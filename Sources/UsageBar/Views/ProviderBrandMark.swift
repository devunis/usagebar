import AppKit
import SwiftUI

struct ProviderBrandMark: View {
    let kind: ProviderKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
                }

            if let image = brandImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                Text(kind.shortName)
                    .font(.caption.bold())
                    .foregroundStyle(kind.color)
            }
        }
        .frame(width: 28, height: 28)
        .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
        .accessibilityHidden(true)
    }

    private var background: Color {
        switch kind {
        case .codex:
            Color.white
        case .anthropic:
            Color(red: 1.0, green: 0.96, blue: 0.91)
        case .gemini:
            Color(red: 0.95, green: 0.97, blue: 1.0)
        }
    }

    private var brandImage: NSImage? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources
            .appendingPathComponent("BrandMarks", isDirectory: true)
            .appendingPathComponent("\(assetName).svg")
        return NSImage(contentsOf: url)
    }

    private var assetName: String {
        switch kind {
        case .codex: "openai"
        case .anthropic: "claude"
        case .gemini: "gemini"
        }
    }
}
