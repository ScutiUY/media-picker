import AppKit

enum PlayState { case playing, paused }
enum MediaAction: String { case play, pause, next, previous }

struct MediaItem: Identifiable {
    /// 스캔 사이에도 유지되는 키 ("com.spotify.client", "com.google.Chrome:12:345" …)
    let id: String
    let bundleID: String
    let title: String
    let subtitle: String
    let state: PlayState
    /// Script.queue 위에서 호출해야 한다.
    let perform: (MediaAction) -> Void
    /// 0–100. nil이면 이 항목은 볼륨을 조절할 수 없다.
    var volume: Int? = nil
    /// Script.queue 위에서 호출해야 한다.
    var setVolume: ((Int) -> Void)? = nil
}

struct ScanResult {
    var items: [MediaItem] = []
    var warnings: [String] = []
}

protocol MediaProvider {
    /// Script.queue 위에서 호출된다.
    func scan() -> ScanResult
}

func isRunning(_ bundleID: String) -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
}

// MARK: - Spotify / Music

struct PlayerAppProvider: MediaProvider {
    let bundleID: String
    let appName: String

    func scan() -> ScanResult {
        guard isRunning(bundleID) else { return ScanResult() }
        let source = """
        tell application id "\(bundleID)"
            set s to player state as string
            set t to ""
            set a to ""
            set v to ""
            try
                set t to name of current track
                set a to artist of current track
            end try
            try
                set v to sound volume as string
            end try
        end tell
        return s & linefeed & t & linefeed & a & linefeed & v
        """
        switch Script.run(source) {
        case .failure(let error):
            return ScanResult(warnings: [error.hint(app: appName)])
        case .success(let output):
            let parts = output.components(separatedBy: "\n")
            let state: PlayState = parts[0] == "playing" ? .playing : .paused
            let title = parts.count > 1 ? parts[1] : ""
            let artist = parts.count > 2 ? parts[2] : ""
            let volume = parts.count > 3 ? Int(parts[3]) : nil
            if title.isEmpty && state == .paused { return ScanResult() }
            let bundleID = bundleID
            let item = MediaItem(
                id: bundleID,
                bundleID: bundleID,
                title: title.isEmpty ? appName : title,
                subtitle: artist.isEmpty ? appName : "\(appName) · \(artist)",
                state: state,
                perform: { action in
                    let command = switch action {
                    case .play: "play"
                    case .pause: "pause"
                    case .next: "next track"
                    case .previous: "previous track"
                    }
                    Script.run("tell application id \"\(bundleID)\" to \(command)")
                },
                volume: volume,
                setVolume: volume == nil ? nil : { value in
                    Script.run("tell application id \"\(bundleID)\" to set sound volume to \(value)")
                }
            )
            return ScanResult(items: [item])
        }
    }
}

// MARK: - VLC

struct VLCProvider: MediaProvider {
    let bundleID = "org.videolan.vlc"

    func scan() -> ScanResult {
        guard isRunning(bundleID) else { return ScanResult() }
        let source = """
        tell application id "\(bundleID)"
            set p to playing
            set t to ""
            set v to ""
            try
                set t to name of current item
            end try
            try
                set v to audio volume as string
            end try
        end tell
        return (p as string) & linefeed & t & linefeed & v
        """
        switch Script.run(source) {
        case .failure(let error):
            return ScanResult(warnings: [error.hint(app: "VLC")])
        case .success(let output):
            let parts = output.components(separatedBy: "\n")
            let state: PlayState = parts[0] == "true" ? .playing : .paused
            let title = parts.count > 1 ? parts[1] : ""
            // VLC의 audio volume은 256이 100%다.
            let volume = parts.count > 2 ? Int(parts[2]).map { min(100, $0 * 100 / 256) } : nil
            if title.isEmpty && state == .paused { return ScanResult() }
            let bundleID = bundleID
            let item = MediaItem(
                id: bundleID,
                bundleID: bundleID,
                title: title.isEmpty ? "VLC" : title,
                subtitle: "VLC",
                state: state,
                perform: { action in
                    // VLC의 play는 재생/일시정지 토글이다.
                    let command = switch action {
                    case .play: "if not playing then play"
                    case .pause: "if playing then play"
                    case .next: "next"
                    case .previous: "previous"
                    }
                    Script.run("tell application id \"\(bundleID)\" to \(command)")
                },
                volume: volume,
                setVolume: volume == nil ? nil : { value in
                    Script.run("tell application id \"\(bundleID)\" to set audio volume to \(value * 256 / 100)")
                }
            )
            return ScanResult(items: [item])
        }
    }
}

// MARK: - 브라우저 탭

enum PageJS {
    /// 탭 안의 소리 나는(음소거 아님) 미디어 상태를 "playing|제목" 형태로 돌려준다.
    static let probe = #"(() => { const m = [...document.querySelectorAll('video,audio')].filter(e => e.duration > 0 && !e.muted); if (!m.length) return ''; const e = m.find(e => !e.paused) || m[0]; return (e.paused ? 'paused' : 'playing') + '|' + Math.round(e.volume * 100) + '|' + document.title.replace(/\s+/g, ' '); })()"#

    static func setVolume(_ value: Int) -> String {
        "(() => { document.querySelectorAll('video,audio').forEach(e => { e.volume = \(value) / 100; }); return 'ok'; })()"
    }

