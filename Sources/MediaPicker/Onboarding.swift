import AppKit
import SwiftUI

/// 첫 실행 안내: 소개 → 손쉬운 사용 권한 → 브라우저 확장(선택) → F8 직접 눌러 보기.
/// 권한·확장 연결·F8 시도는 실제 상태를 지켜보다가 바로 체크로 바뀐다.
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, accessibility, browser, tryIt }

    @Published var step = Step.welcome
    @Published var trusted = false
    @Published var browsers: [String] = []
    @Published var triedPicker = false
    @Published var launchAtLogin = false
}

final class OnboardingController: NSObject, NSWindowDelegate {
    static let doneKey = "onboardingDone"
    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    struct Actions {
        let requestAccessibility: () -> Void
        let installChromium: () -> Void
        let openSafari: () -> Void
        let connectedBrowsers: () -> [String]
        let launchAtLogin: () -> Bool
        let setLaunchAtLogin: (Bool) -> Void
    }

    let model = OnboardingModel()
    private let actions: Actions
    private var window: NSWindow?
    private var pollTimer: Timer?

    init(actions: Actions) {
        self.actions = actions
    }

    var isOpen: Bool { window?.isVisible ?? false }

    func show() {
        model.step = .welcome
        model.launchAtLogin = actions.launchAtLogin()
        poll()
        let window = self.window ?? makeWindow()
        self.window = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
    }

    /// 선택 창이 열리면 '직접 해 보기' 단계를 통과시킨다.
    func pickerDidShow() {
        model.triedPicker = true
    }

    private func poll() {
        model.trusted = AXIsProcessTrusted()
        model.browsers = actions.connectedBrowsers()
    }

    private func finish() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // 중간에 닫아도 다시 조르지 않는다. 메뉴에서 언제든 다시 열 수 있다.
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func makeWindow() -> NSWindow {
        let view = OnboardingView(
            model: model,
            requestAccessibility: actions.requestAccessibility,
            installChromium: actions.installChromium,
            openSafari: actions.openSafari,
            setLaunchAtLogin: { [weak self] on in
                self?.actions.setLaunchAtLogin(on)
                self?.model.launchAtLogin = self?.actions.launchAtLogin() ?? on
            },
            finish: { [weak self] in self?.finish() }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 370),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: view)
        return window
    }
}

// MARK: - 화면

private struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let requestAccessibility: () -> Void
    let installChromium: () -> Void
    let openSafari: () -> Void
    let setLaunchAtLogin: (Bool) -> Void
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case .welcome: welcome
                case .accessibility: accessibility
                case .browser: browser
                case .tryIt: tryIt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 36)
            .padding(.top, 40)

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
        }
        .frame(width: 520, height: 370)
    }

    // MARK: 단계

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "playpause.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text(L("Hold F8 to choose what plays"))
                .font(.title.bold())
            Text(L("A paused YouTube tab won't steal the play key anymore. MediaPicker sends the media keys where you meant, and lets you switch players without taking your hand off the keyboard."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Setup takes about a minute."))
                .foregroundStyle(.secondary)
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("hand.raised.fill", L("Allow Accessibility"))
            Text(L("MediaPicker needs Accessibility permission to catch the media keys before macOS sends them to another app. It doesn't read anything you type."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Turn on MediaPicker in the list that opens. If it's already there, turn it off and on again."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(L("Open Accessibility Settings"), action: requestAccessibility)
                    .controlSize(.large)
                status(model.trusted, on: L("Allowed"), off: L("Waiting for permission…"))
            }
            .padding(.top, 4)
        }
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("globe", L("Browser tabs (optional)"))
            Text(L("Install the browser extension to see each YouTube or Netflix tab in the picker and control it directly. You can skip this and do it later from the menu bar."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(L("Chrome, Edge, Brave, Arc…"), action: installChromium)
                Button(L("Safari…"), action: openSafari)
            }
            .controlSize(.large)
            .padding(.top, 4)
            status(!model.browsers.isEmpty,
                   on: L("Connected: %@", model.browsers.joined(separator: ", ")),
                   off: L("No extension connected"))
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("keyboard", L("Try it"))
            VStack(alignment: .leading, spacing: 8) {
                keyRow("F8", L("Tap: pause what's playing / resume the last one"))
                keyRow("F8", L("Hold: open the picker. Then tap to move, hold to play"))
                keyRow("F7 F9", L("Previous / next"))
                keyRow("F10–F12", L("In the picker: volume for that item only"))
            }
            status(model.triedPicker, on: L("Nice! That's all there is to it."), off: L("Hold F8 now to open the picker."))
                .padding(.top, 4)
            Toggle(L("Launch at Login"), isOn: Binding(get: { model.launchAtLogin }, set: setLaunchAtLogin))
                .toggleStyle(.checkbox)
        }
    }

    // MARK: 하단

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                    Circle()
                        .fill(step == model.step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if model.step != .welcome {
                Button(L("Back")) { move(-1) }
            }
            switch model.step {
            case .tryIt:
                Button(L("Done"), action: finish)
                    .keyboardShortcut(.defaultAction)
            case .accessibility where !model.trusted:
                Button(L("Skip")) { move(1) }
                Button(L("Continue")) { move(1) }
                    .disabled(true)
            default:
                Button(model.step == .welcome ? L("Get Started") : L("Continue")) { move(1) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }

    private func move(_ delta: Int) {
        if let next = OnboardingModel.Step(rawValue: model.step.rawValue + delta) {
            model.step = next
        }
    }

    // MARK: 부품

    private func header(_ symbol: String, _ title: String) -> some View {
        Label {
            Text(title).font(.title2.bold())
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
    }

    private func status(_ ok: Bool, on: String, off: String) -> some View {
        Label {
            Text(ok ? on : off)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(ok ? Color.green : Color.secondary)
        }
        .animation(.easeOut(duration: 0.2), value: ok)
    }

    private func keyRow(_ key: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 72, alignment: .leading)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
