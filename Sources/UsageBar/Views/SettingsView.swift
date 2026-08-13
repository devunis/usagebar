import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        Form {
            Section("서비스") {
                Text("API 키를 저장하지 않습니다. 각 공식 CLI에 로그인된 계정의 한도만 읽습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                providerToggle(.codex, command: "codex login")
                providerToggle(.anthropic, command: "claude auth login")
                providerToggle(.gemini, command: "gemini")

                HStack {
                    Button("모두 켜기") {
                        store.setAllProviders(true)
                    }
                    Button("모두 끄기") {
                        store.setAllProviders(false)
                    }
                }

                if store.isEnabled(.anthropic) {
                    Button {
                        store.refresh(
                            .anthropic,
                            allowsCredentialPrompt: true
                        )
                    } label: {
                        Label("Claude Keychain 권한 요청", systemImage: "key")
                    }
                }
            }

            Section("표시 항목") {
                ForEach(QuotaWindowKind.allCases) { kind in
                    Toggle(kind.name, isOn: Binding(
                        get: { store.isWindowKindEnabled(kind) },
                        set: { store.setWindowKindEnabled($0, for: kind) }
                    ))
                }
                ForEach(DisplayOption.allCases.filter { $0 != .menuBarUsage }) { option in
                    Toggle(option.name, isOn: Binding(
                        get: { store.isDisplayOptionEnabled(option) },
                        set: { store.setDisplayOptionEnabled($0, for: option) }
                    ))
                }

                HStack {
                    Button("모두 표시") {
                        store.setAllDisplayItems(true)
                    }
                    Button("모두 숨기기") {
                        store.setAllDisplayItems(false)
                    }
                }
            }

            Section("메뉴바 사용량") {
                Toggle("메뉴바에 표시", isOn: Binding(
                    get: { store.isDisplayOptionEnabled(.menuBarUsage) },
                    set: { store.setDisplayOptionEnabled($0, for: .menuBarUsage) }
                ))

                Picker("서비스", selection: $store.menuBarProviderSelection) {
                    ForEach(MenuBarProviderSelection.allCases) { selection in
                        Text(selection.name).tag(selection)
                    }
                }

                Picker("Codex·Gemini 한도", selection: $store.menuBarLimitSelection) {
                    ForEach(MenuBarLimitSelection.allCases) { selection in
                        Text(selection.name).tag(selection)
                    }
                }

                Picker("Claude 한도", selection: $store.claudeMenuBarLimitSelection) {
                    ForEach(MenuBarLimitSelection.allCases) { selection in
                        Text(selection.name).tag(selection)
                    }
                }

                Picker("동시 표시", selection: $store.menuBarItemCount) {
                    Text("1개").tag(1)
                    Text("2개").tag(2)
                    Text("3개").tag(3)
                }

                MenuBarIconStylePicker(selection: $store.menuBarIconStyle)

                Picker("색상", selection: $store.menuBarColorStyle) {
                    ForEach(MenuBarColorStyle.allCases) { style in
                        Text(style.name).tag(style)
                    }
                }
            }

            Section("자동 새로고침") {
                Picker("주기", selection: $store.refreshIntervalMinutes) {
                    Text("수동").tag(0)
                    Text("5분").tag(5)
                    Text("15분").tag(15)
                    Text("30분").tag(30)
                    Text("60분").tag(60)
                }
            }

            Section {
                Button("지금 모두 새로고침") {
                    store.refreshAll()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 790)
    }

    private func providerToggle(_ kind: ProviderKind, command: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(kind.name, isOn: Binding(
                get: { store.isEnabled(kind) },
                set: { store.setEnabled($0, for: kind) }
            ))
            Text(command)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .padding(.leading, 20)
        }
    }
}

private struct MenuBarIconStylePicker: View {
    @Binding var selection: MenuBarIconStyle

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("아이콘 스타일")
                .font(.subheadline.weight(.medium))

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    Button {
                        selection = style
                    } label: {
                        VStack(spacing: 7) {
                            MenuBarIconStylePreview(style: style)
                                .frame(height: 31)
                                .frame(maxWidth: .infinity)
                                .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 6))

                            HStack(spacing: 4) {
                                Text(style.name)
                                if selection == style {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .padding(8)
                        .background(
                            selection == style
                                ? Color.accentColor.opacity(0.13)
                                : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(
                                    selection == style
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.28),
                                    lineWidth: selection == style ? 2 : 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MenuBarIconStylePreview: View {
    let style: MenuBarIconStyle

    private let accent = Color.orange

    var body: some View {
        HStack(spacing: 7) {
            switch style {
            case .battery:
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent).frame(width: 25)
                    }
                    .frame(width: 39, height: 10)
                Text("65%")
            case .circular:
                ZStack {
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: 0.65)
                        .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("65").font(.system(size: 8, weight: .bold, design: .rounded))
                }
                .frame(width: 25, height: 25)
            case .minimal:
                Text("65%")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            case .segments:
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(index < 3 ? accent : Color.white.opacity(0.18))
                            .frame(width: 5, height: CGFloat(8 + index * 2))
                    }
                }
            case .dualBar:
                VStack(spacing: 4) {
                    previewTrack(fraction: 0.65, color: accent)
                    previewTrack(fraction: 0.35, color: .purple)
                }
                Text("65%")
            case .gauge:
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 23))
                    .foregroundStyle(accent)
            }
        }
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundStyle(accent)
    }

    private func previewTrack(fraction: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.16))
            .overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: 35 * fraction)
            }
            .frame(width: 35, height: 5)
    }
}
