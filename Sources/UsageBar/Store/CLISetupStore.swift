import AppKit
import SwiftUI

@MainActor
final class CLISetupStore: ObservableObject {
    @Published private(set) var installations: [CLITool: URL] = [:]
    @Published private(set) var message: String?
    private let defaults: UserDefaults
    private let findExecutable: (CLITool) -> URL?
    private var evaluatedStartup = false
    private var window: NSWindow?
    static let seenGuideKey = "UsageBar.hasSeenCLISetup"

    init(defaults: UserDefaults = .standard,
         findExecutable: @escaping (CLITool) -> URL? = { try? $0.resolveExecutable() }) {
        self.defaults = defaults
        self.findExecutable = findExecutable
        checkInstallations()
    }

    // File-system checks only: opening this guide never launches a CLI, reads a
    // credential, installs software, or starts login automatically.
    func checkInstallations() {
        installations = Dictionary(uniqueKeysWithValues: CLITool.allCases.compactMap { tool in
            findExecutable(tool).map { (tool, $0) }
        })
    }

    func offerOnFirstLaunch(using store: UsageStore) {
        guard !evaluatedStartup else { return }
        evaluatedStartup = true
        checkInstallations()
        let shouldShow = shouldOfferCLISetup(
            hasSeenGuide: defaults.bool(forKey: Self.seenGuideKey),
            enabledProviders: store.enabledProviders, installedTools: Set(installations.keys)
        )
        defaults.set(true, forKey: Self.seenGuideKey)
        if shouldShow { show(using: store) }
    }

    func show(using store: UsageStore) {
        checkInstallations()
        message = nil
        if window == nil {
            let view = CLISetupView().environmentObject(self).environmentObject(store)
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "UsageBar 시작하기"
            window.identifier = NSUserInterfaceItemIdentifier("UsageBar.CLISetup")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        message = "명령어를 복사했어요. 터미널에 붙여넣고 Enter를 눌러 주세요."
    }

    func openTerminal() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            message = "응용 프로그램 → 유틸리티에서 터미널을 직접 열어 주세요."
            return
        }
        // Open the app only. Never inject or execute a command in a user's shell.
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
            guard error != nil else { return }
            Task { @MainActor [weak self] in
                self?.message = "터미널을 열지 못했어요. 응용 프로그램 → 유틸리티에서 직접 열어 주세요."
            }
        }
    }

    func dismiss() { window?.close() }
}
