import SwiftUI
import WidgetKit

// Home Screen and Lock Screen widgets. Content first: the system already labels widgets with the app's name, so
// the ᛉ appears only where it carries meaning (the centre of the Lock Screen ring), never as a header.

private let paper = Color(red: 242 / 255, green: 241 / 255, blue: 236 / 255)
private let ink = Color(red: 10 / 255, green: 11 / 255, blue: 10 / 255)
private let mute = Color(red: 157 / 255, green: 161 / 255, blue: 155 / 255)

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, snapshot: context.isPreview ? .placeholder : (WidgetSnapshot.load() ?? .placeholder)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .placeholder)
        // The app reloads timelines when numbers change; also refresh just after midnight to start the new day.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry
    private var s: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: s.progress) {
                EmptyView()
            } currentValueLabel: {
                AlgizMark().fill(.primary).padding(13)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel("\(Int(s.caloriesLeft)) kilocalories left")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    AlgizMark().fill(.primary).frame(width: 10, height: 13)
                    Text("\(Int(s.caloriesLeft).formatted()) kcal left").font(.headline).widgetAccentable()
                }
                Text("\(String(format: "%.1f", s.waterLitres)) L water · \(Int(s.sunMinutes)) min sun").font(.caption)
                Gauge(value: s.progress) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
            }
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle().stroke(paper.opacity(0.15), lineWidth: 8)
                Circle().trim(from: 0, to: s.progress)
                    .stroke(paper, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(Int(s.caloriesLeft).formatted()).font(.system(size: 22, weight: .heavy, design: .default))
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text("KCAL LEFT").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(mute)
                }
                .foregroundColor(paper)
            }
            .frame(width: 92, height: 92)
            .frame(maxWidth: .infinity)
            HStack {
                Label(String(format: "%.1f L", s.waterLitres), systemImage: "drop.fill")
                Spacer()
                Label("\(Int(s.sunMinutes))m", systemImage: "sun.max.fill")
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .labelStyle(CompactLabel())
            .foregroundColor(paper)
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 24 / 255, green: 30 / 255, blue: 22 / 255), ink], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.font(.system(size: 9)); configuration.title }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VitalisToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { ink }
        }
        .configurationDisplayName("Today")
        .description("Calories left, water and sunlight.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct VitalisWidgets: WidgetBundle {
    var body: some Widget { TodayWidget() }
}
