import SwiftUI

struct MenuBarStatusLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.bar.xaxis")

            if let summary = store.menuBarUsageSummary {
                if store.menuBarDisplayStyle.showsBar {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.primary.opacity(0.18))
                            .frame(width: 30, height: 5)
                        Capsule()
                            .fill(barColor(for: summary))
                            .frame(
                                width: 30 * summary.usedPercent / 100,
                                height: 5
                            )
                    }
                }

                if store.menuBarDisplayStyle.showsPercent {
                    Text("\(Int(summary.usedPercent.rounded()))%")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let summary = store.menuBarUsageSummary else {
            return "UsageBar"
        }
        return "\(summary.provider.name) \(summary.title) \(Int(summary.usedPercent.rounded()))퍼센트 사용"
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
