import SwiftUI

struct ProviderCard: View {
    let kind: ProviderKind
    let state: ProviderState
    let isRefreshing: Bool
    let enabledWindowKinds: Set<QuotaWindowKind>
    let enabledDisplayOptions: Set<DisplayOption>
    let isConsumingResetCredit: Bool
    let resetMessage: String?
    let refresh: () -> Void
    let consumeResetCredit: (String?) -> Void
    @State private var showsResetConfirmation = false

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
        .confirmationDialog(
            "사용 한도를 재설정할까요?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("재설정 크레딧 1회 사용", role: .destructive) {
                consumeResetCredit(currentResetCredits?.nextAvailableCredit?.id)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("5시간 및 주간 한도가 함께 재설정됩니다. 사용한 크레딧은 되돌릴 수 없습니다.")
        }
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
            if kind == .codex,
               enabledDisplayOptions.contains(.resetCredit),
               let resetCredits = snapshot.resetCredits {
                resetCreditSection(resetCredits)
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

    private var currentResetCredits: RateLimitResetCreditsSummary? {
        guard case .loaded(let snapshot) = state else { return nil }
        return snapshot.resetCredits
    }

    private func resetCreditSection(
        _ summary: RateLimitResetCreditsSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack {
                Label("사용 한도 재설정", systemImage: "arrow.counterclockwise.circle.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(summary.availableCount)회 사용 가능")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.availableCount > 0 ? kind.color : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (summary.availableCount > 0 ? kind.color : Color.secondary)
                            .opacity(0.13),
                        in: Capsule()
                    )
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("전체 재설정 (주간 + 5시간)")
                        .font(.caption.weight(.medium))
                    if let expiration = summary.earliestExpiration {
                        Text("\(expiration.formatted(date: .abbreviated, time: .shortened)) 만료")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    showsResetConfirmation = true
                } label: {
                    if isConsumingResetCredit {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("재설정 사용")
                    }
                }
                .disabled(summary.availableCount == 0 || isConsumingResetCredit)
            }

            if let resetMessage, !resetMessage.isEmpty {
                Text(resetMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
