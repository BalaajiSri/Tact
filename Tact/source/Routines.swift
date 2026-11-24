import AppKit
import SwiftUI
import UserNotifications

struct RoutineStep: Codable, Identifiable {
    var id = UUID()
    var name = "Activity"
    var duration = 25
    var color = TimerColor.indigo
    var sound: TimerSound = .glass
    var alerts: [Int]? = nil
    var x: Double = 40
    var y: Double = 40
}

struct RoutineLink: Codable, Identifiable {
    var id = UUID()
    var from: UUID
    var to: UUID
    var delay: Int = 0
    var manual = false
    var repeatLimit: Int? = nil
    var repeatForever = false
}

struct Routine: Codable, Identifiable {
    var id = UUID()
    var name = "New routine"
    var steps: [RoutineStep] = []
    var links: [RoutineLink] = []
    var startID: UUID?
    var defaultAlerts: [Int] = [5]
}

struct RoutineRun: Codable {
    var routine: Routine
    var stepID: UUID
    var deadline: Date
    var phase: String = "running"
    var pendingLink: UUID?
    var delayUntil: Date?
    var pausedRemaining: TimeInterval?
    var repeatCounts: [UUID: Int] = [:]
    var sentAlerts: [Int] = []
    var sleepStarted: Date?
    var sleepPromptAt: Date?
    var phaseBeforeSleep: String?
}

