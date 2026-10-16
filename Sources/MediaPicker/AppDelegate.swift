import Cocoa
import SafariServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let safariExtensionID = "io.github.scutiuy.mediapicker.safari"
    private let bridge = BridgeServer()
    private lazy var controller = MediaController(bridge: bridge)
    private let tap = MediaKeyTap()
    private lazy var picker = PickerController(controller: controller)
    private lazy var onboarding = OnboardingController(actions: .init(
        requestAccessibility: { [weak self] in self?.requestAccessibility() },
        installChromium: { [weak self] in self?.installChromiumExtension() },
        openSafari: { [weak self] in self?.openSafariExtension() },
        connectedBrowsers: { [weak self] in self?.bridge.connectedBrowsers.sorted() ?? [] },
        launchAtLogin: { SMAppService.mainApp.status == .enabled },
        setLaunchAtLogin: { [weak self] on in self?.setLaunchAtLogin(on) }
    ))
    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var retryTimer: Timer?

    /// 이만큼 누르고 있으면 '길게 누름'으로 본다.
    private let holdThreshold: TimeInterval = 0.45
    private var holdTimer: Timer?
    private enum Press { case idle, pending, held }
    private var press = Press.idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")")
        setupStatusItem()
        bridge.start()
        controller.startPolling()
        tap.interceptVolume = { [weak self] in self?.picker.isOpen ?? false }
        picker.onShow = { [weak self] in self?.onboarding.pickerDidShow() }
        tap.onDown = { [weak self] key, isRepeat in
            guard let self else { return }
            switch key {
            // 볼륨은 누르고 있으면 계속 바뀌게, 나머지는 한 번만
            case .volumeUp: self.picker.adjustVolume(by: 10)
            case .volumeDown: self.picker.adjustVolume(by: -10)
            case _ where isRepeat: break
            case .playPause: self.keyDown()
            case .next: self.skip(.next)
            case .previous: self.skip(.previous)
            case .mute: self.picker.toggleMute()
            }
        }
        tap.onUp = { [weak self] key in
            if key == .playPause { self?.keyUp() }
        }
        // 첫 실행이면 안내 화면이 권한 요청을 맡는다(시스템 창이 먼저 튀어나오지 않게).
        let firstRun = !OnboardingController.isDone
        startTap(prompt: !firstRun)
        if firstRun { onboarding.show() }
    }

    // MARK: - F8

    /// F8 한 손 조작 (⌘Tab과 같은 감각): 길게 = 열기/실행, 짧게 = 정지·재개/이동.
    /// - 창 닫힘: 짧게 → 재생 중인 것 정지/마지막 것 재개, 길게 → 선택 창 열기
    /// - 창 열림: 짧게 → 다음 항목으로, 길게 → 강조된 항목 재생/정지하고 닫기
    private func keyDown() {
        let pickerWasOpen = picker.isOpen
        if pickerWasOpen { picker.touch() }
        press = .pending
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
            guard let self, self.press == .pending else { return }
            self.press = .held
            if pickerWasOpen {
                Log.write("F8 hold in picker: confirm")
                self.picker.confirm()
            } else {
                Log.write("F8 hold: picker")
                self.picker.show()
            }
        }
    }

    private func keyUp() {
        holdTimer?.invalidate()
        holdTimer = nil
        if press == .pending {
            if picker.isOpen {
                picker.moveSelection(1)
            } else {
                controller.shortPress()
            }
        }
        press = .idle
    }

    /// F7/F9: 선택 창이 떠 있으면 강조된 항목을, 아니면 재생 중인 것을 넘긴다.
    private func skip(_ action: MediaAction) {
        if picker.isOpen {
            picker.skipSelected(action)
        } else {
            controller.skip(action)
        }
    }

    // MARK: - 권한

    private func startTap(prompt: Bool) {
        if prompt { promptAccessibility() }
        if tap.start() {
            Log.write("event tap ready")
            updateStatusIcon()
            return
        }
        Log.write("event tap unavailable: waiting for Accessibility permission")
        updateStatusIcon()
        // 손쉬운 사용 권한을 줄 때까지 기다린다.
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, self.tap.start() else { return }
            timer.invalidate()
            Log.write("event tap ready")
            self.updateStatusIcon()
        }
    }

    /// 시스템 권한 창을 띄우고 손쉬운 사용 목록에 이 앱을 올린다.
    private func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func requestAccessibility() {
        promptAccessibility()
        openAccessibility()
    }

    // MARK: - 메뉴바

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: L("F8 tap: pause what's playing / resume the last one"), action: nil, keyEquivalent: "")
        menu.addItem(withTitle: L("F8 hold: choose what to play"), action: nil, keyEquivalent: "")
        menu.addItem(withTitle: L("F7 / F9: previous / next for what's playing"), action: nil, keyEquivalent: "")
        menu.addItem(withTitle: L("In the picker, F10 / F11 / F12: mute / volume for that item"), action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Open Picker"), action: #selector(openPicker), keyEquivalent: "p").target = self
        menu.addItem(withTitle: L("Install Browser Extension…"), action: #selector(installExtension), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Setup Guide…"), action: #selector(openOnboarding), keyEquivalent: "").target = self
        loginItem = menu.addItem(withTitle: L("Launch at Login"), action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(.separator())
        statusLine = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: L("Accessibility Permission…"), action: #selector(openAccessibility), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Show Log"), action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Quit MediaPicker"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let browsers = bridge.connectedBrowsers.sorted()
        let parts = [
            tap.isRunning ? "F8 ✓" : L("F8 ✗ needs permission"),
            browsers.isEmpty ? L("No extension connected") : L("Extension: %@", browsers.joined(separator: ", ")),
            L("Scan %.2fs", controller.lastScanSeconds),
        ]
        statusLine.title = parts.joined(separator: "  ·  ")
    }

    private func updateStatusIcon() {
        let ok = tap.isRunning
        let symbol = ok ? "playpause.fill" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MediaPicker")
        statusItem.button?.toolTip = ok ? "MediaPicker" : L("MediaPicker needs Accessibility permission")
    }

    @objc private func openPicker() {
        // 메뉴가 닫힌 뒤에 띄워야 창이 바로 닫히지 않는다.
        DispatchQueue.main.async { self.picker.show() }
    }

    /// 사파리는 앱에 든 확장(.appex)을 켜기만 하면 되고, 크롬 계열은 압축해제된 확장을 직접 로드해야 한다.
    @objc private func installExtension() {
        let alert = NSAlert()
        alert.messageText = L("Install Browser Extension")
        alert.informativeText = L("With the extension, MediaPicker controls each browser tab directly. You don't need to allow JavaScript from Apple Events.")
        alert.addButton(withTitle: L("Chrome, Edge, Brave, Arc…"))
        alert.addButton(withTitle: L("Safari…"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: installChromiumExtension()
        case .alertSecondButtonReturn: openSafariExtension()
        default: break
        }
    }

    private func openSafariExtension() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: Self.safariExtensionID) { error in
            if let error { Log.write("safari extension settings failed \(error)") }
        }
    }

    /// 앱에 들어 있는 확장을 고정된 위치로 복사해 두고, 그 폴더를 보여 준다.
    /// ('압축해제된 확장 프로그램 로드'는 폴더 경로를 기억하므로 앱을 옮겨도 안 깨지게)
    private func installChromiumExtension() {
        guard let source = Bundle.main.url(forResource: "Extension", withExtension: nil) else { return }
        let target = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MediaPicker/Extension")
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            Log.write("extension copy failed \(error)")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])

        let alert = NSAlert()
        alert.messageText = L("Install in Chrome, Edge, Brave or Arc")
        alert.informativeText = L("1. Go to chrome://extensions\n2. Turn on Developer mode (top right)\n3. Click Load unpacked and choose the Extension folder that just opened")
        alert.addButton(withTitle: L("OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openOnboarding() {
        DispatchQueue.main.async { self.onboarding.show() }
    }

    @objc private func toggleLogin() {
        setLaunchAtLogin(SMAppService.mainApp.status != .enabled)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.write("login item failed \(error)")
        }
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }
}
