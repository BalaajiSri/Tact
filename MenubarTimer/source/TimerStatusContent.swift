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

    func render(_ timers: Timers, on button: NSStatusBarButton) -> CGFloat? {
        let ordered = timers.active.sorted { $0.deadline < $1.deadline }
        let screenWidth = (button.window?.screen ?? NSScreen.main)?.frame.width ?? 1280
        let layout = TimerStatusLayout(count: ordered.count, budget: min(300, max(88, screenWidth * 0.21)))
        let hidden = ordered.count - layout.visible
        let segments = ordered.isEmpty
            ? [Segment(icon: timers.finished.isEmpty ? "timer" : "checkmark.circle.fill",
                       color: timers.finished.last?.color ?? .indigo, countdown: nil)]
            : ordered.prefix(layout.visible).enumerated().map { index, timer in
                Segment(icon: timer.icon ?? "timer", color: timer.color ?? .indigo,
                        countdown: index < layout.expanded ? timers.remaining(timer) : nil)
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

        let description = ordered.isEmpty
            ? (timers.finished.isEmpty ? "No running timers" : "\(timers.finished.count) finished")
            : ordered.map { "\($0.title)  \(timers.remaining($0))" }.joined(separator: "\n")
        if description != lastDescription {
            button.toolTip = description
            button.subviews.first(where: { $0 is StatusControl })?
                .setAccessibilityLabel("Menu Bar Timer. " + description)
            lastDescription = description
        }
        return updatedWidth
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
