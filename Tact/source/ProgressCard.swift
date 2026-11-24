import SwiftUI

extension Color {
    init(rgb: String) {
        let hex = UInt32(rgb, radix: 16) ?? 0x675AD9
        self.init(red: Double(hex >> 16) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255)
    }
}

extension Tracker {
    var swatches: [String] {
        let index = (paletteID ?? 1) - 1
        return progressPalettes.indices.contains(index) ? progressPalettes[index] : progressPalettes[0]
    }

    var accentHex: String {
        if let customAccent { return customAccent }
        return swatches[min(max(0, swatchIndex ?? 0), swatches.count - 1)]
    }

    var gradientHex: String {
        swatches[(min(max(0, swatchIndex ?? 0), swatches.count - 1) + 1) % swatches.count]
    }
}

struct ProgressCard: View {
    let tracker: Tracker
    let date: Date
    @Environment(\.colorScheme) private var scheme

    private var accent: Color {
        if tracker.customAccent == nil, tracker.paletteID == nil,
           let legacy = TimerColor(rawValue: tracker.color) {
            return legacy.tint
        }
        return Color(rgb: tracker.accentHex)
    }

    var body: some View {
        let reading = tracker.reading(on: date)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: tracker.icon).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                Spacer()
                if let fraction = reading.fraction, (tracker.cardStyle ?? "Ring") == "Ring" {
                    ZStack {
                        Circle().strokeBorder(remaining, lineWidth: 4)
                        Circle().inset(by: 2).trim(from: 0, to: fraction)
                            .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 26, height: 26)
                    .accessibilityLabel("\(Int(fraction * 100)) percent complete")
                }
            }
            Spacer(minLength: 1)
            Text(tracker.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(reading.value).font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
            if let fraction = reading.fraction {
                progressDisplay(fraction, totalDays: reading.totalDays, elapsedDays: reading.elapsedDays)
            }
            Text(reading.detail).font(.caption).opacity(0.7)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(tracker.textHex.map { Color(rgb: $0) } ?? .primary)
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .leading)
        .background {
            surface.clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.09))
                }
        }
    }

    private var remaining: Color {
        tracker.remainingHex.map { Color(rgb: $0) } ?? accent.opacity(0.22)
    }

    @ViewBuilder private func progressDisplay(_ fraction: Double, totalDays: Int?, elapsedDays: Int?) -> some View {
        switch tracker.cardStyle ?? "Ring" {
        case "Dots", "Blocks":
            let isDots = tracker.cardStyle == "Dots"
            let count = max(1, totalDays ?? 20)
            let filled = min(count, max(0, elapsedDays ?? Int((fraction * Double(count)).rounded())))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: min(10, count)), spacing: 3) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: isDots ? 5 : 2)
                        .fill(index < filled ? accent : remaining)
                        .frame(height: isDots ? 8 : 10)
                }
            }
            .frame(maxHeight: 48)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int(fraction * 100)) percent complete")
        case "Bar":
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(remaining)
                    Capsule().fill(accent).frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 7)
            .accessibilityLabel("\(Int(fraction * 100)) percent complete")
        default:
            EmptyView()
        }
    }

    var surface: some View {
        ZStack {
            Rectangle().fill(tracker.backgroundHex.map { Color(rgb: $0) } ?? (scheme == .dark ? Color(rgb: "22232B") : Color(rgb: "FBFBFD")))
            if tracker.tinted == true {
                LinearGradient(colors: [accent, Color(rgb: tracker.gradientHex)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(scheme == .dark ? 0.28 : 0.21)
            }
        }
    }
}
