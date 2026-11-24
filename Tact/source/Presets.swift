import SwiftUI

struct TimerPreset: Codable, Identifiable {
    var id = UUID()
    var name = ""
    var color = TimerColor.indigo
    var icon = "timer"
}

final class Presets: ObservableObject {
    private struct Catalog: Codable {
        var items: [TimerPreset]
        var pinned: [UUID]
    }

    private let key = "timerPresetCatalog"
    @Published private var catalog: Catalog

    var items: [TimerPreset] { catalog.items }
    var quick: [TimerPreset] {
        catalog.pinned.compactMap { id in items.first { $0.id == id } }
    }

    init() {
        let defaults = [
            TimerPreset(name: "Learn", color: .violet, icon: "book"),
            TimerPreset(name: "Work", color: .sky, icon: "briefcase"),
            TimerPreset(name: "Break", color: .mint, icon: "cup.and.saucer")
        ]
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(Catalog.self, from: data) {
            catalog = saved
        } else {
            catalog = Catalog(items: defaults, pinned: defaults.map(\.id))
        }
    }

    func save(_ preset: TimerPreset, pinned: Bool) {
        var updated = catalog
        if let index = updated.items.firstIndex(where: { $0.id == preset.id }) {
            updated.items[index] = preset
        } else {
            updated.items.append(preset)
        }
        if pinned {
            if !updated.pinned.contains(preset.id) {
                if updated.pinned.count == 3 { updated.pinned.removeFirst() }
                updated.pinned.append(preset.id)
            }
        } else {
            updated.pinned.removeAll { $0 == preset.id }
        }
        guard let data = try? JSONEncoder().encode(updated) else { return }
        UserDefaults.standard.set(data, forKey: key)
        catalog = updated
    }
}

struct TimerColorPicker: View {
    @Binding var selection: TimerColor

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TimerColor.allCases, id: \.self) { swatch in
                Button { selection = swatch } label: {
                    Circle().fill(swatch.tint)
                        .frame(width: 17, height: 17)
                        .overlay {
                            if selection == swatch {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 25, height: 25)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(swatch.rawValue.capitalized)
                .accessibilityLabel(swatch.rawValue.capitalized)
                .accessibilityAddTraits(selection == swatch ? .isSelected : [])
            }
        }
    }
}

struct QuickPresetCard: View {
    @ObservedObject var timers: Timers
    @ObservedObject var presets: Presets
    let id: UUID
    let close: () -> Void

    @State private var name = ""
    @State private var color = TimerColor.indigo
    @State private var hovered = false
    @State private var pickingColor = false
    @FocusState private var naming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Timer started").font(.headline)
                Spacer()
                Button("Done", action: close)
            }
            if !presets.quick.isEmpty {
                HStack {
                    ForEach(presets.quick) { preset in
                        Button {
                            timers.update(id, name: preset.name, color: preset.color, icon: preset.icon)
                            close()
                        } label: {
                            Label(preset.name, systemImage: preset.icon)
                                .foregroundStyle(preset.color.tint)
                                .lineLimit(1)
                        }
                        .help(preset.name)
                    }
                }
            }
            HStack {
                TextField("Timer name (optional)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($naming)
                    .onSubmit(close)
                Button { pickingColor.toggle() } label: {
                    Circle().fill(color.tint).frame(width: 16, height: 16)
                }
                .accessibilityLabel("Timer colour")
            }
            if pickingColor {
                TimerColorPicker(selection: $color)
            }
        }
        .padding(14)
        .frame(width: 330)
        .onHover { hovered = $0 }
        .onChange(of: name) { _, value in timers.update(id, name: value, color: color) }
        .onChange(of: color) { _, value in
            timers.update(id, name: name, color: value)
            pickingColor = false
        }
        .task(id: hovered || naming || pickingColor) {
            guard !(hovered || naming || pickingColor) else { return }
            do {
                try await Task.sleep(for: .seconds(4))
                close()
            } catch is CancellationError {
                // Interaction restarted the dismissal timer.
            } catch {}
        }
        .onExitCommand(perform: close)
    }
}

struct PresetManager: View {
    @ObservedObject var presets: Presets
    let done: () -> Void
    @State private var draft = TimerPreset()
    @State private var editing = false
    @State private var pinned = false
    @State private var search = ""

    private let icons = [
        "timer", "book", "briefcase", "cup.and.saucer", "pencil", "graduationcap",
        "laptopcomputer", "desktopcomputer", "keyboard", "brain", "lightbulb",
        "doc.text", "folder", "calendar", "clock", "alarm", "bell", "star", "heart",
        "flame", "bolt", "leaf", "sun.max", "moon", "sparkles", "paintbrush",
        "camera", "music.note", "headphones", "mic", "figure.walk", "figure.run",
        "bicycle", "dumbbell", "fork.knife", "mug", "drop", "cart", "house", "airplane"
    ]

    private var name: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var visibleIcons: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return icons.filter { query.isEmpty || iconTitle($0).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Back", action: done)
                Spacer()
                Button("New Preset") { edit(TimerPreset()) }
            }
            if editing {
                editor
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(presets.items) { preset in
                            Button { edit(preset) } label: {
                                HStack {
                                    Label(preset.name, systemImage: preset.icon)
                                        .foregroundStyle(preset.color.tint)
                                    Spacer()
                                    if presets.quick.contains(where: { $0.id == preset.id }) {
                                        Image(systemName: "pin.fill")
                                            .accessibilityLabel("In quick card")
                                    }
                                    Image(systemName: "chevron.right").accessibilityHidden(true)
                                }
                                .padding(8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(name.isEmpty ? "Preset preview" : name, systemImage: draft.icon)
                .foregroundStyle(draft.color.tint)
                .lineLimit(1)
            TextField("Preset name", text: $draft.name).textFieldStyle(.roundedBorder)
            TimerColorPicker(selection: $draft.color)
            TextField("Search icons", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8)) {
                    ForEach(visibleIcons, id: \.self) { icon in
                        Button { draft.icon = icon } label: {
                            Image(systemName: icon)
                                .frame(width: 30, height: 28)
                                .background(draft.icon == icon ? draft.color.tint.opacity(0.18) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(iconTitle(icon))
                        .accessibilityLabel(iconTitle(icon))
                        .accessibilityAddTraits(draft.icon == icon ? .isSelected : [])
                    }
                }
            }
            .frame(height: 100)
            Toggle("Show in quick card", isOn: $pinned)
            if pinned && presets.quick.count == 3 && !presets.quick.contains(where: { $0.id == draft.id }),
               let first = presets.quick.first {
                Text("Replaces \(first.name) in the quick card.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { editing = false }
                Button("Save") {
                    draft.name = String(name.prefix(60))
                    presets.save(draft, pinned: pinned)
                    editing = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
    }

    private func edit(_ preset: TimerPreset) {
        draft = preset
        pinned = presets.quick.contains { $0.id == preset.id }
        search = ""
        editing = true
    }

    private func iconTitle(_ icon: String) -> String {
        icon.replacingOccurrences(of: ".", with: " ").capitalized
    }
}
