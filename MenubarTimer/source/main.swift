import AppKit
import SwiftUI

enum TimerColor: String, Codable, CaseIterable {
    case indigo, mint, sky, amber, rose, violet

    var tint: Color {
        switch self {
        case .indigo: return Color(red: 0.42, green: 0.40, blue: 0.88)
        case .mint: return Color(red: 0.07, green: 0.64, blue: 0.47)
        case .sky: return Color(red: 0.10, green: 0.57, blue: 0.85)
        case .amber: return Color(red: 0.90, green: 0.55, blue: 0.12)
        case .rose: return Color(red: 0.89, green: 0.31, blue: 0.48)
        case .violet: return Color(red: 0.65, green: 0.33, blue: 0.85)
        }
    }
}

struct Countdown: Codable, Identifiable {
    let id: UUID
    let minutes: Int
    let deadline: Date
    var name: String? = nil
    var color: TimerColor? = nil
    var icon: String? = nil

    var title: String { name ?? "\(minutes)-minute timer" }
    var tint: Color { (color ?? .indigo).tint }
}

final class Timers: ObservableObject {
    @Published var active: [Countdown] = []
    @Published var now = Date()
    @Published var finished: [Countdown] = []
    var refresh: (() -> Void)?
    private let key = "activeCountdowns"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Countdown].self, from: data) {
            active = saved
        }
    }

    @discardableResult
    func start(_ minutes: Int, name: String = "", color: TimerColor = .indigo) -> UUID? {
        guard (1...60).contains(minutes) else { return nil }
        let id = UUID()
        let start = Date()
        active.append(Countdown(id: id, minutes: minutes,
                                deadline: start.addingTimeInterval(Double(minutes * 60)),
                                name: normalizedName(name), color: color))
        tick()
        save()
        return id
    }

    func update(_ id: UUID, name: String, color: TimerColor, icon: String? = nil) {
        guard let index = active.firstIndex(where: { $0.id == id }) else { return }
        active[index].name = normalizedName(name)
        active[index].color = color
        if let icon { active[index].icon = icon }
        save()
        refresh?()
    }

    private func normalizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(60))
    }

    func fractionRemaining(_ timer: Countdown) -> Double {
        min(1, max(0, timer.deadline.timeIntervalSince(now) / Double(timer.minutes * 60)))
    }

    func cancel(_ id: UUID) {
        active.removeAll { $0.id == id }
        save()
        refresh?()
    }

    func tick() {
        now = Date()
        let expired = active.filter { $0.deadline <= now }
        if !expired.isEmpty {
            active.removeAll { $0.deadline <= now }
            finished.append(contentsOf: expired)
            save()
            NSSound.beep()
        }
        refresh?()
    }

    func remaining(_ timer: Countdown) -> String {
        let seconds = max(0, Int(ceil(timer.deadline.timeIntervalSince(now))))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(active) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct TimerMenu: View {
    @ObservedObject var timers: Timers
    @ObservedObject var presets: Presets
    let showTrackers: () -> Void
    @State private var managingPresets = false
    @State private var minutes = 5.0
    @State private var name = ""
    @State private var color = TimerColor.indigo
    @State private var editing: UUID?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TimerColor.indigo.tint)
                    .frame(width: 36, height: 36)
                    .background(TimerColor.indigo.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                Text("Timers").font(.system(size: 23, weight: .semibold))
                Spacer()
                Button(action: showTrackers) {
                    Label("Trackers", systemImage: "calendar")
                }
                Menu {
                    Button(managingPresets ? "Back to Timers" : "Manage Presets…") {
                        managingPresets.toggle()
                    }
                    Button("Quit Menubar Timer") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Timer options")
            }
            if managingPresets {
                PresetManager(presets: presets) { managingPresets = false }
            } else {
                composer
                timerContent
            }
        }
        .padding(16)
        .frame(width: 368)
        .onChange(of: timers.active.map(\.id)) { _, ids in
            if let editing, !ids.contains(editing) { resetComposer() }
        }
    }

    @ViewBuilder private var timerContent: some View {
        if timers.active.isEmpty && timers.finished.isEmpty {
            Text("No active timers. Drag down from the menu bar to start one.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            timerList
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(editing == nil ? "New timer" : "Edit timer")
                .font(.system(size: 13, weight: .semibold))
            TextField("Timer name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .accessibilityLabel("Timer name")

            if editing == nil {
                HStack(spacing: 12) {
                    Slider(value: $minutes, in: 1...60, step: 1) { Text("Duration") }
                        .labelsHidden()
                        .tint(color.tint)
                    Text("\(Int(minutes)) min")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .frame(width: 59, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 4) {
                TimerColorPicker(selection: $color)
                Spacer()
                if editing != nil { Button("Cancel") { resetComposer() } }
                Button(editing == nil ? "Start" : "Save", action: submit)
                    .buttonStyle(.borderedProminent)
                    .tint(color.tint)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var timerList: some View {
        let count = timers.active.count + timers.finished.count

        return ScrollView {
            VStack(spacing: 7) {
                ForEach(timers.active.sorted { $0.deadline < $1.deadline }) { timer in
                    timerRow(timer, complete: false)
                }
                ForEach(timers.finished) { timer in
                    timerRow(timer, complete: true)
                }
            }
        }
        .frame(height: min(201, CGFloat(count) * 62 - 7))
    }

    private func timerRow(_ timer: Countdown, complete: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: complete ? "checkmark.circle.fill" : (timer.icon ?? "timer"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(timer.tint)
                .frame(width: 30, height: 30)
                .background(timer.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(timer.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(complete ? "Done" : timers.remaining(timer))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: complete ? 1 : timers.fractionRemaining(timer))
                    .tint(timer.tint)
                    .accessibilityLabel("Time remaining")
            }
            if !complete {
                rowButton("pencil", label: "Edit \(timer.title)") {
                    editing = timer.id
                    name = timer.name ?? ""
                    color = timer.color ?? .indigo
                    nameFocused = true
                }
            }
            rowButton("xmark", label: complete ? "Dismiss \(timer.title)" : "Cancel \(timer.title)") {
                if complete { timers.finished.removeAll { $0.id == timer.id } }
                else { timers.cancel(timer.id) }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 55)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func rowButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 23, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func submit() {
        if let editing {
            timers.update(editing, name: name, color: color)
        } else {
            timers.start(Int(minutes), name: name, color: color)
        }
        resetComposer()
    }

    private func resetComposer() {
        editing = nil
        name = ""
        color = .indigo
        nameFocused = false
    }
}

struct DragPreview: View {
    let minutes: Int

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "timer").font(.title2).foregroundStyle(Color.accentColor)
            Text("\(minutes) min").font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
            ProgressView(value: Double(minutes), total: 60).frame(width: 140)
            Text(minutes == 0 ? "Drag down to set" : "Release to start")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 192, height: 122)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

final class StatusControl: NSView {
    var onClick: (() -> Void)?
    var onDrag: ((Int) -> Void)?
    var onRelease: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    private var start: NSPoint?
    private var dragged = false
    private var cancelled = false
    private var minute = 0
    private var pointsPerMinute: CGFloat = 5
    private var keyMonitor: Any?

    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
        dragged = false
        cancelled = false
        minute = 0
        if let start, let screen = window?.screen {
            pointsPerMinute = min(5, max(1, (start.y - screen.visibleFrame.minY - 5) / 60))
        }
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancelled = true
            self?.onCancel?()
            self?.removeKeyMonitor()
            return nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start, !cancelled else { return }
        let pointer = NSEvent.mouseLocation
        let distance = start.y - pointer.y
        guard dragged || abs(distance) >= 4 || abs(start.x - pointer.x) >= 4 else { return }
        dragged = true
        let next = min(60, max(0, Int((distance / pointsPerMinute).rounded(.towardZero))))
        if next != minute {
            minute = next
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        onDrag?(minute)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            start = nil
            removeKeyMonitor()
        }
        guard !cancelled else { return }
        if dragged { onRelease?(minute) }
        else if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let timers = Timers()
    private let presets = Presets()
    private let trackerDesktop = TrackerDesktop()
    private let quickPopover = NSPopover()
    private let popover = NSPopover()
    private let control = StatusControl()
    private let statusContent = TimerStatusContent()
    private var clock: Timer?
    private var preview: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = item.button else { return }
        button.addSubview(control)
        control.frame = button.bounds
        control.autoresizingMask = [.width, .height]
        control.setAccessibilityElement(true)
        control.setAccessibilityRole(.button)
        control.setAccessibilityLabel("Menu Bar Timer")

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: TimerMenu(timers: timers, presets: presets) { [weak self] in
            self?.popover.performClose(nil)
            self?.trackerDesktop.showDashboard()
        })
        trackerDesktop.store.didChange = { [weak self] in
            self?.trackerDesktop.refreshPanels()
            self?.refreshTrackerReminders()
        }
        trackerDesktop.refreshPanels()
        refreshTrackerReminders()
        NotificationCenter.default.addObserver(
            self, selector: #selector(trackerDayChanged(_:)), name: .NSCalendarDayChanged, object: nil
        )
        quickPopover.behavior = .transient
        control.onClick = { [weak self] in self?.toggleMenu() }
        control.onDrag = { [weak self] minutes in self?.showPreview(minutes) }
        control.onRelease = { [weak self] minutes in
            self?.hidePreview()
            guard let self, let id = timers.start(minutes) else { return }
            showQuickCard(for: id)
        }
        control.onCancel = { [weak self] in self?.hidePreview() }
        timers.refresh = { [weak self] in self?.renderStatus() }
        let clock = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.timers.tick()
        }
        self.clock = clock
        RunLoop.main.add(clock, forMode: .common)
        timers.tick()
    }

    @objc private func trackerDayChanged(_ notification: Notification) {
        refreshTrackerReminders()
    }

    private func refreshTrackerReminders() {
        let trackers = trackerDesktop.store.trackers
        Task { @MainActor in
            do {
                try await ProgressReminders.shared.refresh(trackers, settings: .current)
            } catch is CancellationError {
                return
            } catch {
                NSLog("Could not schedule tracker reminders: %@", error.localizedDescription)
            }
        }
    }

    private func renderStatus() {
        guard let button = item.button else { return }
        statusContent.render(timers, on: button)
    }

    private func showQuickCard(for id: UUID) {
        guard let button = item.button else { return }
        quickPopover.contentViewController = NSHostingController(
            rootView: QuickPresetCard(timers: timers, presets: presets, id: id) { [weak self] in
                self?.quickPopover.close()
            }
        )
        quickPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        quickPopover.contentViewController?.view.window?.makeKey()
    }

    private func toggleMenu() {
        quickPopover.close()
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showPreview(_ minutes: Int) {
        if let host = preview?.contentViewController as? NSHostingController<DragPreview> {
            host.rootView = DragPreview(minutes: minutes)
            return
        }
        guard let button = item.button, let window = button.window,
              let screen = window.screen else { return }
        popover.performClose(nil)
        quickPopover.close()
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = NSSize(width: 192, height: 122)
        let x = min(max(screen.visibleFrame.minX + 8, anchor.midX - size.width / 2),
                    screen.visibleFrame.maxX - size.width - 8)
        let panel = NSPanel(contentRect: NSRect(x: x, y: anchor.minY - size.height - 8,
                                                width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.contentViewController = NSHostingController(rootView: DragPreview(minutes: minutes))
        panel.orderFrontRegardless()
        preview = panel
    }

    private func hidePreview() {
        preview?.orderOut(nil)
        preview = nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
