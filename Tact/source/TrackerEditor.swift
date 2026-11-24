import SwiftUI
import AppKit

struct TrackerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var tracker: Tracker
    let save: (Tracker) -> Void
    @State private var darkPreview = false
    @State private var showPalette = false
    @State private var showIcons = false
    @State private var milestones = ""
    @State private var customHex = ""
    private let today = Calendar.current.startOfDay(for: Date())
    private let icons = ["calendar", "banknote", "airplane", "gift", "book", "briefcase", "heart",
                         "house", "star", "cup.and.saucer", "figure.run", "graduationcap", "creditcard",
                         "target", "leaf", "music.note", "birthday.cake", "sparkles", "suitcase",
                         "sun.max", "moon.stars", "tram", "flag", "bolt", "globe", "pawprint",
                         "camera", "headphones", "bicycle", "mountain.2", "cart", "timer"]

    var body: some View {
        Group {
            macEditor
        }
        .sheet(isPresented: $showPalette) { palettePicker }
        .sheet(isPresented: $showIcons) { iconPicker }
        .onAppear {
            milestones = (tracker.milestones ?? []).map(String.init).joined(separator: ", ")
            customHex = tracker.customAccent ?? ""
        }
    }

    private func colourControl(_ label: String, value: Binding<String?>, fallback: String) -> some View {
        HStack {
            ColorPicker(label, selection: Binding(
                get: { Color(rgb: value.wrappedValue ?? fallback) },
                set: { value.wrappedValue = hexString($0) }
            ), supportsOpacity: false)
            TextField("Hex", text: Binding(
                get: { value.wrappedValue ?? "" },
                set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
            )).textFieldStyle(.roundedBorder).frame(width: 90)
            Button("Reset") { value.wrappedValue = nil }
        }
    }

    private func hexString(_ color: Color) -> String {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }

    private var previewCard: some View {
        ProgressCard(tracker: preview, date: .now)
            .frame(height: 148)
            .environment(\.colorScheme, darkPreview ? .dark : .light)
    }

    private var previewMode: some View {
        Picker("Preview appearance", selection: $darkPreview) {
            Text("Light").tag(false)
            Text("Dark").tag(true)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    private var saveButton: some View {
        Button("Save") { save(preview); dismiss() }
            .keyboardShortcut(.defaultAction)
            .disabled(!valid)
    }

    private var cancelButton: some View {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
    }

    private var macEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tracker details")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 17)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 21) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Details").font(.headline)
                            TextField("Tracker name", text: $tracker.name)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.large)
                            Form { trackerFields }
                                .formStyle(.columns)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Appearance").font(.headline)
                            HStack(spacing: 8) {
                                Button { showIcons = true } label: {
                                    Label("Symbol", systemImage: tracker.icon)
                                }
                                Button { showPalette = true } label: {
                                    Label("Palettes", systemImage: "paintpalette")
                                }
                            }
                            swatches
                            Picker("Progress style", selection: Binding(
                                get: { tracker.cardStyle ?? "Ring" },
                                set: { tracker.cardStyle = $0 }
                            )) {
                                ForEach(["Ring", "Dots", "Blocks", "Bar", "Text"], id: \.self) { Text($0) }
                            }
                            colourControl("Background", value: $tracker.backgroundHex, fallback: "FBFBFD")
                            colourControl("Text", value: $tracker.textHex, fallback: "202020")
                            colourControl("Remaining progress", value: $tracker.remainingHex, fallback: "A0A0A0")
                            ColorPicker("Progress / ring", selection: Binding(
                                get: { Color(rgb: hexValid ? hex : tracker.accentHex) },
                                set: { customHex = hexString($0) }
                            ), supportsOpacity: false)
                            HStack {
                                TextField("Custom hex", text: $customHex)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 111)
                                Spacer()
                                Toggle("Tinted card", isOn: tintBinding).toggleStyle(.switch)
                            }
                        }
                    }
                    .padding(.horizontal, 25)
                    .padding(.vertical, 20)
                }
                .frame(maxWidth: .infinity)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview").font(.headline)
                    previewCard
                    previewMode
                    Spacer(minLength: 0)
                }
                .padding(19)
                .frame(width: 234)
                .background(.primary.opacity(0.035))
            }
            Divider()
            HStack {
                Spacer()
                cancelButton
                saveButton.buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
        }
        .frame(width: 660, height: 470)
    }

    private var tintBinding: Binding<Bool> {
        Binding(get: { tracker.tinted ?? false }, set: { tracker.tinted = $0 })
    }

    @ViewBuilder
    private var trackerFields: some View {
        Picker("Track", selection: $tracker.mode) {
            ForEach(TrackerMode.allCases) { Text($0.rawValue).tag($0) }
        }
        if tracker.mode == .elapsed || tracker.mode == .progress {
            DatePicker("Start date", selection: $tracker.start, displayedComponents: .date)
        }
        if tracker.mode == .countdown || tracker.mode == .progress {
            DatePicker("Target date", selection: $tracker.end, displayedComponents: .date)
        }
        if tracker.mode == .elapsed {
            TextField("Milestones (e.g. 30, 100, 365)", text: $milestones)
        }
        if tracker.mode == .recurring {
            recurrence
            ForEach(tracker.upcoming(from: today), id: \.self) { date in
                Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var swatches: some View {
        HStack(spacing: 9) {
            ForEach(Array(tracker.swatches.enumerated()), id: \.offset) { index, hex in
                let selected = tracker.paletteID != nil && (tracker.swatchIndex ?? 0) == index && customHex.isEmpty
                Button {
                    tracker.paletteID = tracker.paletteID ?? 1
                    tracker.swatchIndex = index
                    customHex = ""
                } label: {
                    Circle().fill(Color(rgb: hex)).frame(width: 25, height: 25)
                        .overlay { Circle().strokeBorder(.primary.opacity(0.14)) }
                        .overlay {
                            if selected {
                                Circle().strokeBorder(.primary, lineWidth: 1)
                                    .padding(-3)
                            }
                        }
                        .frame(width: 29, height: 29)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("#\(hex)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var cleanName: String { tracker.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hex: String { customHex.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "#", with: "").uppercased() }
    private var hexValid: Bool { hex.count == 6 && UInt32(hex, radix: 16) != nil }
    private var enteredMilestones: [Int] {
        milestones.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
    private var valid: Bool {
        let calendar = Calendar.current
        let validMilestones = tracker.mode != .elapsed || milestones.isEmpty ||
            (enteredMilestones.count == milestones.split(separator: ",", omittingEmptySubsequences: false).count
             && enteredMilestones.allSatisfy { $0 > 0 && $0 <= 36500 })
        let colours = [tracker.backgroundHex, tracker.textHex, tracker.remainingHex].compactMap { $0 }
        let validColours = colours.allSatisfy { $0.count == 6 && UInt32($0, radix: 16) != nil }
        return !cleanName.isEmpty && validColours &&
            (tracker.mode != .recurring || tracker.repeatRule != .weekly || !(tracker.weekdays ?? [tracker.weekday]).isEmpty) && (hex.isEmpty || hexValid) && validMilestones &&
            (tracker.mode != .progress || calendar.startOfDay(for: tracker.end) > calendar.startOfDay(for: tracker.start))
    }

    private var preview: Tracker {
        var result = tracker
        result.name = cleanName.isEmpty ? "Your tracker" : cleanName
        result.customAccent = hexValid ? hex : nil
        result.milestones = Array(Set(enteredMilestones.filter { $0 > 0 })).sorted()
        return result
    }

    private var palettePicker: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), spacing: 12)], spacing: 12) {
                    ForEach(Array(progressPalettes.enumerated()), id: \.offset) { index, palette in
                        Button {
                            tracker.paletteID = index + 1
                            tracker.swatchIndex = 0
                            customHex = ""
                            showPalette = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                LinearGradient(colors: palette.map { Color(rgb: $0) },
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(height: 35).clipShape(.rect(cornerRadius: 9))
                                Text("Palette \(index + 1)").font(.caption)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding()
            }.navigationTitle("Palettes")
        }
        .frame(width: 400, height: 400)
    }

    private var iconPicker: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 45))], spacing: 8) {
                    ForEach(icons, id: \.self) { icon in
                        Button { tracker.icon = icon; showIcons = false } label: {
                            Image(systemName: icon).frame(width: 38, height: 38)
                        }.buttonStyle(.bordered).accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
                    }
                }.padding()
            }.navigationTitle("Symbols")
        }
        .frame(width: 390, height: 320)
    }

    private var recurrence: some View {
        Group {
            Picker("Repeat", selection: $tracker.repeatRule) {
                ForEach(RepeatRule.allCases) { Text($0.rawValue).tag($0) }
            }
            .onChange(of: tracker.repeatRule) { _, _ in tracker.dateOverride = nil }
            switch tracker.repeatRule {
            case .daily:
                DatePicker("Starting date", selection: $tracker.start, displayedComponents: .date)
                Stepper("Every \(tracker.dayInterval ?? 1) day(s)", value: Binding(
                    get: { tracker.dayInterval ?? 1 }, set: { tracker.dayInterval = $0 }
                ), in: 1...365)
            case .weekly:
                VStack(alignment: .leading) {
                    Text("Days")
                    HStack {
                        ForEach(Array(Calendar.current.shortWeekdaySymbols.enumerated()), id: \.offset) { entry in
                            let day = entry.offset + 1
                            Toggle(entry.element, isOn: Binding(
                                get: { (tracker.weekdays ?? [tracker.weekday]).contains(day) },
                                set: { selected in
                                    var days = Set(tracker.weekdays ?? [tracker.weekday])
                                    if selected { days.insert(day) } else { days.remove(day) }
                                    tracker.weekdays = days.sorted()
                                }
                            )).toggleStyle(.checkbox)
                        }
                    }
                }
            case .monthlyDay:
                Stepper("Day \(tracker.monthDay)", value: $tracker.monthDay, in: 1...31)
                    .onChange(of: tracker.monthDay) { _, _ in tracker.dateOverride = nil }
                Picker("On weekends", selection: $tracker.weekendRule) {
                    ForEach(WeekendRule.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: tracker.weekendRule) { _, _ in tracker.dateOverride = nil }
            case .monthlyWorkday:
                Picker("Working day", selection: $tracker.ordinal) {
                    ForEach(1...23, id: \.self) { number in
                        Text("Working day \(number)").tag(number)
                    }
                    Text("Last working day").tag(-1)
                }
            case .ordinalWeekday:
                Picker("Occurrence", selection: $tracker.ordinal) {
                    ForEach(Array(["First", "Second", "Third", "Fourth", "Fifth", "Last"].enumerated()), id: \.offset) { entry in
                        Text(entry.element).tag(entry.offset == 5 ? -1 : entry.offset + 1)
                    }
                }
                .onChange(of: tracker.ordinal) { _, _ in tracker.dateOverride = nil }
                Picker("Weekday", selection: $tracker.weekday) {
                    ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { entry in
                        Text(entry.element).tag(entry.offset + 1)
                    }
                }
                .onChange(of: tracker.weekday) { _, _ in tracker.dateOverride = nil }
                Picker("If non-working", selection: $tracker.weekendRule) {
                    ForEach(WeekendRule.allCases) { Text($0.rawValue).tag($0) }
                }
            case .yearly:
                DatePicker("Anniversary date", selection: $tracker.end, displayedComponents: .date)
                    .onChange(of: tracker.end) { _, _ in tracker.dateOverride = nil }
            case .firstWorkday, .lastWorkday:
                Text("Working days are Monday to Friday.").font(.caption).foregroundStyle(.secondary)
            }
            if [.monthlyDay, .monthlyWorkday, .firstWorkday, .lastWorkday, .ordinalWeekday].contains(tracker.repeatRule) {
                Text("Working days are Monday to Friday. Add holidays below.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array((tracker.excludedDates ?? []).enumerated()), id: \.offset) { entry in
                    HStack {
                        DatePicker("Holiday", selection: Binding(
                            get: { (tracker.excludedDates ?? [])[entry.offset] },
                            set: { tracker.excludedDates?[entry.offset] = $0 }
                        ), displayedComponents: .date)
                        Button("Remove") { tracker.excludedDates?.remove(at: entry.offset) }
                    }
                }
                Button("Add holiday") {
                    var dates = tracker.excludedDates ?? []
                    dates.append(Date())
                    tracker.excludedDates = dates
                }
            }
            Picker("Show", selection: $tracker.showPercentage) {
                Text("Days remaining").tag(false)
                Text("Percentage").tag(true)
            }
            if let override = tracker.dateOverride {
                DatePicker("Override date", selection: Binding(
                    get: { tracker.dateOverride?.replacement ?? override.replacement },
                    set: { tracker.dateOverride = .init(original: override.original, replacement: $0) }
                ), in: today..., displayedComponents: .date)
                Button("Remove override") { tracker.dateOverride = nil }
            } else if let next = tracker.upcoming(from: today, count: 1).first {
                Button("Override next date") {
                    tracker.dateOverride = .init(original: next, replacement: next)
                }
            }
        }
    }
}
