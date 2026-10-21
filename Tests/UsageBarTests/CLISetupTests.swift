import AppKit
import SwiftUI
import XCTest
@testable import UsageBar

final class CLISetupTests: XCTestCase {
    func testFirstRunOnlyOffersGuideForMissingEnabledCLIs() {
        XCTAssertTrue(shouldOfferCLISetup(hasSeenGuide: false, enabledProviders: [.codex, .anthropic], installedTools: []))
        XCTAssertTrue(shouldOfferCLISetup(hasSeenGuide: false, enabledProviders: [.codex, .anthropic], installedTools: [.codex]))
        XCTAssertFalse(shouldOfferCLISetup(hasSeenGuide: false, enabledProviders: [.codex, .anthropic], installedTools: [.codex, .claude]))
        XCTAssertFalse(shouldOfferCLISetup(hasSeenGuide: false, enabledProviders: [.codex], installedTools: [.codex]))
        XCTAssertFalse(shouldOfferCLISetup(hasSeenGuide: false, enabledProviders: [.gemini], installedTools: []))
        XCTAssertFalse(shouldOfferCLISetup(hasSeenGuide: false, enabledProviders: [], installedTools: []))
        XCTAssertFalse(shouldOfferCLISetup(hasSeenGuide: true, enabledProviders: [.codex, .anthropic], installedTools: []))
    }

    func testCommandsAndLinksUseOfficialInstallersAndSubscriptionLogin() {
        XCTAssertEqual(CLITool.codex.installationCommand, "curl -fsSL https://chatgpt.com/codex/install.sh | sh")
        XCTAssertEqual(CLITool.claude.installationCommand, "curl -fsSL https://claude.ai/install.sh | bash")
        XCTAssertEqual(CLITool.codex.documentationURL.host, "learn.chatgpt.com")
        XCTAssertEqual(CLITool.claude.documentationURL.host, "code.claude.com")
        XCTAssertEqual(CLITool.codex.loginCommand(executable: nil), "codex login")
        XCTAssertEqual(CLITool.claude.loginCommand(executable: nil), "claude auth login")
        for tool in CLITool.allCases {
            XCTAssertFalse(tool.installationCommand.contains("sudo"))
            XCTAssertFalse(tool.loginArguments.contains("console"))
            XCTAssertEqual(tool.candidates.count, 3)
        }
    }

    func testLoginUsesDetectedPathAndEscapesShellMetacharacters() {
        let executable = URL(fileURLWithPath: "/Users/Test's Mac/cli/$tools/claude")
        XCTAssertEqual(CLITool.claude.loginCommand(executable: executable),
                       "'/Users/Test'\\''s Mac/cli/$tools/claude' auth login")
    }

    @MainActor
    func testInstallationChecksDoNotRequireCLIExecutionOrAuthentication() {
        var calls: [CLITool] = []
        var available: [CLITool: URL] = [.codex: URL(fileURLWithPath: "/fixture/codex")]
        let suiteName = "UsageBar.CLISetupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let setup = CLISetupStore(defaults: defaults) { tool in
            calls.append(tool)
            return available[tool]
        }
        XCTAssertEqual(calls, [.codex, .claude])
        XCTAssertEqual(Set(setup.installations.keys), [.codex])
        XCTAssertFalse(defaults.bool(forKey: CLISetupStore.seenGuideKey))
        available[.claude] = URL(fileURLWithPath: "/fixture/claude")
        setup.checkInstallations()
        XCTAssertEqual(Set(setup.installations.keys), [.codex, .claude])
        XCTAssertEqual(calls.count, 4)
    }

    @MainActor
    func testGuideRendersMissingAndInstalledTools() throws {
        _ = NSApplication.shared
        let setup = CLISetupStore(findExecutable: { tool in
            tool == .codex ? URL(fileURLWithPath: "/opt/homebrew/bin/codex") : nil
        })
        let view = NSHostingView(rootView: CLISetupView()
            .environmentObject(setup).environmentObject(UsageStore()))
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 720)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        if let path = ProcessInfo.processInfo.environment["USAGEBAR_SETUP_PREVIEW_PATH"] {
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path))
        }
    }
}