final class RoutineStore: ObservableObject {
    @Published var routines: [Routine] = []
    @Published var run: RoutineRun?
    @Published var now = Date()
    @Published var error: String?
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: "tact.routines"),
           let saved = try? JSONDecoder().decode([Routine].self, from: data) { routines = saved }
        if let data = defaults.data(forKey: "tact.routineRun"),
           let saved = try? JSONDecoder().decode(RoutineRun.self, from: data) { run = saved }
    }

    func save(_ routine: Routine) {
        if let index = routines.firstIndex(where: { $0.id == routine.id }) { routines[index] = routine }
        else { routines.append(routine) }
        if let data = try? JSONEncoder().encode(routines) { defaults.set(data, forKey: "tact.routines") }
    }

    func start(_ routine: Routine) {
        guard run == nil else { error = "Stop the active routine before starting another."; return }
        guard let id = routine.startID, let step = routine.steps.first(where: { $0.id == id }),
              step.duration > 0 else { error = "Choose a valid starting activity."; return }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        run = RoutineRun(routine: routine, stepID: id,
                         deadline: Date().addingTimeInterval(Double(step.duration * 60)))
        error = nil
        persist()
    }

    var current: RoutineStep? {
        guard let run else { return nil }
        return run.routine.steps.first { $0.id == run.stepID }
    }

    var choices: [RoutineLink] {
        guard let run else { return [] }
        return run.routine.links.filter { link in
            guard link.from == run.stepID else { return false }
            if link.repeatForever { return true }
            guard let limit = link.repeatLimit else { return true }
            return (run.repeatCounts[link.id] ?? 0) < limit
        }
    }

    func name(for id: UUID) -> String {
        run?.routine.steps.first(where: { $0.id == id })?.name ?? "Missing activity"
    }

    func tick() {
        now = Date()
        guard var state = run, state.pausedRemaining == nil, state.phase != "sleep" else { return }
        if state.phase == "delay", let until = state.delayUntil, until <= now,
           let link = state.routine.links.first(where: { $0.id == state.pendingLink }) {
            begin(link, at: until)
            return
        }
        guard state.phase == "running", let step = current else { return }
        let remaining = state.deadline.timeIntervalSince(now)
        let previousAlerts = state.sentAlerts
        for alert in step.alerts ?? state.routine.defaultAlerts where alert > 0 {
            if remaining > 0 && remaining <= Double(alert * 60) && !state.sentAlerts.contains(alert) {
                state.sentAlerts.append(alert)
                notify(title: step.name, body: "\(alert) minute(s) remaining.")
            }
        }
        run = state
        guard remaining <= 0 else {
            if state.sentAlerts != previousAlerts { persist() }
            return
        }
        step.sound.play()
        notify(title: "Activity complete", body: step.name)
        let options = choices
        if options.isEmpty { run = nil; persist(); return }
        if options.count > 1 {
            run?.phase = "choice"
        } else if let link = options.first {
            if link.manual { run?.phase = "choice" }
            else { choose(link, reference: state.deadline) }
        }
        persist()
    }

    func choose(_ link: RoutineLink, reference: Date = Date()) {
        guard run?.stepID == link.from else { return }
        if link.repeatForever || link.repeatLimit != nil {
            run?.repeatCounts[link.id, default: 0] += 1
        }
        let start = reference.addingTimeInterval(Double(max(0, link.delay) * 60))
        if start > Date() {
            run?.phase = "delay"
            run?.pendingLink = link.id
            run?.delayUntil = start
        } else {
            begin(link, at: start)
        }
        persist()
    }

    private func begin(_ link: RoutineLink, at date: Date) {
        guard let step = run?.routine.steps.first(where: { $0.id == link.to }), step.duration > 0 else {
            error = "The next activity is missing or has an invalid duration."
            run = nil
            persist()
            return
        }
        run?.stepID = step.id
        run?.deadline = date.addingTimeInterval(Double(step.duration * 60))
        run?.phase = "running"
        run?.pendingLink = nil
        run?.delayUntil = nil
        run?.sentAlerts = []
        persist()
    }

    func pauseOrResume() {
        guard let state = run else { return }
        if let remaining = state.pausedRemaining {
            let newDeadline = Date().addingTimeInterval(remaining)
            if state.phase == "delay" { run?.delayUntil = newDeadline }
            else { run?.deadline = newDeadline }
            run?.pausedRemaining = nil
        } else if state.phase == "running" || state.phase == "delay" {
            let deadline = state.phase == "delay" ? (state.delayUntil ?? Date()) : state.deadline
            run?.pausedRemaining = max(0, deadline.timeIntervalSinceNow)
        }
        persist()
    }

    func skip() {
        guard run?.phase == "running" else { return }
        run?.deadline = Date()
        tick()
    }

    func stop() { run = nil; persist() }

    func sleep() {
        guard run != nil else { return }
        run?.sleepStarted = Date()
        persist()
    }

    func wake() {
        guard let started = run?.sleepStarted else { return }
        let duration = Date().timeIntervalSince(started)
        run?.sleepStarted = nil
        let threshold = max(1, defaults.object(forKey: "routineSleepThreshold") as? Int ?? 60)
        if duration >= Double(threshold * 60), run?.pausedRemaining == nil {
            run?.sleepPromptAt = started
            run?.phaseBeforeSleep = run?.phase
            run?.phase = "sleep"
        }
        persist()
        if run?.phase != "sleep" { tick() }
    }

    func recover(catchUp: Bool) {
        guard let state = run, let slept = state.sleepPromptAt else { return }
        if !catchUp {
            run?.deadline = Date().addingTimeInterval(max(0, state.deadline.timeIntervalSince(slept)))
            if let delay = state.delayUntil {
                run?.delayUntil = Date().addingTimeInterval(max(0, delay.timeIntervalSince(slept)))
            }
        }
        run?.phase = state.phaseBeforeSleep ?? (state.pendingLink == nil ? "running" : "delay")
        run?.phaseBeforeSleep = nil
        run?.sleepPromptAt = nil
        persist()
        tick()
    }

    private func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func persist() {
        if let run, let data = try? JSONEncoder().encode(run) { defaults.set(data, forKey: "tact.routineRun") }
        else if run == nil { defaults.removeObject(forKey: "tact.routineRun") }
    }
}

