import AppKit
import SwiftUI

struct TimerStatusLayout: Equatable {
    static let iconWidth: CGFloat = 15
    static let separatorWidth: CGFloat = 8
    static let countdownWidth: CGFloat = 40
    static let overflowWidth: CGFloat = 40
    static let buttonPadding: CGFloat = 16

    let visible: Int
    let expanded: Int

    init(count: Int, budget: CGFloat) {
        let space = max(0, budget - Self.buttonPadding)
        let slot = Self.iconWidth + Self.separatorWidth
        let allIconsWidth = CGFloat(count) * slot - Self.separatorWidth
        let visible = allIconsWidth <= space
            ? count
            : min(count, max(1, Int((space - Self.overflowWidth) / slot)))
        let hidden = count - visible
        let baseWidth = CGFloat(visible) * slot - Self.separatorWidth
            + (hidden > 0 ? Self.overflowWidth : 0)
        self.visible = visible
        expanded = min(visible, max(0, Int((space - baseWidth) / Self.countdownWidth)))
    }
}

final class TimerStatusContent {
    private struct Segment: Equatable {
        let icon: String
        let color: TimerColor
        let countdown: String?
    }

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private var lastSegments: [Segment] = []
    private var lastHidden = 0
    private var lastDescription = ""
    private var symbols: [TimerColor: [String: NSImage]] = [:]

    func render(_ timers: Timers, routines: RoutineStore, on button: NSStatusBarButton) -> CGFloat? {
        let ordered = timers.active.filter { $0.pausedRemaining == nil }.sorted { $0.deadline < $1.deadline }
        let screenWidth = (button.window?.screen ?? NSScreen.main)?.frame.width ?? 1280
        var entries: [(segment: Segment, description: String)] = []
        if let run = routines.run {
            let activity = routines.current
            let label: String
            if let remaining = run.pausedRemaining {
                label = "Ⅱ " + formatted(remaining)
            } else if run.phase == "running" {
                label = formatted(run.deadline.timeIntervalSince(routines.now))
            } else if run.phase == "delay", let deadline = run.delayUntil {
                label = formatted(deadline.timeIntervalSince(routines.now))
            } else {
                label = run.phase == "sleep" ? "Wake" : "Choose"
            }
            let step = activity?.name ?? run.routine.name
            entries.append((Segment(icon: "arrow.triangle.2.circlepath",
                                    color: activity?.color ?? .indigo, countdown: label),
                            "Routine \(run.routine.name), \(step), \(label)"))
        }
        entries += ordered.map { timer in
            (Segment(icon: timer.icon ?? "timer", color: timer.color ?? .indigo,
                     countdown: timers.remaining(timer)), "\(timer.title)  \(timers.remaining(timer))")
        }
        let layout = TimerStatusLayout(count: entries.count, budget: min(300, max(88, screenWidth * 0.21)))
        let hidden = entries.count - layout.visible
        let segments = entries.isEmpty
            ? [Segment(icon: !timers.active.isEmpty ? "pause.circle" : (timers.finished.isEmpty ? "timer" : "checkmark.circle.fill"),
                       color: timers.finished.last?.color ?? .indigo, countdown: nil)]
            : entries.prefix(layout.visible).enumerated().map { index, entry in
                Segment(icon: entry.segment.icon, color: entry.segment.color,
                        countdown: index < layout.expanded || (index == 0 && routines.run != nil)
                            ? entry.segment.countdown : nil)
            }

        var updatedWidth: CGFloat?
        if segments != lastSegments || hidden != lastHidden {
            if let image = statusImage(segments, hidden: hidden) {
                button.image = image
                updatedWidth = max(28, ceil(image.size.width) + TimerStatusLayout.buttonPadding)
            }
            lastSegments = segments
            lastHidden = hidden
        }

        let description = entries.isEmpty
            ? (timers.finished.isEmpty ? "No running timers" : "\(timers.finished.count) finished")
            : entries.map(\.description).joined(separator: "\n")
        if description != lastDescription {
            button.toolTip = description
            button.subviews.first(where: { $0 is StatusControl })?
                .setAccessibilityLabel("Menu Bar Timer. " + description)
            lastDescription = description
        }
        return updatedWidth
    }

    private func formatted(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(value)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func statusImage(_ segments: [Segment], hidden: Int) -> NSImage? {
        if segments.count == 1, let segment = segments.first, segment.countdown == nil, hidden == 0 {
            return symbol(segment.icon, color: segment.color)
        }

        var x: CGFloat = 0
        var icons: [(NSImage, CGFloat)] = []
        var labels: [(String, CGFloat)] = []
        let measure: [NSAttributedString.Key: Any] = [.font: font]
        func addLabel(_ text: String) {
            labels.append((text, x))
            x += ceil((text as NSString).size(withAttributes: measure).width)
        }
        for (index, segment) in segments.enumerated() {
            if index > 0 { x += TimerStatusLayout.separatorWidth }
            if let image = symbol(segment.icon, color: segment.color) {
                icons.append((image, x))
            }
            x += TimerStatusLayout.iconWidth
            if let countdown = segment.countdown { addLabel(" " + countdown) }
        }
        if hidden > 0 { addLabel("  +\(hidden)") }

        let size = NSSize(width: x, height: 18)
        let font = font
        return NSImage(size: size, flipped: false) { _ in
            for (image, offset) in icons {
                let scale = min(TimerStatusLayout.iconWidth / image.size.width, 15 / image.size.height, 1)
                let width = image.size.width * scale
                let height = image.size.height * scale
                image.draw(in: NSRect(x: offset + (TimerStatusLayout.iconWidth - width) / 2,
                                      y: (size.height - height) / 2, width: width, height: height))
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            for (text, offset) in labels {
                let height = (text as NSString).size(withAttributes: attributes).height
                (text as NSString).draw(at: NSPoint(x: offset, y: (size.height - height) / 2),
                                        withAttributes: attributes)
            }
            return true
        }
    }

    private func symbol(_ name: String, color: TimerColor) -> NSImage? {
        if let cached = symbols[color]?[name] { return cached }
        let original = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        let size = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let palette = NSImage.SymbolConfiguration(paletteColors: [NSColor(color.tint)])
        let image = original?.withSymbolConfiguration(size.applying(palette))
        image?.isTemplate = false
        symbols[color, default: [:]][name] = image
        return image
    }
}
