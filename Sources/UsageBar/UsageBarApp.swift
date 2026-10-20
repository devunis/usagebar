import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
enum UsageBarEntry {
    @MainActor
    static func main() async {
        let cliOnly = CommandLine.arguments.contains("--diagnose-claude-cli")
        if cliOnly || CommandLine.arguments.contains("--diagnose-claude-usage") {
            // Same signed app and existing consent; never interactive. This report
            // deliberately excludes tokens, account IDs and raw server responses.
            do {
                let snapshot = cliOnly
                    ? try await ClaudeCLIUsageProvider().fetchQuota()
                    : try await ClaudeQuotaProvider().fetchQuota()
                let report: [String: Any] = [
                    "status": "ok",
                    "mode": cliOnly ? "cli-only" : "cli-first",
                    "windows": snapshot.windows.map { ["title": $0.title, "usedPercent": $0.usedPercent] as [String: Any] }
                ]
                let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
                FileHandle.standardOutput.write(data)
                print("")
            } catch UsageProviderError.credentialExpired {
                print("{\"status\":\"token_expired\"}")
            } catch UsageProviderError.credentialAccessRequired {
                print("{\"status\":\"credential_access_unavailable\"}")
            } catch UsageProviderError.server(let status, _) {
                print("{\"status\":\"http_error\",\"code\":\(status)}")
            } catch {
                print("{\"status\":\"usage_unavailable\"}")
            }
            return
        }
        UsageBarApp.main()
    }
}

struct UsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
        } label: {
            MenuBarStatusLabel(store: store)
                .task {
                    store.refreshAll()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
