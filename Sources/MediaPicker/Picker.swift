import AppKit
import SwiftUI

final class PickerModel: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var warnings: [String] = []
    @Published var loading = true
    @Published var selection = 0
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// F8을 길게 누르면 뜨는 선택 창.
final class PickerController: NSObject, NSWindowDelegate {
    private let controller: MediaController
    private let model = PickerModel()
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var refreshTimer: Timer?
    private var refreshing = false
    /// 손을 떼고 가만히 두면 아무것도 하지 않고 닫는다.
    private let idleTimeout: TimeInterval = 4
    private var idleTimer: Timer?
    /// 음소거 전 볼륨 (항목 id → 볼륨)
    private var volumeBeforeMute: [String: Int] = [:]
    /// 방금 바꾼 볼륨. 플레이어가 새 값을 반영하기 전의 갱신이 막대를 되돌리지 않게 잠시 우선한다.
    private var recentVolumeEdits: [String: (value: Int, at: Date)] = [:]
    private var lastVolumeSend = Date.distantPast

    var isOpen: Bool { panel?.isVisible ?? false }
    /// 선택 창이 열릴 때 (첫 실행 안내의 '직접 해 보기' 확인용)
    var onShow: (() -> Void)?

    init(controller: MediaController) {
        self.controller = controller
    }

    func show() {
        model.items = []
        model.warnings = []
        model.loading = true
        model.selection = 0

        let panel = self.panel ?? makePanel()
        self.panel = panel
        relayout()
        panel.makeKeyAndOrderFront(nil)
        onShow?()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }

        controller.scan { [weak self] result in
            guard let self, self.isOpen else { return }
            // 처음 열 때만 재생 중인 걸 위로 올린다. 이후 갱신에서는 순서를 유지한다.
            self.model.items = result.items.sorted { $0.state == .playing && $1.state != .playing }
            self.model.warnings = result.warnings
            self.model.loading = false
            self.relayout()
        }