struct RoutinesView: View {
    @ObservedObject var store: RoutineStore
    @State private var draft: Routine?
    @AppStorage("routineSleepThreshold") private var sleepThreshold = 60

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Routines").font(.title2.bold())
                    Spacer()
                    Button("New") {
                        var routine = Routine()
                        let step = RoutineStep()
                        routine.steps = [step]
                        routine.startID = step.id
                        draft = routine
                    }
                }
                List(store.routines) { routine in
                    HStack {
                        Button(routine.name) { draft = routine }.buttonStyle(.plain)
                        Spacer()
                        Button("Start") { store.start(routine) }.disabled(store.run != nil)
                    }
                }
                Stepper("Ask after \(sleepThreshold) min asleep", value: $sleepThreshold, in: 1...1440)
                    .font(.caption)
                if let run = store.run {
                    Divider()
                    Text("Active: \(run.routine.name)").font(.headline)
                    Text(store.current?.name ?? "")
                    if run.phase == "running" {
                        Text(run.pausedRemaining.map { seconds($0) } ??
                             seconds(max(0, run.deadline.timeIntervalSince(store.now))))
                            .monospacedDigit()
                    } else { Text(run.phase.capitalized) }
                    if run.phase == "choice" {
                        Text("Choose the next activity").font(.caption)
                        ForEach(store.choices) { link in
                            Button(store.name(for: link.to)) { store.choose(link) }
                        }
                    }
                    if run.phase == "sleep" {
                        Text("Tact was asleep for a while.").font(.caption)
                        Button("Continue from where I left off") { store.recover(catchUp: false) }
                        Button("Catch up to now") { store.recover(catchUp: true) }
                    }
                    HStack {
                        Button(run.pausedRemaining == nil ? "Pause" : "Resume") { store.pauseOrResume() }
                            .disabled(run.phase != "running" && run.phase != "delay")
                        Button("Skip") { store.skip() }.disabled(run.phase != "running")
                        Button("Stop") { store.stop() }
                    }
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }
            .padding().frame(minWidth: 250, idealWidth: 280)
            if let draft {
                RoutineEditor(routine: draft, save: { store.save($0); self.draft = nil },
                              cancel: { self.draft = nil })
                    .id(draft.id)
            } else {
                ContentUnavailableView("Select a routine", systemImage: "point.3.connected.trianglepath.dotted")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func seconds(_ value: TimeInterval) -> String {
        let total = max(0, Int(ceil(value)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct RoutineEditor: View {
    @State var routine: Routine
    let save: (Routine) -> Void
    let cancel: () -> Void
    @State private var selected: UUID?
    @State private var source: UUID?
    @State private var target: UUID?
    @State private var dragOrigin: CGPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Routine name", text: $routine.name)
                Button("Add activity") {
                    let step = RoutineStep(x: Double(50 + routine.steps.count * 35),
                                           y: Double(50 + routine.steps.count * 35))
                    routine.steps.append(step)
                    if routine.startID == nil { routine.startID = step.id }
                    selected = step.id
                }
                Button("Cancel", action: cancel)
                Button("Save") { save(routine) }
                    .disabled(routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || routine.steps.isEmpty)
            }
            HStack(alignment: .top) {
                graph
                inspector.frame(width: 245)
            }
            Divider()
            HStack {
                Text("Default alerts (minutes)")
                TextField("5, 2", text: Binding(
                    get: { routine.defaultAlerts.map(String.init).joined(separator: ", ") },
                    set: { routine.defaultAlerts = $0.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 > 0 } }
                )).frame(width: 100)
                Picker("From", selection: $source) {
                    Text("Select").tag(Optional<UUID>.none)
                    ForEach(routine.steps) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("To", selection: $target) {
                    Text("Select").tag(Optional<UUID>.none)
                    ForEach(routine.steps) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("Connect") {
                    if let source, let target, source != target,
                       !routine.links.contains(where: { $0.from == source && $0.to == target }) {
                        routine.links.append(RoutineLink(from: source, to: target))
                    }
                }.disabled(source == nil || target == nil || source == target)
            }
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach($routine.links) { $link in
                        HStack {
                            Text("\(stepName(link.from)) → \(stepName(link.to))").frame(width: 170, alignment: .leading)
                            Stepper("Delay \(link.delay)m", value: $link.delay, in: 0...1440)
                            Toggle("Confirm", isOn: $link.manual)
                            Toggle("Repeat forever", isOn: $link.repeatForever)
                            if !link.repeatForever {
                                Stepper("Repeat \(link.repeatLimit ?? 0)", value: Binding(
                                    get: { link.repeatLimit ?? 0 },
                                    set: { link.repeatLimit = $0 == 0 ? nil : $0 }
                                ), in: 0...1000)
                            }
                            Button("Remove") { routine.links.removeAll { $0.id == link.id } }
                        }
                    }
                }
            }.frame(maxHeight: 110)
        }
        .padding()
    }

    private var graph: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.04))
                Canvas { context, _ in
                    for link in routine.links {
                        guard let a = routine.steps.first(where: { $0.id == link.from }),
                              let b = routine.steps.first(where: { $0.id == link.to }) else { continue }
                        let startCenter = CGPoint(x: a.x + 60, y: a.y + 27.5)
                        let endCenter = CGPoint(x: b.x + 60, y: b.y + 27.5)
                        let dx = endCenter.x - startCenter.x
                        let dy = endCenter.y - startCenter.y
                        let distance = hypot(dx, dy)
                        guard distance > 1 else { continue }
                        let ux = dx / distance
                        let uy = dy / distance
                        let startScale = min(abs(ux) > 0.001 ? 60 / abs(ux) : .infinity,
                                             abs(uy) > 0.001 ? 27.5 / abs(uy) : .infinity)
                        let endScale = min(abs(ux) > 0.001 ? 60 / abs(ux) : .infinity,
                                           abs(uy) > 0.001 ? 27.5 / abs(uy) : .infinity)
                        let start = CGPoint(x: startCenter.x + ux * startScale, y: startCenter.y + uy * startScale)
                        let end = CGPoint(x: endCenter.x - ux * endScale, y: endCenter.y - uy * endScale)
                        let curved = routine.links.contains { $0.from == link.to && $0.to == link.from }
                        let bend: CGFloat = curved ? 28 : 0
                        let control = CGPoint(x: (start.x + end.x) / 2 - uy * bend,
                                              y: (start.y + end.y) / 2 + ux * bend)
                        var path = Path()
                        path.move(to: start)
                        path.addQuadCurve(to: end, control: control)
                        context.stroke(path, with: .color(.secondary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        let angle = atan2(end.y - control.y, end.x - control.x)
                        let arrowX = cos(angle)
                        let arrowY = sin(angle)
                        let wing: CGFloat = 7
                        var arrow = Path()
                        arrow.move(to: end)
                        arrow.addLine(to: CGPoint(x: end.x - arrowX * wing - arrowY * wing * 0.55,
                                                  y: end.y - arrowY * wing + arrowX * wing * 0.55))
                        arrow.move(to: end)
                        arrow.addLine(to: CGPoint(x: end.x - arrowX * wing + arrowY * wing * 0.55,
                                                  y: end.y - arrowY * wing - arrowX * wing * 0.55))
                        context.stroke(arrow, with: .color(.secondary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }.allowsHitTesting(false)
                ForEach($routine.steps) { $step in
                    Button {
                        selected = step.id
                    } label: {
                        VStack(alignment: .leading) {
                            Text(step.name).font(.headline).lineLimit(1)
                            Text("\(step.duration) min").font(.caption)
                        }
                        .frame(width: 120, height: 55)
                        .background(step.color.tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(selected == step.id ? step.color.tint : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .offset(x: step.x, y: step.y)
                    .simultaneousGesture(DragGesture(minimumDistance: 3).onChanged { value in
                        if dragOrigin == nil { dragOrigin = CGPoint(x: step.x, y: step.y) }
                        guard let origin = dragOrigin else { return }
                        step.x = min(max(0, origin.x + value.translation.width), max(0, geometry.size.width - 120))
                        step.y = min(max(0, origin.y + value.translation.height), max(0, geometry.size.height - 55))
                    }.onEnded { _ in dragOrigin = nil })
                }
            }
        }
        .frame(minWidth: 360, minHeight: 300)
    }

    @ViewBuilder private var inspector: some View {
        if let selected, let index = routine.steps.firstIndex(where: { $0.id == selected }) {
            VStack(alignment: .leading) {
                Text("Activity").font(.headline)
                TextField("Name", text: $routine.steps[index].name)
                Stepper("\(routine.steps[index].duration) minutes", value: $routine.steps[index].duration, in: 1...1440)
                Picker("Colour", selection: $routine.steps[index].color) {
                    ForEach(TimerColor.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Sound", selection: $routine.steps[index].sound) {
                    ForEach(TimerSound.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("Advance alerts (minutes, comma separated)").font(.caption)
                TextField("Use routine default", text: Binding(
                    get: { routine.steps[index].alerts?.map(String.init).joined(separator: ", ") ?? "" },
                    set: { input in
                        routine.steps[index].alerts = input.trimmingCharacters(in: .whitespaces).isEmpty
                            ? nil : input.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 > 0 }
                    }
                ))
                Button("Set as start") { routine.startID = selected }
                if routine.startID == selected { Text("Starting activity").font(.caption) }
                Button("Delete activity") {
                    routine.steps.removeAll { $0.id == selected }
                    routine.links.removeAll { $0.from == selected || $0.to == selected }
                    if routine.startID == selected { routine.startID = routine.steps.first?.id }
                    self.selected = nil
                }
                Spacer()
            }
        } else {
            Text("Select an activity to edit it.").foregroundStyle(.secondary)
        }
    }

    private func stepName(_ id: UUID) -> String {
        routine.steps.first(where: { $0.id == id })?.name ?? "Missing"
    }
}
