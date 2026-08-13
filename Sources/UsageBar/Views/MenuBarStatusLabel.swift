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
        let style = store.menuBarIconStyle
        let graphicWidth = graphicWidth(for: style)
        let textGap: CGFloat = style.showsExternalPercent && graphicWidth > 0 ? 4 : 0
        let segmentGap: CGFloat = 10
        let percentWidths = segments.map { status -> CGFloat in
            guard style.showsExternalPercent else { return 0 }
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

                drawStatusGraphic(for: status, style: style, at: NSPoint(x: x, y: 0))
                x += graphicWidth

                guard style.showsExternalPercent else { continue }
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
        style: MenuBarIconStyle,
        at origin: NSPoint
    ) {
        let summary = status.summary
        let kind = summary.provider

        guard style != .minimal else { return }

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

        switch style {
        case .battery:
            drawBattery(for: status, at: origin)
        case .circular:
            drawCircular(for: status, at: origin)
        case .segments:
            drawSegments(for: status, at: origin)
        case .dualBar:
            drawDualBar(for: status, at: origin)
        case .gauge:
            drawGauge(for: status, at: origin)
        case .minimal:
            break
        }
    }

    private func graphicWidth(for style: MenuBarIconStyle) -> CGFloat {
        switch style {
        case .battery, .segments, .dualBar: 51
        case .circular: 42
        case .gauge: 45
        case .minimal: 0
        }
    }

    private func drawBattery(for status: MenuBarStatusSegment, at origin: NSPoint) {
        let trackRect = NSRect(x: origin.x + 22, y: origin.y + 5, width: 28, height: 6)
        drawTrack(
            in: trackRect,
            fraction: status.fillFraction,
            color: statusColor(for: status.summary)
        )
    }

    private func drawCircular(for status: MenuBarStatusSegment, at origin: NSPoint) {
        let color = statusColor(for: status.summary)
        let circleRect = NSRect(x: origin.x + 22, y: origin.y + 0.75, width: 14.5, height: 14.5)
        let center = NSPoint(x: circleRect.midX, y: circleRect.midY)
        let radius = circleRect.width / 2 - 1.5

        color.withAlphaComponent(0.2).setStroke()
        let background = NSBezierPath(ovalIn: circleRect.insetBy(dx: 1, dy: 1))
        background.lineWidth = 2.5
        background.stroke()

        if status.fillFraction > 0 {
            color.setStroke()
            let progress = NSBezierPath()
            progress.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - 360 * status.fillFraction,
                clockwise: true
            )
            progress.lineWidth = 2.5
            progress.lineCapStyle = .round
            progress.stroke()
        }

        let number = "\(Int(status.summary.usedPercent.rounded()))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 6.5, weight: .bold),
            .foregroundColor: color
        ]
        let textSize = number.size(withAttributes: attributes)
        number.draw(
            at: NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func drawSegments(for status: MenuBarStatusSegment, at origin: NSPoint) {
        let color = statusColor(for: status.summary)
        let filledCount = Int(ceil(status.fillFraction * 5))
        let heights: [CGFloat] = [6, 8, 10, 12, 14]

        for index in 0..<5 {
            let height = heights[index]
            let rect = NSRect(
                x: origin.x + 22 + CGFloat(index) * 5.5,
                y: origin.y + (16 - height) / 2,
                width: 4,
                height: height
            )
            let segment = NSBezierPath(roundedRect: rect, xRadius: 1.25, yRadius: 1.25)
            (index < filledCount ? color : color.withAlphaComponent(0.18)).setFill()
            segment.fill()
        }
    }

    private func drawDualBar(for status: MenuBarStatusSegment, at origin: NSPoint) {
        let color = statusColor(for: status.summary)
        drawTrack(
            in: NSRect(x: origin.x + 22, y: origin.y + 9, width: 28, height: 4),
            fraction: status.fillFraction,
            color: color,
            drawsBorder: false
        )
        drawTrack(
            in: NSRect(x: origin.x + 22, y: origin.y + 3, width: 28, height: 4),
            fraction: 1 - status.fillFraction,
            color: NSColor.systemPurple,
            drawsBorder: false
        )
    }

    private func drawGauge(for status: MenuBarStatusSegment, at origin: NSPoint) {
        let color = statusColor(for: status.summary)
        let center = NSPoint(x: origin.x + 31.5, y: origin.y + 4)
        let radius: CGFloat = 8

        color.withAlphaComponent(0.2).setStroke()
        let background = NSBezierPath()
        background.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 180,
            clockwise: false
        )
        background.lineWidth = 2.5
        background.lineCapStyle = .round
        background.stroke()

        if status.fillFraction > 0 {
            color.setStroke()
            let progress = NSBezierPath()
            progress.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 180,
                endAngle: 180 - 180 * status.fillFraction,
                clockwise: true
            )
            progress.lineWidth = 2.5
            progress.lineCapStyle = .round
            progress.stroke()
        }

        let angle = Double.pi * (1 - status.fillFraction)
        let needle = NSBezierPath()
        needle.move(to: center)
        needle.line(to: NSPoint(
            x: center.x + cos(angle) * 6,
            y: center.y + sin(angle) * 6
        ))
        color.setStroke()
        needle.lineWidth = 1.25
        needle.stroke()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)).fill()
    }

    private func drawTrack(
        in rect: NSRect,
        fraction: CGFloat,
        color: NSColor,
        drawsBorder: Bool = true
    ) {
        let track = NSBezierPath(
            roundedRect: rect,
            xRadius: rect.height / 2,
            yRadius: rect.height / 2
        )
        color.withAlphaComponent(0.18).setFill()
        track.fill()

        if drawsBorder {
            color.withAlphaComponent(0.55).setStroke()
            track.lineWidth = 0.75
            track.stroke()
        }

        guard fraction > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        color.setFill()
        NSRect(
            x: rect.minX,
            y: rect.minY,
            width: max(1.5, rect.width * min(max(fraction, 0), 1)),
            height: rect.height
        ).fill()
        NSGraphicsContext.restoreGraphicsState()
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
