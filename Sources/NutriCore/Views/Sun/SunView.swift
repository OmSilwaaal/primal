import SwiftUI
import SwiftData
import Charts
import CoreLocation

struct SunView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SunSession.start, order: .reverse) private var sessions: [SunSession]
    @Query(sort: \OutcomeLog.date) private var outcomes: [OutcomeLog]
    @StateObject private var sun = SunService.shared
    @StateObject private var location = LocationManager()
    @StateObject private var health = HealthKitManager.shared
    @AppStorage(RawSettings.sunGoalKey) private var goal = 30
    @AppStorage("sunTimerStart") private var timerStart = 0.0
    @AppStorage("sunTimerExposure") private var timerExposure = "partial"

    @State private var daylight: [Date: Double] = [:]
    @State private var manualMinutes = 15
    @State private var exposure = "partial"
    @State private var showManual = false

    private var cal: Calendar { .current }

    private func minutes(on day: Date) -> Double {
        let manual = sessions.filter { cal.isDate($0.start, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
        let hk = daylight[cal.startOfDay(for: day)] ?? 0
        return max(manual, hk)   // the watch and manual logs can overlap, so don't add them
    }
    private var todayMin: Double { minutes(on: Date()) }
    private var last14: [(day: Date, min: Double)] {
        (0..<14).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: Date()))!
            return (d, minutes(on: d))
        }
    }
    private var streak: Int {
        var n = 0
        var d = cal.startOfDay(for: Date())
        if minutes(on: d) < Double(goal) { d = cal.date(byAdding: .day, value: -1, to: d)! }   // today may still be in progress
        while minutes(on: d) >= Double(goal) { n += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
        return n
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ncBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        LeafHeader(title: "Sun", caption: "Light, outdoors, vitamin D", seed: 33).padding(.top, 12)

                        todayCard
                        timerCard
                        conditionsCard
                        weekCard
                        effectCard
                        learnCard
                        Disclaimer(text: "General information, not medical advice. UV exposure raises skin-cancer risk; avoid burning and follow your clinician's guidance on sun exposure.")
                        Spacer().frame(height: 100)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationBarHidden(true)
            .task { await loadAll() }
            .onChange(of: location.location) { _, loc in
                if let loc { Task { await sun.refresh(location: loc) } }
            }
            .sheet(isPresented: $showManual) { manualSheet }
        }
    }

    // MARK: Cards
    private var todayCard: some View {
        RawCard(title: "Time outside today", trailing: streak > 0 ? "\(streak)-day streak" : nil, trailingColor: .ncOrange) {
            VStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.ncSurfaceContHigh, lineWidth: 12)
                    Circle().trim(from: 0, to: min(1, todayMin / Double(max(goal, 1))))
                        .stroke(Color.ncOrange, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90)).animation(.smooth(duration: 0.7), value: todayMin)
                    VStack(spacing: 2) {
                        Text("\(Int(todayMin))").font(.system(size: 44, weight: .bold).monospacedDigit()).foregroundColor(.ncPrimary)
                            .contentTransition(.numericText())
                        Text("of \(goal) min").font(.system(size: 13)).foregroundColor(.ncSecondary)
                    }
                }
                .frame(width: 170, height: 170).frame(maxWidth: .infinity)

                HStack {
                    Stepper("Daily goal: \(goal) min", value: $goal, in: 10...180, step: 5)
                        .font(.system(size: 13)).foregroundColor(.ncSecondary)
                }
                if !health.isAuthorized {
                    Button {
                        Task { try? await health.requestAuthorization(); await loadAll() }
                    } label: { Label("Connect Apple Health for automatic daylight", systemImage: "applewatch") }
                        .buttonStyle(.primalSecondary)
                } else {
                    Text(daylight.isEmpty ? "Daylight from Apple Watch appears here once Health has data." : "Includes Apple Watch time in daylight.")
                        .font(.system(size: 11)).foregroundColor(.ncSecondary)
                }
            }
        }
    }

    private var timerCard: some View {
        RawCard(title: "Outdoor session") {
            VStack(spacing: 12) {
                if timerStart > 0 {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let secs = max(0, ctx.date.timeIntervalSince1970 - timerStart)
                        Text(String(format: "%02d:%02d", Int(secs) / 60, Int(secs) % 60))
                            .font(.system(size: 40, weight: .bold).monospacedDigit()).foregroundColor(.ncPrimary)
                    }
                    Button { stopTimer() } label: { Label("Stop & save", systemImage: "stop.fill") }.buttonStyle(.primal)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach([("minimal", "Face & hands"), ("partial", "Arms & legs"), ("most", "Most skin")], id: \.0) { e in
                            Chip(label: e.1, selected: timerExposure == e.0) { timerExposure = e.0 }
                        }
                    }
                    Button { timerStart = Date().timeIntervalSince1970; Haptics.success() } label: { Label("Start session", systemImage: "play.fill") }
                        .buttonStyle(.primal)
                }
                Button("Add time manually") { showManual = true }
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.ncIndigo)
            }
        }
    }

    private var conditionsCard: some View {
        RawCard(title: "Sun right now") {
            VStack(alignment: .leading, spacing: 12) {
                if location.authorizationStatus == .notDetermined {
                    Text("Allow location to see UV index, sunrise/sunset and when the sun is high enough for vitamin D.")
                        .font(.system(size: 13)).foregroundColor(.ncSecondary)
                    Button("Enable location") { location.requestPermission() }.buttonStyle(.primalSecondary)
                } else if location.location == nil {
                    Text("Finding your location…").font(.system(size: 13)).foregroundColor(.ncSecondary)
                } else {
                    HStack(spacing: 8) {
                        StatTile(title: "UV now", value: sun.uvNow.map { String(format: "%.1f", $0) } ?? "—", color: uvColor(sun.uvNow))
                        StatTile(title: "UV peak today", value: sun.uvMax.map { String(format: "%.1f", $0) } ?? "—", color: uvColor(sun.uvMax))
                        StatTile(title: "Sun height", value: sun.elevationNow.map { "\(Int($0))°" } ?? "—")
                    }
                    if let r = sun.sunrise, let s = sun.sunset {
                        HStack {
                            Label(r.formatted(date: .omitted, time: .shortened), systemImage: "sunrise")
                            Spacer()
                            Label(s.formatted(date: .omitted, time: .shortened), systemImage: "sunset")
                        }
                        .font(.system(size: 13)).foregroundColor(.ncSecondary)
                    }
                    if sun.uvbAllDay {
                        Text("The sun stays above 45° all day here.").font(.system(size: 13)).foregroundColor(.ncPrimary)
                    } else if let w = sun.uvbWindow {
                        VStack(alignment: .leading, spacing: 4) {
                            FieldLabel(text: "Vitamin D window")
                            Text("\(w.lowerBound.formatted(date: .omitted, time: .shortened)) – \(w.upperBound.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 20, weight: .bold)).foregroundColor(.ncOrange)
                            Text("While the sun is above 45° (your shadow is shorter than you), sunlight carries enough UVB for skin to make vitamin D.")
                                .font(.system(size: 12)).foregroundColor(.ncSecondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            FieldLabel(text: "Vitamin D window")
                            Text("None today").font(.system(size: 20, weight: .bold)).foregroundColor(.ncSky)
                            Text("At your latitude the sun doesn't climb above 45° today, so little vitamin D is made from sunlight in this season.")
                                .font(.system(size: 12)).foregroundColor(.ncSecondary)
                        }
                    }
                    if sun.failed { Text("UV data unavailable (offline?). Solar times are calculated on-device.").font(.system(size: 11)).foregroundColor(.ncOrange) }
                    if !sun.hourlyUV.isEmpty {
                        Chart(sun.hourlyUV, id: \.hour) { p in
                            BarMark(x: .value("Hour", p.hour, unit: .hour), y: .value("UV", p.uv)).foregroundStyle(uvColor(p.uv))
                        }
                        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
                        .frame(height: 90)
                    }
                }
            }
        }
    }

    private var weekCard: some View {
        RawCard(title: "Last 14 days", trailing: "avg \(Int(last14.map(\.min).reduce(0, +) / 14)) min") {
            Chart {
                ForEach(last14, id: \.day) { d in
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("Minutes", d.min))
                        .foregroundStyle(d.min >= Double(goal) ? Color.ncOrange : Color.ncSurfaceContHighest)
                }
                RuleMark(y: .value("Goal", goal)).foregroundStyle(Color.ncOrange.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .frame(height: 140)
        }
    }

    /// How outcomes differ between days at or above the goal and days below it.
    private var effectCard: some View {
        let g = Double(goal)
        func avg(_ pick: (OutcomeLog) -> Int, above: Bool) -> (Double, Int)? {
            let vals = outcomes.filter { pick($0) > 0 && (minutes(on: $0.date) >= g) == above }.map { Double(pick($0)) }
            return vals.isEmpty ? nil : (vals.reduce(0, +) / Double(vals.count), vals.count)
        }
        let metrics: [(String, (OutcomeLog) -> Int)] = [("Energy", { $0.energy }), ("Mood", { $0.mood }), ("Sleep quality", { $0.sleep }), ("Focus", { $0.focus })]
        let rows = metrics.compactMap { m -> (String, Double, Double, Int, Int)? in
            guard let a = avg(m.1, above: true), let b = avg(m.1, above: false), a.1 >= 3, b.1 >= 3 else { return nil }
            return (m.0, a.0, b.0, a.1, b.1)
        }
        return RawCard(title: "How it shows up for you") {
            VStack(alignment: .leading, spacing: 10) {
                if rows.isEmpty {
                    Text("Do daily check-ins for a couple of weeks. Once there are 3+ days at or above your goal and 3+ below, your energy, mood, sleep and focus are compared here.")
                        .font(.system(size: 13)).foregroundColor(.ncSecondary)
                } else {
                    ForEach(rows, id: \.0) { r in
                        HStack {
                            Text(r.0).font(.system(size: 13, weight: .medium)).foregroundColor(.ncPrimary)
                            Spacer()
                            Text(String(format: "%.1f vs %.1f", r.1, r.2)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .foregroundColor(r.1 > r.2 + 0.2 ? .ncGreen : r.1 < r.2 - 0.2 ? .ncOrange : .ncSecondary)
                        }
                    }
                    Text("Average on days at/above goal vs below. A pattern in your logs, not proof of cause.").font(.system(size: 11)).foregroundColor(.ncSecondary)
                }
            }
        }
    }

    private var learnCard: some View {
        RawCard(title: "How sunlight affects you") {
            VStack(alignment: .leading, spacing: 14) {
                learn("sun.max", "Vitamin D", "Skin makes vitamin D when UVB reaches it — mainly when the sun is high (above about 45°). Windows, clouds, sunscreen, skin tone and latitude all change how much. Food, supplements and your blood level (25-OH vitamin D) are the other pieces.")
                learn("moon.stars", "Body clock & sleep", "Bright outdoor light in the morning is a strong signal for your circadian rhythm. People commonly report easier sleep timing when they get daylight early in the day and dim light at night.")
                learn("face.smiling", "Mood & energy", "Daylight exposure is associated with mood and alertness in many studies. The check-in lets you see whether that holds for you.")
                learn("exclamationmark.shield", "Skin safety", "Build exposure gradually, avoid burning, and cover up or seek shade once your skin starts to turn pink. UV index 3 or higher calls for sun protection for long stays.")
            }
        }
    }

    private func learn(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundColor(.ncOrange).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.ncPrimary)
                Text(text).font(.system(size: 12)).foregroundColor(.ncSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var manualSheet: some View {
        NavigationStack {
            RawScreen(title: "Add time outside") {
                RawCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper("\(manualMinutes) minutes", value: $manualMinutes, in: 5...240, step: 5).foregroundColor(.ncPrimary)
                        FlowLayout(spacing: 8) {
                            ForEach([("minimal", "Face & hands"), ("partial", "Arms & legs"), ("most", "Most skin")], id: \.0) { e in
                                Chip(label: e.1, selected: exposure == e.0) { exposure = e.0 }
                            }
                        }
                    }
                }
                Button("Save") {
                    save(minutes: Double(manualMinutes), start: Date().addingTimeInterval(-Double(manualMinutes) * 60), exposure: exposure, source: "manual")
                    showManual = false
                }.buttonStyle(.primal)
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { showManual = false } } }
        }
        .presentationDetents([.medium])
    }

    // MARK: Actions
    private func stopTimer() {
        let start = Date(timeIntervalSince1970: timerStart)
        let mins = Date().timeIntervalSince(start) / 60
        timerStart = 0
        guard mins >= 1 else { return }
        save(minutes: mins, start: start, exposure: timerExposure, source: "timer")
    }

    private func save(minutes: Double, start: Date, exposure: String, source: String) {
        let s = SunSession(); s.start = start; s.minutes = minutes; s.exposure = exposure; s.source = source
        s.uvIndex = sun.uvNow ?? 0
        context.insert(s); try? context.save(); Haptics.success()
    }

    private func loadAll() async {
        if location.authorizationStatus == .authorizedWhenInUse || location.authorizationStatus == .authorizedAlways {
            location.startUpdating()
            if let loc = location.location { await sun.refresh(location: loc) }
        }
        daylight = await health.dailyDaylightMinutes(days: 14)
    }

    private func uvColor(_ uv: Double?) -> Color {
        guard let uv else { return .ncPrimary }
        return uv < 3 ? .ncGreen : uv < 6 ? .ncOrange : .ncError
    }
}
