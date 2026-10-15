import SwiftUI

// Disambiguate the property wrapper from the SDK's same-named State macro.
private typealias ConfirmationState = State<Bool>

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
    let connectClaudeBenefits: () -> Void
    let claudeBenefitsMessage: String?
    var claudeRefreshMessage: String? = nil
    var claudeConnectionRequired: Bool = false
    @ConfirmationState private var showsResetConfirmation = false
    @ConfirmationState private var showsClaudeConnectionConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProviderBrandMark(kind: kind)

                Text(kind.name)
                    .font(.headline)

                Spacer()

                if kind == .anthropic, needsClaudeConnection {
                    Button("다시 연결…") { showsClaudeConnectionConfirmation = true }
                        .font(.caption)
                        .disabled(isRefreshing)
                }

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
            if kind == .anthropic, let claudeRefreshMessage {
                Text(claudeRefreshMessage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if case .loaded(let snapshot) = state {
                    Text("마지막 성공: \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
        .confirmationDialog(
            "Claude 로그인 정보를 연결할까요?",
            isPresented: $showsClaudeConnectionConfirmation,
            titleVisibility: .visible
        ) {
            Button("로그인 정보 연결") { connectClaudeBenefits() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("사용량·크레딧·초기화 정보를 조회하기 위해 기존 Claude 로그인 정보 접근을 요청합니다. 지금은 macOS 키체인 허용 창이 나타날 수 있습니다. 자동 새로고침에서는 허용 창 없이 재시도합니다.")
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
            if kind == .anthropic,
               enabledDisplayOptions.contains(.resetCredit) || enabledDisplayOptions.contains(.cloudCredits) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    claudeBenefitsSection(snapshot.claudeBenefits, now: context.date)
                }
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

    private var needsClaudeConnection: Bool {
        if claudeConnectionRequired { return true }
        if case .needsConfiguration = state { return true }
        guard enabledDisplayOptions.contains(.resetCredit) || enabledDisplayOptions.contains(.cloudCredits) else {
            return false
        }
        guard case .loaded(let snapshot) = state else { return false }
        return snapshot.claudeBenefits?.unavailableMessage != nil
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

    private func claudeBenefitsSection(
        _ benefits: ClaudeAccountBenefits?, now: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if enabledDisplayOptions.contains(.resetCredit) {
                HStack {
                    Label("제한 초기화", systemImage: "arrow.counterclockwise.circle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let inventory = benefits?.resets {
                        let count = inventory.availableCount(at: now)
                        Text(count > 0 ? "\(count)회 사용 가능" : "현재 초기화 없음")
                            .font(.caption)
                            .foregroundStyle(count > 0 ? kind.color : .secondary)
                    } else {
                        Text("조회 불가").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let expiry = benefits?.resets?.nextExpiration(at: now) {
                    Text("\(expiry.formatted(date: .abbreviated, time: .shortened)) 만료")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if enabledDisplayOptions.contains(.cloudCredits) {
                HStack {
                    Label("클라우드 세션 크레딧", systemImage: "cloud")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let credits = benefits?.cloudCredits {
                        Text("\(usd(credits.remainingUSD)) 남음")
                            .font(.caption.monospacedDigit())
                    } else {
                        Text("조회 불가").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let credits = benefits?.cloudCredits {
                    let expired = credits.isExpired(at: now)
                    ProgressView(value: credits.usedPercent, total: 100)
                        .tint(expired || credits.locked ? .gray : kind.color)
                    HStack {
                        Text("\(usd(credits.allowanceUSD)) 중 \(usd(credits.allowanceUSD - credits.remainingUSD)) 사용")
                        Spacer()
                        if expired { Text("만료됨") }
                        else if credits.locked { Text("사용 불가") }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    if let expiry = credits.expiresAt {
                        Text("\(expiry.formatted(date: .abbreviated, time: .shortened)) 만료")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if let message = benefits?.unavailableMessage {
                Text(message).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = claudeBenefitsMessage {
                Text(message).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Link("Claude에서 확인·초기화 ↗", destination: URL(string: "https://claude.ai/settings/usage")!)
                .font(.caption)
        }
    }

    private func usd(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD"))
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
