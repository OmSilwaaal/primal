import SwiftUI

/// The legal documents bundled in Resources/Legal. The same Markdown is published on the website,
/// so the in-app copy and the App Store privacy policy URL never drift apart.
enum LegalDocument: String, Identifiable {
    case privacy = "privacy-policy"
    case terms = "terms-of-service"

    var id: String { rawValue }
    var title: String { self == .privacy ? "Privacy Policy" : "Terms of Service" }

    var markdown: String {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "This document couldn't be loaded. Contact support for a copy."
        }
        return text
    }
}

/// Renders the small Markdown subset the documents use: #/##/### headings, "- " bullets and paragraphs.
/// Inline **bold** and links go through AttributedString.
struct LegalView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    private enum Block: Hashable {
        case heading(String, level: Int)
        case bullet(String)
        case paragraph(String)
    }

    private var blocks: [Block] {
        document.markdown.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("### ") { return .heading(String(line.dropFirst(4)), level: 3) }
            if line.hasPrefix("## ") { return .heading(String(line.dropFirst(3)), level: 2) }
            // The title is already in the header bar.
            if line.hasPrefix("# ") { return nil }
            if line.hasPrefix("- ") { return .bullet(String(line.dropFirst(2))) }
            return .paragraph(line)
        }
    }

    var body: some View {
        ZStack {
            Color.ncBg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(document.title).font(.ui(size: 17, weight: .bold)).foregroundColor(.ncPrimary)
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(.glass)
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, 12)
                Hairline()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            view(for: block)
                        }
                    }
                    .padding(Space.margin)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let text, let level):
            Text(text)
                .font(.ui(size: level == 2 ? 19 : 16, weight: .bold))
                .foregroundColor(.ncPrimary)
                .padding(.top, level == 2 ? 16 : 6)
                .accessibilityAddTraits(.isHeader)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•").foregroundColor(.ncSecondary)
                inline(text)
            }
        case .paragraph(let text):
            inline(text)
        }
    }

    private func inline(_ text: String) -> some View {
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
            .font(.ui(size: 15))
            .foregroundColor(.ncPrimary.opacity(0.88))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .tint(.ncPrimary)
            .textSelection(.enabled)
    }
}

/// "Terms · Privacy" links shown wherever someone signs up or pays.
struct LegalLinks: View {
    @State private var shown: LegalDocument?
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                Button("Terms of Service") { shown = .terms }.fixedSize()
                Text("·")
                Button("Privacy Policy") { shown = .privacy }.fixedSize()
            }
            VStack(spacing: 4) {
                Button("Terms of Service") { shown = .terms }
                Button("Privacy Policy") { shown = .privacy }
            }
        }
        .font(.ui(size: 12))
        .foregroundColor(.ncPrimary.opacity(0.7))
        .sheet(item: $shown) { LegalView(document: $0) }
    }
}
