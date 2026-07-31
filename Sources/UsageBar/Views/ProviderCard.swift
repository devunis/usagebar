import SwiftUI

struct ProviderCard: View {
    let kind: ProviderKind
    let state: ProviderState
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(kind.shortName)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 25)
                    .background(kind.color.gradient, in: RoundedRectangle(cornerRadius: 7))

                Text(kind.name)
                    .font(.headline)

                Spacer()

                if case .loading = state {
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
            HStack(spacing: 20) {
                metric("토큰", value: snapshot.totalTokens.compactUsage)
                metric("입력", value: snapshot.inputTokens.compactUsage)
                metric("출력", value: snapshot.outputTokens.compactUsage)
                metric("요청", value: snapshot.requests.compactUsage)
            }
            Text("최근 30일 · \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)) 갱신")
                .font(.caption2)
                .foregroundStyle(.secondary)

        case .needsConfiguration(let message):
            stateMessage(message, icon: "key")

        case .failed(let message):
            stateMessage(message, icon: "exclamationmark.triangle")

        case .loading:
            Text("사용량을 불러오는 중…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .idle:
            Text("새로고침하면 최근 30일 사용량을 조회합니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func stateMessage(_ message: String, icon: String) -> some View {
        Label(message, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
