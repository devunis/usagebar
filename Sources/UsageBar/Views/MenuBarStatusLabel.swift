import SwiftUI

struct MenuBarStatusLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.bar.xaxis")

            if let summary = store.menuBarUsageSummary {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.18))
                        .frame(width: 30, height: 5)
                    Capsule()
                        .fill(summary.provider.color)
                        .frame(
                            width: 30 * summary.usedPercent / 100,
                            height: 5
                        )
                }

                Text("\(Int(summary.usedPercent.rounded()))%")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
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
}
