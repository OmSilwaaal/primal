import SwiftUI

/// The legal documents bundled in Resources/Legal. The same Markdown is published on the website,
/// so the in-app copy and the App Store privacy policy URL never drift apart.
enum LegalDocument: String, Identifiable, CaseIterable {
    case terms = "terms-of-service"
    case privacy = "privacy-policy"
    case safety = "health-safety-policy"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .terms: "Terms of Service"
        case .privacy: "Privacy Policy"
        case .safety: "Health & Safety Policy"
        }
    }

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
        // A glass sheet like every other in the app: the title large with a round close button, the text below.
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(document.title).font(.ui(size: 26, weight: .bold)).foregroundColor(Mono.text)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.bentoRound)
                    .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 24).padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        view(for: block)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 4)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .glassSheetBackground()
        .presentationCornerRadius(Bento.radius)
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

// MARK: - Acceptance

/// Records that the person agreed to the current Terms, Privacy Policy and Health & Safety Policy. Bump
/// `currentVersion` whenever any of them changes materially: everyone is asked to agree again.
enum LegalAcceptance {
    /// 2: AI moved to Anthropic's Claude (through our server) and usage limits were added to the Privacy Policy.
    static let currentVersion = 2
    private static let versionKey = "legalAcceptedVersion"
    private static let dateKey = "legalAcceptedAt"

    static var isCurrent: Bool { UserDefaults.standard.integer(forKey: versionKey) >= currentVersion }
    static var acceptedAt: Date? { UserDefaults.standard.object(forKey: dateKey) as? Date }

    static func accept() {
        UserDefaults.standard.set(currentVersion, forKey: versionKey)
        UserDefaults.standard.set(Date(), forKey: dateKey)
    }
}

/// Shown before the app can be used. A tick box the person must check themselves, links to all three policies,
/// and an "I agree" button that stays disabled until the box is ticked: an explicit, recorded agreement.
struct LegalConsentView: View {
    let onAgree: () -> Void
    @State private var agreed = false
    @State private var shown: LegalDocument?

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            AlgizMark().fill(Color.ncPrimary).frame(width: 14, height: 18).accessibilityHidden(true)
                            Text("Vitalis LLC").monoLabel()
                        }
                        .padding(.bottom, 8)
                        Text("Before you start").monoLabel()
                        Text("Vitalis is not medical advice")
                            .font(.ui(size: 28, weight: .bold)).foregroundColor(.ncPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Vitalis LLC is not a doctor, dietitian or any other health professional. Everything in the app is general information. You decide what to eat and do, and you use the app voluntarily and at your own risk. Raw and undercooked foods can cause serious illness.")
                            .font(.ui(size: 15)).foregroundColor(.ncSecondary).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // The three policies in one glass tile, like Legal & support.
                    VStack(spacing: 0) {
                        ForEach(Array(LegalDocument.allCases.enumerated()), id: \.element) { i, doc in
                            Button { shown = doc } label: {
                                HStack {
                                    Text(doc.title).font(.ui(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.ui(size: 12, weight: .semibold)).foregroundColor(Mono.label)
                                }
                                .frame(minHeight: 52)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) } }
                            .accessibilityHint("Opens the full text")
                        }
                    }
                    .bentoTile(padding: 16)

                    Button {
                        Haptics.selection()
                        withAnimation(.snappy) { agreed.toggle() }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24)).foregroundColor(agreed ? .vitalisLime : .ncPrimary.opacity(0.7))
                                .contentTransition(.symbolEffect(.replace))
                            Text("I have read and agree to the Terms of Service, Privacy Policy and Health & Safety Policy. I understand Vitalis LLC does not give medical advice, and I use the app of my own accord and at my own risk.")
                                .font(.ui(size: 14)).foregroundColor(.ncPrimary).multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .bentoTile(padding: 16)
                    .accessibilityAddTraits(agreed ? .isSelected : [])

                    Button("I agree") {
                        LegalAcceptance.accept()
                        Haptics.success()
                        onAgree()
                    }
                    .buttonStyle(.vitalis)
                    .disabled(!agreed)
                    .opacity(agreed ? 1 : 0.45)
                }
                .padding(Space.margin)
                .padding(.top, 24)
            }
        }
        .sheet(item: $shown) { LegalView(document: $0) }
    }
}
