import AppKit
import SwiftUI

final class TrackerStore: ObservableObject {
    @Published private(set) var trackers: [Tracker]
    @Published private(set) var pinned: Set<UUID>
    var didChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    init() {
        trackers = defaults.data(forKey: "manualTrackers")
            .flatMap { try? JSONDecoder().decode([Tracker].self, from: $0) } ?? []
        pinned = Set((defaults.stringArray(forKey: "desktopTrackerIDs") ?? []).compactMap(UUID.init(uuidString:)))
    }

    func save(_ tracker: Tracker) {
        if let index = trackers.firstIndex(where: { $0.id == tracker.id }) {
            trackers[index] = tracker
        } else {
            trackers.append(tracker)
        }
        persist()
    }

    func remove(_ id: UUID) {
        trackers.removeAll { $0.id == id }
        pinned.remove(id)
        persist()
    }

    func togglePin(_ id: UUID) {
        if pinned.contains(id) { pinned.remove(id) }
        else { pinned.insert(id) }
        persist()
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(trackers) {
            defaults.set(encoded, forKey: "manualTrackers")
        }
        defaults.set(pinned.map(\.uuidString), forKey: "desktopTrackerIDs")
        didChange?()
    }
}

struct TrackerCard: View {
    let tracker: Tracker

    var body: some View {
        TimelineView(.everyMinute) { context in
            ProgressCard(tracker: tracker, date: context.date)
        }
    }
}

struct TrackerDashboard: View {
    @ObservedObject var store: TrackerStore
    let showTimers: () -> Void
    @State private var draft: Tracker?
    @State private var removal: Tracker?
    @State private var showReminders = false

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                Text("Trackers").font(.largeTitle.bold())
                Spacer()
                Button(action: showTimers) { Label("Timers", systemImage: "timer") }
                Button("Reminders…") { showReminders = true }
                Button {
                    draft = Tracker(end: Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now, paletteID: 1)
                } label: {
                    Label("New tracker", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            if store.trackers.isEmpty {
                ContentUnavailableView("No trackers yet", systemImage: "calendar.badge.clock",
                                       description: Text("Add a date, a recurring event, or a day you want to count from."))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 15)], spacing: 15) {
                        ForEach(store.trackers) { tracker in
                            VStack(alignment: .leading, spacing: 8) {
                                TrackerCard(tracker: tracker)
                                HStack {
                                    let pinned = store.pinned.contains(tracker.id)
                                    Button { store.togglePin(tracker.id) } label: {
                                        Label(pinned ? "On Desktop" : "Pin to Desktop",
                                              systemImage: pinned ? "pin.fill" : "pin")
                                    }
                                    Spacer()
                                    Menu {
                                        Button("Edit tracker") { draft = tracker }
                                        Button("Delete tracker", role: .destructive) { removal = tracker }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                    .fixedSize()
                                    .accessibilityLabel("Options for \(tracker.name)")
                                }
                                .font(.caption)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 490, minHeight: 345)
        .sheet(isPresented: $showReminders) {
            ReminderSettingsView { store.didChange?() }
        }
        .sheet(item: $draft) { tracker in
            TrackerEditor(tracker: tracker, save: store.save)
        }
        .alert("Delete tracker?", isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } }
        ), presenting: removal) { tracker in
            Button("Delete", role: .destructive) { store.remove(tracker.id) }
            Button("Cancel", role: .cancel) {}
        } message: { tracker in
            Text(tracker.name)
        }
    }
}

final class TrackerDesktop: NSObject, NSWindowDelegate {
    private var panels: [UUID: NSPanel] = [:]
    private var dashboard: NSWindow?
    let store = TrackerStore()

    func showDashboard(showTimers: @escaping () -> Void) {
        if dashboard == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 655, height: 460),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "Tact — Trackers"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: TrackerDashboard(store: store, showTimers: showTimers))
            window.minSize = NSSize(width: 490, height: 375)
            window.center()
            dashboard = window
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.makeKeyAndOrderFront(nil)
    }

    func refreshPanels() {
        for id in Array(panels.keys) where !store.pinned.contains(id) {
            panels.removeValue(forKey: id)?.orderOut(nil)
        }
        for tracker in store.trackers where store.pinned.contains(tracker.id) {
            let card = TrackerCard(tracker: tracker)
            if let controller = panels[tracker.id]?.contentViewController as? NSHostingController<TrackerCard> {
                controller.rootView = card
            } else {
                addPanel(tracker.id, card: card)
            }
        }
    }

    private func addPanel(_ id: UUID, card: TrackerCard) {
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 190, height: 146)
        let key = "desktopTrackerPosition.\(id.uuidString)"
        var frame = NSRect(x: screen.visibleFrame.maxX - size.width - 24,
                           y: screen.visibleFrame.maxY - size.height - 24,
                           width: size.width, height: size.height)
        let rows = max(1, Int((screen.visibleFrame.height - 24) / 158))
        frame.origin.x -= CGFloat(panels.count / rows) * 202
        frame.origin.y -= CGFloat(panels.count % rows) * 158
        if let saved = UserDefaults.standard.string(forKey: key) {
            let position = NSPointFromString(saved)
            let savedFrame = NSRect(origin: position, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(savedFrame) }) {
                frame = savedFrame
            }
        }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentViewController = NSHostingController(rootView: card)
        panel.setFrame(frame, display: false)
        panel.delegate = self
        panels[id] = panel
        panel.orderFrontRegardless()
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = panels.first(where: { $0.value === window })?.key else { return }
        UserDefaults.standard.set(NSStringFromPoint(window.frame.origin),
                                  forKey: "desktopTrackerPosition.\(id.uuidString)")
    }
}
