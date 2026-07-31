import SwiftUI

struct ProviderCard: View {
    let kind: ProviderKind
    let state: ProviderState
    let isRefreshing: Bool
    let enabledWindowKinds: Set<QuotaWindowKind>
    let enabledDisplayOptions: Set<DisplayOption>
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProviderBrandMark(kind: kind)

                Text(kind.name)
                    .font(.headline)

                Spacer()

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("\(kind.name) 새로고침")
                }
            }

            content
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loaded(let snapshot):
            if enabledDisplayOptions.contains(.plan),
               let plan = snapshot.plan, !plan.isEmpty {
                Text(plan.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            let visibleWindows = snapshot.windows.filter {
                enabledWindowKinds.contains($0.kind)
            }
            ForEach(visibleWindows) { window in
                quotaRow(window)
            }
            if visibleWindows.isEmpty {
                Text("설정에서 표시할 한도 항목을 선택해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if enabledDisplayOptions.contains(.lastUpdated) {
                Text("\(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)) 갱신")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .needsConfiguration(let message):
            stateMessage(message, icon: "person.crop.circle.badge.exclamationmark")

        case .failed(let message):
            stateMessage(message, icon: "exclamationmark.triangle")

        case .loading:
            Text("한도를 불러오는 중…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .idle:
            Text("새로고침하면 현재 한도를 조회합니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func quotaRow(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(window.clampedPercent.rounded()))% 사용")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: window.clampedPercent, total: 100)
                .tint(progressColor(window.clampedPercent))
            if enabledDisplayOptions.contains(.resetTime), let reset = window.resetsAt {
                Text("리셋 \(reset.formatted(.relative(presentation: .named))) · \(reset.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func progressColor(_ percent: Double) -> Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return kind.color
    }

    private func stateMessage(_ message: String, icon: String) -> some View {
        Label(message, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
