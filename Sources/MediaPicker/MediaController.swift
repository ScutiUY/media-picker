import Foundation

/// 어떤 미디어를 재생·정지할지 결정한다. 상태는 모두 Script.queue 위에서만 만진다.
final class MediaController {
    private let players: [MediaProvider] = [
        PlayerAppProvider(bundleID: "com.spotify.client", appName: "Spotify"),
        PlayerAppProvider(bundleID: "com.apple.Music", appName: "Music"),
        PlayerAppProvider(bundleID: "com.apple.TV", appName: "TV"),
        VLCProvider(),
    ]
    private let soundingApps = SoundingAppProvider()
    private let scriptedBrowserIDs: Set<String> = [
        "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser",
        "com.microsoft.edgemac", "com.apple.Safari",
    ]
    /// AppleScript 경로. 확장이 연결된 브라우저는 건너뛴다.
    private let scriptedBrowsers: [(name: String, provider: MediaProvider)] = [
        ("Chrome", ChromiumProvider(bundleID: "com.google.Chrome", appName: "Chrome")),
        ("Arc", ChromiumProvider(bundleID: "company.thebrowser.Browser", appName: "Arc")),
        ("Brave", ChromiumProvider(bundleID: "com.brave.Browser", appName: "Brave")),
        ("Edge", ChromiumProvider(bundleID: "com.microsoft.edgemac", appName: "Edge")),
        ("Safari", SafariProvider()),
    ]
    private let bridge: BridgeServer
    private let extensionTabs: ExtensionProvider

    init(bridge: BridgeServer) {
        self.bridge = bridge
        self.extensionTabs = ExtensionProvider(bridge: bridge)
    }
    private var playerIDs: Set<String> { ["com.spotify.client", "com.apple.Music", "com.apple.TV", "org.videolan.vlc"] }

    /// 마지막으로 재생 중이던(또는 고른) 대상. 아무것도 재생 중이 아닐 때 F8이 이걸 다시 재생한다.
    private var lastTarget: String?
    private var pollTimer: Timer?

    /// 진단용 (메인 스레드에서 읽음)
    private(set) var lastScanSeconds: Double = 0
    private(set) var lastWarnings: [String] = []