    static func action(_ action: MediaAction) -> String {
        switch action {
        case .pause:
            return #"(() => { document.querySelectorAll('video,audio').forEach(e => e.pause()); return 'ok'; })()"#
        case .play:
            return #"(() => { const m = [...document.querySelectorAll('video,audio')].filter(e => e.duration > 0 && !e.muted); if (m[0]) m[0].play(); return 'ok'; })()"#
        case .next, .previous:
            return "(() => { \(skipSource) return mediaPickerSkip('\(action.rawValue)'); })()"
        }
    }

    /// 확장과 같은 다음/이전 처리 코드 (Extension/media-actions.js)
    private static let skipSource: String = {
        guard let url = Bundle.main.url(forResource: "media-actions", withExtension: "js", subdirectory: "Extension"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "var mediaPickerSkip = () => 'none';" }
        return source
    }()
}

/// 스캔 스크립트 출력 한 줄: 창id \t 탭키 \t URL \t 상태|볼륨|제목
///
/// 보안: 상태 부분은 웹페이지 안에서 실행한 JS의 결과라서 페이지가 마음대로 꾸밀 수 있다
/// (줄바꿈·탭을 넣어 가짜 줄을 만드는 것까지). 창id·탭키는 AppleScript에 그대로 들어가므로
/// 반드시 정수로 검사한다. 정수가 아니면 그 줄은 버린다.
private func parseTabLines(_ output: String) -> [(window: Int, tab: Int, url: String, state: PlayState, volume: Int?, title: String)] {
    output.split(separator: "\n").compactMap { line in
        let cols = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard cols.count == 4, let window = Int(cols[0]), let tab = Int(cols[1]) else { return nil }
        let probe = cols[3].split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard probe.count == 3 else { return nil }
        return (window, tab, cols[2], probe[0] == "playing" ? .playing : .paused, Int(probe[1]), probe[2])
    }
}

func host(_ url: String) -> String {
    URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? url
}

/// Chrome 계열(Chrome, Arc, Brave, Edge)은 같은 AppleScript 사전을 쓴다.
struct ChromiumProvider: MediaProvider {
    let bundleID: String
    let appName: String

    func scan() -> ScanResult {
        guard isRunning(bundleID) else { return ScanResult() }
        let source = """
        set TB to character id 9
        set out to ""
        set jsErr to ""
        tell application id "\(bundleID)"
            repeat with w in windows
                set wid to id of w
                repeat with t in tabs of w
                    set u to URL of t
                    if u starts with "http" then
                        try
                            with timeout of 2 seconds
                                set r to execute t javascript \(Script.quote(PageJS.probe))
                            end timeout
                            if r is not missing value and r is not "" then set out to out & wid & TB & (id of t) & TB & u & TB & r & linefeed
                        on error msg
                            set jsErr to msg
                        end try
                    end if
                end repeat
            end repeat
        end tell
        if out is "" and jsErr is not "" then error jsErr
        return out
        """
        switch Script.run(source) {
        case .failure(let error):
            return ScanResult(warnings: [error.hint(app: appName)])
        case .success(let output):
            let bundleID = bundleID
            let items = parseTabLines(output).map { tab in
                MediaItem(
                    id: "\(bundleID):\(tab.window):\(tab.tab)",
                    bundleID: bundleID,
                    title: tab.title,
                    subtitle: "\(appName) · \(host(tab.url))",
                    state: tab.state,
                    perform: { action in
                        Script.run("tell application id \"\(bundleID)\" to execute (tab id \(tab.tab) of window id \(tab.window)) javascript \(Script.quote(PageJS.action(action)))")
                    },
                    volume: tab.volume,
                    setVolume: { value in
                        Script.run("tell application id \"\(bundleID)\" to execute (tab id \(tab.tab) of window id \(tab.window)) javascript \(Script.quote(PageJS.setVolume(value)))")
                    }
                )
            }
            return ScanResult(items: items)
        }
    }
}

struct SafariProvider: MediaProvider {
    let bundleID = "com.apple.Safari"

    func scan() -> ScanResult {
        guard isRunning(bundleID) else { return ScanResult() }
        let source = """
        set TB to character id 9
        set out to ""
        set jsErr to ""
        tell application id "\(bundleID)"
            repeat with w in windows
                set wid to id of w
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    set u to URL of t
                    if u is not missing value and u starts with "http" then
                        try
                            with timeout of 2 seconds
                                set r to do JavaScript \(Script.quote(PageJS.probe)) in t
                            end timeout
                            if r is not missing value and r is not "" then set out to out & wid & TB & i & TB & u & TB & r & linefeed
                        on error msg
                            set jsErr to msg
                        end try
                    end if
                end repeat
            end repeat
        end tell
        if out is "" and jsErr is not "" then error jsErr
        return out
        """
        switch Script.run(source) {
        case .failure(let error):
            return ScanResult(warnings: [error.hint(app: "Safari")])
        case .success(let output):
            let bundleID = bundleID
            let items = parseTabLines(output).map { tab in
                MediaItem(
                    id: "\(bundleID):\(tab.window):\(tab.tab)",
                    bundleID: bundleID,
                    title: tab.title,
                    subtitle: "Safari · \(host(tab.url))",
                    state: tab.state,
                    perform: { action in
                        Script.run("tell application id \"\(bundleID)\" to do JavaScript \(Script.quote(PageJS.action(action))) in tab \(tab.tab) of window id \(tab.window)")
                    },
                    volume: tab.volume,
                    setVolume: { value in
                        Script.run("tell application id \"\(bundleID)\" to do JavaScript \(Script.quote(PageJS.setVolume(value))) in tab \(tab.tab) of window id \(tab.window)")
                    }
                )
            }
            return ScanResult(items: items)
        }
    }
}