        // 떠 있는 동안 곡 제목·재생 상태를 계속 맞춘다.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        touch()
    }

    /// 조작이 있을 때마다 자동 닫힘 시간을 다시 잰다.
    func touch() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
            Log.write("picker: idle close")
            self?.close()
        }
    }

    /// F8 길게(창이 열린 상태): 강조된 항목을 재생/정지하고 닫는다.
    func confirm() {
        pick(model.selection)
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        idleTimer?.invalidate()
        idleTimer = nil
        panel?.orderOut(nil)
    }

    /// F7/F9 또는 ←/→: 강조된 항목을 이전/다음으로 넘기고 창은 그대로 둔다.
    func skipSelected(_ action: MediaAction) {
        touch()
        guard model.items.indices.contains(model.selection) else { return }
        controller.skip(action, item: model.items[model.selection])
        // 플레이어가 곡을 바꾸는 데 시간이 걸린다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refresh() }
    }

    // MARK: - 볼륨

    /// F11/F12: 강조된 항목을 10% 단위로. 현재 값을 10의 배수로 맞춘 뒤 움직인다
    /// (Spotify는 설정값보다 1 낮게 돌려주는 일이 있어 그대로 더하면 어긋난다).
    func adjustVolume(by delta: Int) {
        touch()
        guard let item = selectedItem, let current = item.volume else { return }
        let snapped = Int((Double(current) / 10).rounded()) * 10
        applyVolume(min(100, max(0, snapped + delta)), to: item)
    }

    /// F10: 강조된 항목만 음소거/해제
    func toggleMute() {
        touch()
        guard let item = selectedItem, let current = item.volume else { return }
        if current > 0 {
            volumeBeforeMute[item.id] = current
            applyVolume(0, to: item)
        } else {
            applyVolume(volumeBeforeMute.removeValue(forKey: item.id) ?? 50, to: item)
        }
    }

    /// 막대를 끌 때. 너무 잦은 전송은 건너뛰고, 손을 뗄 때는 꼭 보낸다.
    fileprivate func dragVolume(_ value: Int, index: Int, ended: Bool) {
        touch()
        guard model.items.indices.contains(index), model.items[index].volume != nil else { return }
        model.selection = index
        let item = model.items[index]
        if ended || Date().timeIntervalSince(lastVolumeSend) > 0.08 {
            applyVolume(value, to: item)
        } else {
            setLocalVolume(value, id: item.id)
        }
    }

    private var selectedItem: MediaItem? {
        model.items.indices.contains(model.selection) ? model.items[model.selection] : nil
    }

    private func applyVolume(_ value: Int, to item: MediaItem) {
        setLocalVolume(value, id: item.id)
        lastVolumeSend = Date()
        controller.setVolume(item, to: value)
    }

    private func setLocalVolume(_ value: Int, id: String) {
        recentVolumeEdits[id] = (value, Date())
        if let index = model.items.firstIndex(where: { $0.id == id }) {
            model.items[index].volume = value
        }
    }

    private func refresh() {
        guard isOpen, !model.loading, !refreshing else { return }
        refreshing = true
        controller.scan { [weak self] result in
            guard let self else { return }
            self.refreshing = false
            guard self.isOpen else { return }
            let selectedID = self.model.items.indices.contains(self.model.selection)
                ? self.model.items[self.model.selection].id : nil
            // 기존 순서를 유지하고, 새로 생긴 건 뒤에 붙인다.
            let fresh = Dictionary(result.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var merged = self.model.items.compactMap { fresh[$0.id] }
            merged += result.items.filter { item in !merged.contains { $0.id == item.id } }
            for index in merged.indices {
                if let edit = self.recentVolumeEdits[merged[index].id], Date().timeIntervalSince(edit.at) < 1.5 {
                    merged[index].volume = edit.value
                }
            }
            self.model.items = merged
            self.model.warnings = result.warnings
            if let selectedID, let index = merged.firstIndex(where: { $0.id == selectedID }) {
                self.model.selection = index
            } else {
                self.model.selection = min(self.model.selection, max(merged.count - 1, 0))
            }
            self.relayout()
        }
    }

    func moveSelection(_ delta: Int) {
        touch()
        guard !model.items.isEmpty else { return }
        let n = model.items.count
        model.selection = (model.selection + delta + n) % n
    }

    private func pick(_ index: Int) {
        guard model.items.indices.contains(index) else { return }
        controller.choose(model.items[index], among: model.items)
        close()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        touch()
        switch event.keyCode {
        case 53: close()                                   // esc
        case 125: moveSelection(1)                         // ↓
        case 126: moveSelection(-1)                        // ↑
        case 123: skipSelected(.previous)                  // ←
        case 124: skipSelected(.next)                      // →
        case 36, 76, 49: pick(model.selection)             // return, enter, space
        default:
            guard let c = event.characters, let n = Int(c), (1...9).contains(n) else { return false }
            pick(n - 1)
        }
        return true
    }

    private func makePanel() -> NSPanel {
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PickerView(
            model: model,
            onPick: { [weak self] in self?.pick($0) },
            onVolume: { [weak self] value, index, ended in self?.dragVolume(value, index: index, ended: ended) }
        ))
        return panel
    }

    private func relayout() {
        guard let panel, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrame(NSRect(
            x: frame.midX - size.width / 2,
            y: frame.midY + frame.height * 0.15 - size.height / 2,
            width: size.width,
            height: size.height
        ), display: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

private struct PickerView: View {
    @ObservedObject var model: PickerModel
    let onPick: (Int) -> Void
    let onVolume: (_ value: Int, _ index: Int, _ ended: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Choose what to play"))
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            if model.loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Searching…")).foregroundStyle(.secondary)
                }
                .padding(8)
            } else if model.items.isEmpty {
                Text(L("No media found"))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }

            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                PickerRow(index: index, item: item, selected: index == model.selection,
                          onVolume: { value, ended in onVolume(value, index, ended) })
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(index) }
            }

            ForEach(model.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }

            Text(L("F8 tap: next · hold: play/pause · F7·F9 skip · F10–F12 volume"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
        }
        .padding(12)
        .frame(width: 400, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PickerRow: View {
    let index: Int
    let item: MediaItem
    let selected: Bool
    let onVolume: (_ value: Int, _ ended: Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon(item.bundleID))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                VolumeBar(volume: item.volume, highlighted: selected, onChange: onVolume)
            }
            Spacer(minLength: 8)
            Image(systemName: item.state == .paused ? "pause.fill" : item.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(item.state == .playing ? Color.accentColor : .secondary)
            if index < 9 {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// 볼륨 막대. 끌거나 눌러서 바꿀 수 있다. 조절할 수 없는 항목은 회색 빈 막대.
private struct VolumeBar: View {
    let volume: Int?
    let highlighted: Bool
    let onChange: (_ value: Int, _ ended: Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    if let volume {
                        Capsule()
                            .fill(highlighted ? Color.accentColor : Color.secondary)
                            .frame(width: geo.size.width * CGFloat(volume) / 100)
                    }
                }
                .contentShape(Rectangle())
                .gesture(volume == nil ? nil : DragGesture(minimumDistance: 0)
                    .onChanged { onChange(value(at: $0.location.x, width: geo.size.width), false) }
                    .onEnded { onChange(value(at: $0.location.x, width: geo.size.width), true) })
            }
            .frame(height: 5)
            Text(label)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .animation(.easeOut(duration: 0.12), value: volume)
    }

    private var label: String {
        guard let volume else { return "—" }
        return volume == 0 ? L("Muted") : "\(volume)%"
    }

    private func value(at x: CGFloat, width: CGFloat) -> Int {
        Int((min(max(x / width, 0), 1) * 100).rounded())
    }
}

private func appIcon(_ bundleID: String) -> NSImage {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        return NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) ?? NSImage()
    }
    return NSWorkspace.shared.icon(forFile: url.path)
}