    /// 음악 앱은 가볍게 주기적으로 확인해, 앱 안에서 직접 재생·정지한 것도 '마지막 대상'으로 기억한다.
    /// (모르면 F8이 시스템으로 넘어가 유튜브가 켜지는 원래 문제로 돌아간다)
    func startPolling(interval: TimeInterval = 3) {
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Script.queue.async { _ = self.scan(self.players + [self.extensionTabs], browsersScanned: false) }
        }
    }

    /// `browsersScanned`가 false면(가벼운 폴링) 브라우저 탭을 훑지 않았으므로,
    /// 브라우저 소리를 '알 수 없는 앱'으로 오해하지 않게 제외한다.
    private func scan(_ providers: [MediaProvider], browsersScanned: Bool = true) -> ScanResult {
        let start = Date()
        var result = providers.reduce(into: ScanResult()) { acc, provider in
            let r = provider.scan()
            acc.items += r.items
            acc.warnings += r.warnings
        }
        // 정지 직후에도 잠깐 소리 출력이 남으므로, 항목을 낸 앱은 재생 여부와 관계없이 제외한다.
        var handled = Set(result.items.map(\.bundleID)).union(bridge.connectedBundleIDs)
        if !browsersScanned { handled.formUnion(scriptedBrowserIDs) }
        result.items += soundingApps.scan(excluding: handled)
        if let playing = result.items.first(where: { $0.state == .playing }), playing.id != lastTarget {
            lastTarget = playing.id
            Log.write("now playing: \(playing.id)")
        }
        let elapsed = Date().timeIntervalSince(start)
        let warnings = result.warnings
        DispatchQueue.main.async {
            self.lastScanSeconds = elapsed
            self.lastWarnings = warnings
        }
        return result
    }

    private func scanAll() -> ScanResult {
        let viaExtension = bridge.connectedBrowsers
        let scripted = scriptedBrowsers.filter { !viaExtension.contains($0.name) }.map(\.provider)
        return scan(players + [extensionTabs] + scripted)
    }

    func scan(completion: @escaping (ScanResult) -> Void) {
        Script.queue.async {
            let result = self.scanAll()
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// F8 짧게: 재생 중인 게 있으면 정지, 없으면 마지막 대상을 다시 재생.
    func shortPress() {
        Script.queue.async {
            let items = self.scanAll().items
            let playing = items.filter { $0.state == .playing }
            if !playing.isEmpty {
                Log.write("short press: pause \(playing.map(\.id))")
                // 먼저 기억해 둔다. 시스템 키가 엉뚱한 앱으로 가면 pause()가 이 기억을 지운다.
                self.lastTarget = playing[0].id
                self.pause(playing)
            } else if let last = self.lastTarget, last.hasPrefix(SoundingAppProvider.idPrefix) {
                // 소리로만 알던 앱은 멈추면 목록에서 사라진다. 시스템 키로 다시 재생한다.
                Log.write("short press: resume \(last) via system key")
                DispatchQueue.main.async { MediaKeyTap.postSystemKey(MediaKeyTap.playKey) }
            } else if let target = items.first(where: { $0.id == self.lastTarget })
                        ?? items.first(where: { self.playerIDs.contains($0.id) }) {
                // 기억한 대상이 없으면 브라우저 탭보다 음악 앱을 먼저 고른다.
                Log.write("short press: play \(target.id)")
                target.perform(.play)
                self.lastTarget = target.id
            } else {
                Log.write("short press: no known target, pass through to system")
                DispatchQueue.main.async { MediaKeyTap.postSystemKey(MediaKeyTap.playKey) }
            }
        }
    }

    /// F7/F9: 재생 중인 것(없으면 마지막 대상)을 이전/다음으로.
    func skip(_ action: MediaAction) {
        Script.queue.async {
            let items = self.scanAll().items
            if let target = items.first(where: { $0.state == .playing })
                ?? items.first(where: { $0.id == self.lastTarget }) {
                Log.write("skip \(action.rawValue): \(target.id)")
                target.perform(action)
            } else {
                Log.write("skip \(action.rawValue): no known target, pass through to system")
                DispatchQueue.main.async { MediaKeyTap.postSystemKey(action == .next ? MediaKeyTap.nextKey : MediaKeyTap.previousKey) }
            }
        }
    }

    func setVolume(_ item: MediaItem, to value: Int) {
        guard let set = item.setVolume else { return }
        Script.queue.async { set(value) }
    }

    /// 선택 창에서 F7/F9로 강조된 항목만 넘긴다.
    func skip(_ action: MediaAction, item: MediaItem) {
        Script.queue.async {
            Log.write("picker skip \(action.rawValue): \(item.id)")
            item.perform(action)
        }
    }

    /// 시스템 키로만 조작하는 앱은 여러 개여도 키를 한 번만 보낸다(두 번이면 다시 재생된다).
    private func pause(_ items: [MediaItem]) {
        let viaSystemKey = items.filter { $0.id.hasPrefix(SoundingAppProvider.idPrefix) }
        items.filter { !$0.id.hasPrefix(SoundingAppProvider.idPrefix) }.forEach { $0.perform(.pause) }
        if let item = viaSystemKey.first { pauseViaSystemKey(item) }
    }

    /// 시스템 키는 macOS가 '지금 재생 중'으로 아는 앱에 간다. 엉뚱한 앱(예: 멈춰 있던 Spotify)이
    /// 받으면 그 앱이 재생되므로, 보낸 뒤 확인해서 새로 켜진 앱은 바로 다시 멈춘다. Script.queue 위에서 호출.
    private func pauseViaSystemKey(_ item: MediaItem) {
        let before = scan(players + [extensionTabs], browsersScanned: false).items
        let wasPlaying = Set(before.filter { $0.state == .playing }.map(\.id))
        item.perform(.pause)
        Thread.sleep(forTimeInterval: 0.8)
        let after = scan(players + [extensionTabs], browsersScanned: false).items
        let misrouted = after.filter {
            $0.state == .playing && !wasPlaying.contains($0.id) && !$0.id.hasPrefix(SoundingAppProvider.idPrefix)
        }
        for wrong in misrouted {
            Log.write("system key misrouted to \(wrong.id); pausing it again")
            wrong.perform(.pause)
        }
        if !misrouted.isEmpty {
            // 원래 대상은 시스템 키로 멈출 수 없었다. 다음 F8이 엉뚱한 앱을 다시 켜지 않게 기억을 지운다.
            lastTarget = nil
        }
    }

    /// 선택 창에서 고른 항목: 재생 중이면 정지, 멈춰 있으면 다른 것을 멈추고 이걸 재생.
    func choose(_ item: MediaItem, among items: [MediaItem]) {
        Script.queue.async {
            if item.state == .playing {
                Log.write("picker: pause \(item.id)")
                item.perform(.pause)
            } else {
                Log.write("picker: play \(item.id)")
                self.pause(items.filter { $0.state == .playing && $0.id != item.id })
                item.perform(.play)
            }
            if item.state != .playing || !item.id.hasPrefix(SoundingAppProvider.idPrefix) {
                self.lastTarget = item.id
            }
        }
    }
}
