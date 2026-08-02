import AppKit
import SwiftUI

struct MenuBarStatusSegment: Equatable {
    let summary: MenuBarUsageSummary
    let fillFraction: CGFloat
    let percentText: String
}

func makeMenuBarStatusSegments(
    from summaries: [MenuBarUsageSummary]
) -> [MenuBarStatusSegment] {
    summaries.map { summary in
        return MenuBarStatusSegment(
            summary: summary,
            fillFraction: min(1, max(0, summary.usedPercent / 100)),
            percentText: "\(Int(summary.usedPercent.rounded()))%"
        )
    }
}

struct MenuBarStatusLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        statusText
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var statusText: Text {
        let segments = makeMenuBarStatusSegments(from: store.menuBarUsageSummaries)
        guard !segments.isEmpty else {
            return Text(Image(systemName: "chart.bar.xaxis"))
        }

        return segments.enumerated().reduce(Text("")) { result, element in
            let (index, status) = element
            let summary = status.summary
            var segment = index == 0 ? Text("") : Text("  ")

            if let graphic = statusGraphic(for: status) {
                segment = segment + Text(Image(nsImage: graphic))
            } else {
                segment = segment + Text(summary.provider.shortName)
            }

            if store.menuBarDisplayStyle.showsPercent {
                segment = segment
                    + Text(" ")
                    + Text(status.percentText)
                        .foregroundColor(Color(nsColor: statusColor(for: summary)))
            }

            return result + segment
        }
    }

    private var accessibilityText: String {
        let summaries = store.menuBarUsageSummaries
        guard !summaries.isEmpty else {
            return "UsageBar"
        }
        return summaries.map {
            "\($0.provider.name) \($0.title) \(Int($0.usedPercent.rounded()))퍼센트 사용"
        }.joined(separator: ", ")
    }

    private func statusGraphic(for status: MenuBarStatusSegment) -> NSImage? {
        let summary = status.summary
        let kind = summary.provider
        guard let resources = Bundle.main.resourceURL else { return nil }
        let assetName = switch kind {
        case .codex: "openai"
        case .anthropic: "claude"
        case .gemini: "gemini"
        }
        let url = resources
            .appendingPathComponent("BrandMarks", isDirectory: true)
            .appendingPathComponent("\(assetName).svg")
        guard let source = NSImage(contentsOf: url) else { return nil }

        let showsBar = store.menuBarDisplayStyle.showsBar
        let size = NSSize(width: showsBar ? 47 : 15, height: 15)
        let result = NSImage(size: size)
        result.lockFocus()

        let badgeRect = NSRect(x: 0.5, y: 0.5, width: 14, height: 14)
        brandBackground(for: kind).setFill()
        NSBezierPath(
            roundedRect: badgeRect,
            xRadius: 4,
            yRadius: 4
        ).fill()
        providerColor(for: kind).setStroke()
        let badgeBorder = NSBezierPath(
            roundedRect: badgeRect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 3.5,
            yRadius: 3.5
        )
        badgeBorder.lineWidth = 1
        badgeBorder.stroke()

        source.draw(
            in: NSRect(x: 3, y: 3, width: 9, height: 9),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        if showsBar {
            let trackRect = NSRect(x: 18, y: 4.5, width: 28, height: 6)
            let track = NSBezierPath(
                roundedRect: trackRect,
                xRadius: trackRect.height / 2,
                yRadius: trackRect.height / 2
            )

            statusColor(for: summary).withAlphaComponent(0.22).setFill()
            track.fill()

            statusColor(for: summary).withAlphaComponent(0.65).setStroke()
            track.lineWidth = 0.75
            track.stroke()

            if status.fillFraction > 0 {
                NSGraphicsContext.saveGraphicsState()
                track.addClip()
                statusColor(for: summary).setFill()
                NSRect(
                    x: trackRect.minX,
                    y: trackRect.minY,
                    width: max(1.5, trackRect.width * status.fillFraction),
                    height: trackRect.height
                ).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    private func brandBackground(for kind: ProviderKind) -> NSColor {
        switch kind {
        case .codex:
            .white
        case .anthropic:
            NSColor(srgbRed: 1, green: 0.96, blue: 0.91, alpha: 1)
        case .gemini:
            NSColor(srgbRed: 0.95, green: 0.97, blue: 1, alpha: 1)
        }
    }

    private func providerColor(for kind: ProviderKind) -> NSColor {
        switch kind {
        case .codex:
            NSColor(srgbRed: 0.08, green: 0.65, blue: 0.52, alpha: 1)
        case .anthropic:
            NSColor(srgbRed: 0.82, green: 0.48, blue: 0.30, alpha: 1)
        case .gemini:
            NSColor(srgbRed: 0.34, green: 0.48, blue: 0.94, alpha: 1)
        }
    }

    private func statusColor(for summary: MenuBarUsageSummary) -> NSColor {
        switch store.menuBarColorStyle {
        case .provider:
            return providerColor(for: summary.provider)
        case .trafficLight:
            if summary.usedPercent >= 90 { return .systemRed }
            if summary.usedPercent >= 70 { return .systemOrange }
            return .systemGreen
        case .monochrome:
            return .labelColor
        }
    }
}
