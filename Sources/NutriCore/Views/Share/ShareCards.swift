import SwiftUI

// MARK: - Share cards
//
// Images people choose to share: the session's backdrop photo, big numbers, and the ᛉ VITALIS lockup in the
// corner. Rendered at 1080 × 1350 (4:5), which fits Instagram, Messages and most feeds without cropping.

/// The frame every share card uses: photo, scrim, content, then the lockup at the bottom.
struct ShareCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(Backdrop.current.assetName).resizable().scaledToFill()
                .frame(width: 360, height: 450).clipped()
            LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.15), .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                content
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    AlgizMark().fill(Color.ncPrimary).frame(width: 18, height: 23)
                    Text("VITALIS").font(.ui(size: 15, weight: .regular)).tracking(6).foregroundColor(.ncPrimary)
                }
            }
            .padding(28)
        }
        .frame(width: 360, height: 450)
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.large) // a fixed-size image, independent of the viewer's text size
    }
}

/// One day: calories against the target, macros, water and sunlight.
struct DaySummaryCard: View {
    let day: Date
    let calories: Double
    let goal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let waterLitres: Double
    let sunMinutes: Double

    var body: some View {
        ShareCard {
            Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.mono(11, .semibold)).tracking(1.8).foregroundColor(.ncPrimary.opacity(0.8))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Int(calories).formatted()).font(.display(64)).tracking(-2.4)
                Text("/ \(Int(goal).formatted()) KCAL").font(.mono(12)).foregroundColor(.ncPrimary.opacity(0.7))
            }
            .foregroundColor(.ncPrimary)
            .padding(.top, 14)
            HStack(spacing: 22) {
                stat("PROTEIN", "\(Int(protein))", "G")
                stat("CARBS", "\(Int(carbs))", "G")
                stat("FAT", "\(Int(fat))", "G")
            }
            .padding(.top, 22)
            HStack(spacing: 22) {
                stat("WATER", String(format: "%.1f", waterLitres), "L")
                stat("SUN", "\(Int(sunMinutes))", "MIN")
            }
            .padding(.top, 16)
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.mono(10, .semibold)).tracking(1.4).foregroundColor(.ncPrimary.opacity(0.7))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.display(24)).foregroundColor(.ncPrimary)
                Text(unit).font(.mono(10)).foregroundColor(.ncPrimary.opacity(0.7))
            }
        }
    }
}

/// Where the diet sits over a period, with the raw and animal shares.
struct DietTierCard: View {
    let tier: String
    let days: Int
    let rawPct: Double
    let animalPct: Double

    var body: some View {
        ShareCard {
            Text("MY DIET · LAST \(days) DAYS").font(.mono(11, .semibold)).tracking(1.8).foregroundColor(.ncPrimary.opacity(0.8))
            Text(tier).font(.display(40)).foregroundColor(.ncPrimary)
                .lineLimit(3).minimumScaleFactor(0.6)
                .padding(.top, 14)
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RAW").font(.mono(10, .semibold)).tracking(1.4).foregroundColor(.ncPrimary.opacity(0.7))
                    Text("\(Int(rawPct))%").font(.display(30)).foregroundColor(.ncPrimary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("ANIMAL").font(.mono(10, .semibold)).tracking(1.4).foregroundColor(.ncPrimary.opacity(0.7))
                    Text("\(Int(animalPct))%").font(.display(30)).foregroundColor(.ncPrimary)
                }
            }
            .padding(.top, 24)
        }
    }
}

/// A "Share" button that renders the card to an image and opens the share sheet.
struct ShareCardButton<Card: View>: View {
    var title = "Share"
    @ViewBuilder let card: () -> Card
    @State private var image: UIImage?

    var body: some View {
        Button {
            let renderer = ImageRenderer(content: card())
            renderer.scale = 3
            image = renderer.uiImage
            Haptics.tap()
        } label: {
            Label(title, systemImage: "square.and.arrow.up")
        }
        .buttonStyle(TextButtonStyle(color: .ncPrimary))
        .sheet(isPresented: Binding(get: { image != nil }, set: { if !$0 { image = nil } })) {
            if let image { ShareSheet(items: [image]).presentationDetents([.medium, .large]) }
        }
        .accessibilityHint("Shares an image of these stats")
    }
}
