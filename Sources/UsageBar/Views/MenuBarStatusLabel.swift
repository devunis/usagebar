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
        Group {
            if let statusImage {
                Image(nsImage: statusImage)
                    .renderingMode(.original)
            } else {
                Image(systemName: "chart.bar.xaxis")
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var statusImage: NSImage? {
        let segments = makeMenuBarStatusSegments(from: store.menuBarUsageSummaries)
        guard !segments.isEmpty else { return nil }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let graphicWidth: CGFloat = store.menuBarDisplayStyle.showsBar ? 51 : 15
        let textGap: CGFloat = store.menuBarDisplayStyle.showsPercent ? 4 : 0
        let segmentGap: CGFloat = 10
        let percentWidths = segments.map { status -> CGFloat in
            guard store.menuBarDisplayStyle.showsPercent else { return 0 }
            return ceil((status.percentText as NSString).size(withAttributes: [.font: font]).width)
        }

        let contentWidth = segments.indices.reduce(CGFloat.zero) { width, index in
            width + graphicWidth + textGap + percentWidths[index]
        } + segmentGap * CGFloat(max(0, segments.count - 1))
        let size = NSSize(width: ceil(contentWidth), height: 16)
        let result = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0

            for (index, status) in segments.enumerated() {
                if index > 0 { x += segmentGap }

                drawStatusGraphic(for: status, at: NSPoint(x: x, y: 0))
                x += graphicWidth

                guard store.menuBarDisplayStyle.showsPercent else { continue }
                x += textGap

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: statusColor(for: status.summary)
                ]
                let text = status.percentText as NSString
                let textSize = text.size(withAttributes: attributes)
                text.draw(
                    at: NSPoint(x: x, y: floor((size.height - textSize.height) / 2)),
                    withAttributes: attributes
                )
                x += percentWidths[index]
            }

            return true
        }
        result.isTemplate = false
        return result
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

    private func drawStatusGraphic(
        for status: MenuBarStatusSegment,
        at origin: NSPoint
    ) {
        let summary = status.summary
        let kind = summary.provider
        let showsBar = store.menuBarDisplayStyle.showsBar

        if let source = brandImage(for: kind) {
            let markRect = NSRect(
                x: origin.x + 0.5,
                y: origin.y + 1.5,
                width: 13,
                height: 13
            )
            source.draw(
                in: markRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )

            if kind == .codex {
                NSColor.labelColor.setFill()
                markRect.fill(using: .sourceIn)
            }
        }

        if showsBar {
            let trackRect = NSRect(
                x: origin.x + 22,
                y: origin.y + 5,
                width: 28,
                height: 6
            )
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
    }

    private func brandImage(for kind: ProviderKind) -> NSImage? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let assetName = switch kind {
        case .codex: "openai"
        case .anthropic: "claude"
        case .gemini: "gemini"
        }
        let url = resources
            .appendingPathComponent("BrandMarks", isDirectory: true)
            .appendingPathComponent("\(assetName).svg")
        return NSImage(contentsOf: url)
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
