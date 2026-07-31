import AppKit
import SwiftUI

struct MenuBarStatusSegment: Equatable {
    let summary: MenuBarUsageSummary
    let filledCount: Int
    let emptyCount: Int
    let percentText: String
}

func makeMenuBarStatusSegments(
    from summaries: [MenuBarUsageSummary]
) -> [MenuBarStatusSegment] {
    summaries.map { summary in
        let filledCount = min(5, max(0, Int((summary.usedPercent / 20).rounded())))
        return MenuBarStatusSegment(
            summary: summary,
            filledCount: filledCount,
            emptyCount: 5 - filledCount,
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

            if let mark = brandMark(for: summary.provider) {
                segment = segment + Text(Image(nsImage: mark))
            } else {
                segment = segment + Text(summary.provider.shortName)
            }

            if store.menuBarDisplayStyle.showsBar {
                segment = segment
                    + Text(" ")
                    + Text(String(repeating: "▰", count: status.filledCount))
                        .foregroundColor(barColor(for: summary))
                    + Text(String(repeating: "▱", count: status.emptyCount))
                        .foregroundColor(.primary.opacity(0.28))
            }

            if store.menuBarDisplayStyle.showsPercent {
                segment = segment
                    + Text(" ")
                    + Text(status.percentText)
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

    private func brandMark(for kind: ProviderKind) -> NSImage? {
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

        let size = NSSize(width: 13, height: 13)
        let result = NSImage(size: size)
        result.lockFocus()
        brandBackground(for: kind).setFill()
        NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size),
            xRadius: 3,
            yRadius: 3
        ).fill()
        source.draw(
            in: NSRect(x: 2.5, y: 2.5, width: 8, height: 8),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
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

    private func barColor(for summary: MenuBarUsageSummary) -> Color {
        switch store.menuBarColorStyle {
        case .provider:
            return summary.provider.color
        case .trafficLight:
            if summary.usedPercent >= 90 { return .red }
            if summary.usedPercent >= 70 { return .orange }
            return .green
        case .monochrome:
            return Color.primary
        }
    }
}
