import Foundation
import Network

/// 브라우저 확장과 붙는 로컬 WebSocket 서버(127.0.0.1 전용).
/// 확장이 탭별 재생 상태를 밀어 넣고, 앱은 재생·정지 명령을 보낸다.
/// 덕분에 브라우저의 'Apple Events JavaScript 허용' 없이도 탭을 다룬다.
final class BridgeServer {
    static let port: UInt16 = 17872

    struct Tab: Decodable {
        let id: Int
        let title: String
        let url: String
        let state: String
        let volume: Int?
    }

    struct Client {
        let key: ObjectIdentifier
        let browser: String
        let tabs: [Tab]
    }

    private struct Incoming: Decodable {
        let type: String
        let browser: String?
        let tabs: [Tab]?
    }

    private final class Connection {
        let nw: NWConnection
        var browser = "Chrome"
        var tabs: [Tab] = []
        init(_ nw: NWConnection) { self.nw = nw }
    }

    private let queue = DispatchQueue(label: "mediapicker.bridge")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: Connection] = [:] // queue 전용
    private var keepAlive: DispatchSourceTimer?

    func start() {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        // 탭 목록 하나가 이보다 클 일은 없다. 비정상적으로 큰 메시지로 메모리를 채우지 못하게 막는다.
        ws.maximumMessageSize = 1 << 20
        // 웹페이지가 localhost로 붙는 것을 막는다: 확장 출처만 받는다.
        ws.setClientRequestHandler(queue) { _, headers in
            let origin = headers.first { $0.name.lowercased() == "origin" }?.value ?? ""
            let allowed = ["chrome-extension://", "moz-extension://", "safari-web-extension://"]
                .contains { origin.hasPrefix($0) }
            if !allowed { Log.write("bridge: rejected origin \(origin)") }
            return NWProtocolWebSocket.Response(status: allowed ? .accept : .reject, subprotocol: nil)
        }
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params)
        } catch {
            Log.write("bridge: listener failed \(error)")
            return
        }
        listener?.stateUpdateHandler = { Log.write("bridge: \($0)") }
        listener?.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener?.start(queue: queue)

        // MV3 서비스 워커는 메시지가 오가야 살아 있다.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 20, repeating: 20)
        timer.setEventHandler { [weak self] in
            self?.connections.values.forEach { self?.send(["type": "ping"], to: $0.nw) }
        }
        timer.resume()
        keepAlive = timer
    }

    // MARK: - 다른 스레드에서 읽기

    func snapshot() -> [Client] {
        queue.sync {
            connections.map { Client(key: $0.key, browser: $0.value.browser, tabs: $0.value.tabs) }
        }
    }

    var connectedBrowsers: Set<String> { Set(snapshot().map(\.browser)) }

    /// 확장으로 연결된 브라우저의 번들 ID. 이 브라우저들은 시스템 키 대신 확장으로만 조작한다.
    var connectedBundleIDs: Set<String> {
        Set(connectedBrowsers.compactMap { ExtensionProvider.bundleIDs[$0] })
    }

    func setVolume(_ client: ObjectIdentifier, tab: Int, value: Int) {
        queue.async {
            guard let conn = self.connections[client] else { return }
            self.send(["type": "command", "tabId": tab, "action": "volume", "value": value], to: conn.nw)
        }
    }

    func command(_ client: ObjectIdentifier, tab: Int, action: MediaAction) {
        queue.async {
            guard let conn = self.connections[client] else { return }
            self.send(["type": "command", "tabId": tab, "action": action.rawValue], to: conn.nw)
        }
    }

    // MARK: - 연결

    private func accept(_ nw: NWConnection) {
        let key = ObjectIdentifier(nw)
        connections[key] = Connection(nw)
        nw.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections[key] = nil
                Log.write("bridge: client left")
            default: break
            }
        }
        nw.start(queue: queue)
        receive(nw)
    }

    private func receive(_ nw: NWConnection) {
        nw.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               meta.opcode == .close {
                nw.cancel()
                return
            }
            if let data, !data.isEmpty { self.handle(data, from: nw) }
            if error == nil { self.receive(nw) } else { nw.cancel() }
        }
    }

    private func handle(_ data: Data, from nw: NWConnection) {
        guard let message = try? JSONDecoder().decode(Incoming.self, from: data),
              let conn = connections[ObjectIdentifier(nw)] else { return }
        switch message.type {
        case "hello":
            conn.browser = message.browser ?? "Chrome"
            Log.write("bridge: \(conn.browser) extension connected")
        case "state":
            let tabs = message.tabs ?? []
            if tabs.count != conn.tabs.count {
                Log.write("bridge: \(conn.browser) media tabs \(conn.tabs.count) → \(tabs.count)")
            }
            conn.tabs = tabs
        default:
            break
        }
    }

    private func send(_ object: [String: Any], to nw: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [meta])
        nw.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }
}

/// 확장으로 연결된 브라우저의 탭들. 캐시를 읽기만 하므로 즉시 끝난다.
struct ExtensionProvider: MediaProvider {
    let bridge: BridgeServer

    static let bundleIDs = [
        "Chrome": "com.google.Chrome",
        "Edge": "com.microsoft.edgemac",
        "Brave": "com.brave.Browser",
        "Opera": "com.operasoftware.Opera",
        "Arc": "company.thebrowser.Browser",
        "Safari": "com.apple.Safari",
    ]

    func scan() -> ScanResult {
        let bridge = bridge
        let items = bridge.snapshot().flatMap { client in
            client.tabs.map { tab in
                MediaItem(
                    id: "ext:\(client.browser):\(tab.id)",
                    bundleID: Self.bundleIDs[client.browser] ?? "com.google.Chrome",
                    title: tab.title,
                    subtitle: "\(client.browser) · \(host(tab.url))",
                    state: tab.state == "playing" ? .playing : .paused,
                    perform: { action in bridge.command(client.key, tab: tab.id, action: action) },
                    volume: tab.volume,
                    setVolume: tab.volume == nil ? nil : { value in bridge.setVolume(client.key, tab: tab.id, value: value) }
                )
            }
        }
        return ScanResult(items: items)
    }
}
