import SwiftUI
import SwiftData

/// The Data tab, Nutrients grouped view, on the app's shared photo backdrop. A title with a Today / Week switch,
/// then bento tiles: what's low (lowest first), the met / on track / low counts, and one card
/// per group (Macros full width; Vitamins and Minerals side by side) with a small vial per nutrient filled to its
/// share of the target. Tapping any tile grows it into a full page with every nutrient's amount, bar and status.
/// Low is under 50% of the target, Met is 90% or more (`NutrientInfo.isDeficient` / `isMet`); status always shows
/// as a word somewhere on screen and to VoiceOver, never colour alone.
struct MicronutrientsView: View {
    enum Range: Hashable { case today, week }
    /// A tile that can grow into its full page.
    enum Panel: Hashable {
        case low, status, group(NutrientGroup)
    }

    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @State private var range: Range = .today
    @State private var open: Panel?
    @Namespace private var hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init() {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: .now)) ?? .now
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start })
    }

    private var goals: NutrientGoals { profiles.first.map(NutrientGoals.from) ?? .default }

    private var rangeMeals: [MealEntry] {
        range == .today ? meals.filter { Calendar.current.isDateInToday($0.date) } : meals
    }

    /// Today's totals, or the daily average over the week's logged days (so days before you started don't drag
    /// it down).
    private var nutrients: [NutrientInfo] {
        let cal = Calendar.current
        let days = range == .today ? 1 : Double(max(1, Set(rangeMeals.map { cal.startOfDay(for: $0.date) }).count))
        return buildNutrientList(from: rangeMeals, goals: goals)
            .map { NutrientInfo(id: $0.id, name: $0.name, unit: $0.unit, icon: $0.icon, group: $0.group,
                                current: $0.current / days, goal: $0.goal) }
    }

    /// One spring for every grow and shrink: quick to start, settles without a bounce.
    private var heroAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.48, dampingFraction: 0.88)
    }

    var body: some View {
        let all = nutrients

        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    header.padding(.top, 8)

                    Group {
                        pair {
                            tile(.low, radius: 30) { LowTile(nutrients: all, range: range) }
                        } right: {
                            tile(.status, radius: 30) { StatusTile(nutrients: all) }
                        }
                        tile(.group(.macros)) { GroupTile(group: .macros, rows: all.filter { $0.group == .macros }, hasMeals: !rangeMeals.isEmpty) }
                        pair {
                            tile(.group(.vitamins)) {
                                GroupTile(group: .vitamins, rows: all.filter { $0.group == .vitamins }, hasMeals: !rangeMeals.isEmpty)
                            }
                        } right: {
                            tile(.group(.minerals)) {
                                GroupTile(group: .minerals, rows: all.filter { $0.group == .minerals }, hasMeals: !rangeMeals.isEmpty)
                            }
                        }
                        Text("Daily targets follow NIH dietary reference intakes for your age and sex."
                             + (range == .week ? " Week shows the daily average over days you logged." : ""))
                            .font(.ui(size: 12)).lineSpacing(3).foregroundColor(Color.ncPrimary.opacity(0.6))
                            .padding(.top, 4).padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
                .animation(.smooth(duration: 0.35), value: range)
            }
            .glassLightFollowsScroll()
            .scrollDisabled(open != nil)
            .accessibilityHidden(open != nil)

            if let open {
                // Dims the page behind the open tile; tap it to close.
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .transition(.opacity)
                    .accessibilityHidden(true)
                DetailPanel(panel: open, nutrients: all, range: range, hero: hero, onClose: close)
                    .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 10)
                    .zIndex(1)
            }
        }
        .hidesTabBar(open != nil)
    }

    private func show(_ panel: Panel) {
        Haptics.tap()
        withAnimation(heroAnimation) { open = panel }
    }

    private func close() {
        withAnimation(heroAnimation) { open = nil }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Data").font(.ui(size: 34, weight: .bold)).tracking(-34 * 0.03)
                .foregroundColor(.ncPrimary)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            RangeSwitch(selection: $range)
        }
    }

    // MARK: Tiles

    /// A tappable glass tile whose surface grows into the full page (shared geometry with `DetailPanel`).
    private func tile<Content: View>(_ panel: Panel, radius: CGFloat = 28,
                                     @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let isOpen = open == panel
        return Button { show(panel) } label: {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(isOpen ? 0 : 1)
                .background {
                    if !isOpen {
                        shape.fill(Color.clear)
                            .glassSheen(in: shape, strength: 0.8)
                            .glass(.tinted, in: shape)
                            .matchedGeometryEffect(id: panel, in: hero)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityHint("Opens details")
    }

    /// Two tiles side by side at equal height; stacked at accessibility text sizes.
    @ViewBuilder private func pair<L: View, R: View>(@ViewBuilder _ left: () -> L,
                                                    @ViewBuilder right: () -> R) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 12) { left(); right() }
        } else {
            HStack(alignment: .top, spacing: 12) { left(); right() }
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Status

private enum Status {
    case met, onTrack, low
    init(_ n: NutrientInfo) { self = n.isMet ? .met : n.isDeficient ? .low : .onTrack }

    var word: String {
        switch self {
        case .met: "Met"
        case .onTrack: "On track"
        case .low: "Low"
        }
    }
    var dot: Color {
        switch self {
        case .met: .ncMoss
        case .onTrack: Color.ncPrimary.opacity(0.85)
        case .low: .ncEmber
        }
    }
}

private extension NutrientInfo {
    /// Share of the target, uncapped (can pass 100%).
    var share: Double { goal > 0 ? current / goal : 0 }

    /// The label under a vial: the macro's name, or the vitamin letter / mineral symbol.
    var short: String {
        switch id {
        case "cal": "Kcal"
        case "pro": "Protein"
        case "carb": "Carbs"
        case "fat": "Fat"
        case "fib": "Fiber"
        case "va": "A"
        case "vc": "C"
        case "vd": "D"
        case "ve": "E"
        case "vk": "K"
        case "b1": "B1"
        case "b2": "B2"
        case "b3": "B3"
        case "b6": "B6"
        case "fol": "B9"
        case "b12": "B12"
        case "ca": "Ca"
        case "fe": "Fe"
        case "mg": "Mg"
        case "ph": "P"
        case "k": "K"
        case "zn": "Zn"
        case "se": "Se"
        case "cu": "Cu"
        case "mn": "Mn"
        default: String(name.prefix(3))
        }
    }
}

/// Status counts for a set of nutrients.
private struct Counts {
    let met: Int, onTrack: Int, low: Int
    init(_ list: [NutrientInfo]) {
        met = list.filter(\.isMet).count
        low = list.filter(\.isDeficient).count
        onTrack = list.count - met - low
    }
    var spoken: String { "\(met) met, \(onTrack) on track, \(low) low" }
}

// MARK: - Top tiles

/// What's low, lowest first: the first one large, the next two by name, then how many more.
private struct LowTile: View {
    let nutrients: [NutrientInfo]
    let range: MicronutrientsView.Range

    var body: some View {
        let low = nutrients.filter(\.isDeficient).sorted { $0.share < $1.share }
        VStack(alignment: .leading, spacing: 8) {
            Text(range == .today ? "Low today" : "Low this week")
                .font(.mono(11)).tracking(0.88).textCase(.uppercase)
                .foregroundColor(Color.ncPrimary.opacity(0.78))
            if let first = low.first {
                Text(first.name).font(.display(22)).foregroundColor(.ncPrimary)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                Text("\(Int((first.share * 100).rounded()))% of target")
                    .font(.mono(11)).tracking(0.88).textCase(.uppercase).foregroundColor(.ncPrimary)
                Spacer(minLength: 0)
                let next = low.dropFirst().prefix(2).map(\.name)
                if !next.isEmpty {
                    Text(next.joined(separator: " · ")
                         + (low.count > 3 ? " +\(low.count - 3)" : ""))
                        .font(.ui(size: 13, weight: .semibold)).foregroundColor(Color.ncPrimary.opacity(0.78))
                        .lineLimit(2).minimumScaleFactor(0.85)
                }
            } else {
                Text("All clear").font(.display(22)).foregroundColor(.ncPrimary)
                Text("Nothing is low").font(.mono(11)).tracking(0.88).textCase(.uppercase).foregroundColor(.ncPrimary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(.vertical, 16).padding(.horizontal, 18)
        .overlay(alignment: .topTrailing) {
            // The app's rune, quietly signing the tile.
            AlgizMark().fill(Color.ncPrimary.opacity(0.22)).frame(width: 11, height: 14)
                .padding(16).accessibilityHidden(true)
        }
        .lineArt(.sprig, placement: .init(alignment: .bottomTrailing, size: 120, offset: CGSize(width: 34, height: 46)),
                 radius: 30)
        .accessibilityElement(children: .combine)
    }
}

/// Met, On track and Low with their counts.
private struct StatusTile: View {
    let nutrients: [NutrientInfo]

    var body: some View {
        let c = Counts(nutrients)
        VStack(spacing: 12) {
            row(.met, c.met)
            row(.onTrack, c.onTrack)
            row(.low, c.low)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 16).padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
    }

    private func row(_ s: Status, _ n: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(s.dot).frame(width: 8, height: 8)
            Text(s.word).font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(.ncPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text("\(n)").font(.display(22)).foregroundColor(.ncPrimary)
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Group tile

/// A group's vials (one per nutrient), its counts and size. Macros gets large vials in a row; Vitamins and
/// Minerals get small ones, five to a row.
private struct GroupTile: View {
    let group: NutrientGroup
    let rows: [NutrientInfo]
    let hasMeals: Bool

    private var large: Bool { group == .macros }

    var body: some View {
        let c = Counts(rows)
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(group.rawValue).font(.mono(13, .semibold)).tracking(1.04).textCase(.uppercase)
                    .foregroundColor(.ncPrimary)
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.ui(size: 15, weight: .medium)).foregroundColor(Color.ncPrimary.opacity(0.78))
                    .accessibilityHidden(true)
            }

            if large {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(rows) { n in
                        VStack(spacing: 6) {
                            Vial(n: n, radius: 14).frame(width: 36, height: 58)
                            Text(n.short).font(.mono(9, .semibold)).tracking(0.5).textCase(.uppercase)
                                .foregroundColor(Color.ncPrimary.opacity(0.78))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(width: 48)
                    }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 14, maximum: 26), spacing: 6), count: 5),
                          alignment: .leading, spacing: 8) {
                    ForEach(rows) { n in
                        VStack(spacing: 4) {
                            Vial(n: n, radius: 9).aspectRatio(22 / 34, contentMode: .fit)
                            Text(n.short).font(.mono(9, .semibold))
                                .foregroundColor(Color.ncPrimary.opacity(0.78))
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Words when they fit; then dots and numbers; then without the item count, so the narrow cards never
            // overflow (VoiceOver always gets the words).
            Group {
                if hasMeals {
                    ViewThatFits(in: .horizontal) {
                        footer { legend(c, words: true) }
                        footer { legend(c, words: false) }
                        legend(c, words: false).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        footer { emptyNote }
                        emptyNote.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.rawValue.capitalized)
        .accessibilityValue("\(rows.count) items, \(c.spoken)")
    }

    private var emptyNote: some View {
        Text("Nothing logged yet").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
            .foregroundColor(Color.ncPrimary.opacity(0.6))
            .lineLimit(1).fixedSize()
    }

    /// A legend (or note) with the item count on the right.
    private func footer<L: View>(@ViewBuilder _ leading: () -> L) -> some View {
        HStack(spacing: 10) {
            leading()
            Spacer(minLength: 4)
            Text("\(rows.count) items").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                .foregroundColor(Color.ncPrimary.opacity(0.78)).fixedSize()
        }
    }

    private func legend(_ c: Counts, words: Bool) -> some View {
        HStack(spacing: words ? 12 : 9) {
            ForEach([(Status.met, c.met), (.onTrack, c.onTrack), (.low, c.low)].filter { $0.1 > 0 }, id: \.0.word) { s, n in
                HStack(spacing: 5) {
                    Circle().fill(s.dot).frame(width: 7, height: 7)
                    Text(words ? "\(n) \(s.word)" : "\(n)")
                        .font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(.ncPrimary)
                        .fixedSize()
                }
            }
        }
    }
}

/// A small glass vial filled from the bottom to the nutrient's share of its target (capped at full): Moss when
/// met, Ember when low, Paper otherwise.
private struct Vial: View {
    let n: NutrientInfo
    let radius: CGFloat

    var body: some View {
        let share = min(max(n.share, 0), 1)
        let status = Status(n)
        let outer = RoundedRectangle(cornerRadius: radius, style: .continuous)
        GeometryReader { geo in
            let inset: CGFloat = 2.5
            let inner = max(0, radius - inset)
            let room = geo.size.height - inset * 2
            ZStack(alignment: .bottom) {
                Color.clear
                if share > 0 {
                    UnevenRoundedRectangle(topLeadingRadius: inner * 0.7, bottomLeadingRadius: inner,
                                           bottomTrailingRadius: inner, topTrailingRadius: inner * 0.7,
                                           style: .continuous)
                        .fill(fill(status))
                        .frame(height: max(inner * 1.2, room * share))
                }
            }
            .padding(inset)
        }
        .background(outer.fill(Color.white.opacity(0.05)))
        .overlay(outer.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .clipShape(outer)
        .animation(.smooth(duration: 0.55), value: share)
        .accessibilityHidden(true)
    }

    private func fill(_ s: Status) -> LinearGradient {
        let colors: [Color] = switch s {
        case .met: [Color(hex: "#A2CD8B"), Color(hex: "#7FA96B")]
        case .low: [Color(hex: "#F37E61"), Color(hex: "#D9644A")]
        case .onTrack: [Color(hex: "#F2F1EC"), Color(hex: "#B9B8B2")]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Full page

/// The open tile: its glass grows from the tile to fill the screen (shared geometry), then the page fades in —
/// the title, the counts in words, a vial strip for a group, and every nutrient's amount, bar and status.
private struct DetailPanel: View {
    let panel: MicronutrientsView.Panel
    let nutrients: [NutrientInfo]
    let range: MicronutrientsView.Range
    let hero: Namespace.ID
    let onClose: () -> Void
    @State private var shown = false

    private var title: String {
        switch panel {
        case .low: "Low"
        case .status: "Status"
        case .group(let g): g.rawValue.capitalized
        }
    }

    private var rows: [NutrientInfo] {
        switch panel {
        case .low: nutrients.filter(\.isDeficient).sorted { $0.share < $1.share }
        case .status: nutrients
        case .group(let g): nutrients.filter { $0.group == g }
        }
    }

    private var sections: [(String?, [NutrientInfo])] {
        switch panel {
        case .status:
            [("Low", nutrients.filter(\.isDeficient)), ("On track", nutrients.filter { !$0.isDeficient && !$0.isMet }),
             ("Met", nutrients.filter(\.isMet))].filter { !$0.1.isEmpty }
        default:
            [(nil, rows)]
        }
    }

    private var art: LineArt {
        switch panel {
        case .low: .sprig
        case .status: .sun
        case .group(.macros): .leaf
        case .group(.vitamins): .sun
        case .group(.minerals): .water
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(Color.clear)
                .glass(.thick, in: shape)
                .matchedGeometryEffect(id: panel, in: hero)

            content
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 14)
                .environment(\.glassNested, true)
        }
        .clipShape(shape)
        .onAppear {
            withAnimation(.easeOut(duration: 0.28).delay(0.14)) { shown = true }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    private var content: some View {
        let c = Counts(rows)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(range == .today ? "Today" : "This week") · \(rows.count) items")
                        .font(.mono(11)).tracking(0.88).textCase(.uppercase)
                        .foregroundColor(Color.ncPrimary.opacity(0.78))
                    Text(title).font(.ui(size: 30, weight: .bold)).tracking(-0.9).foregroundColor(.ncPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                Button(action: onClose) { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                    .buttonStyle(.bentoRound)
                    .accessibilityLabel("Close")
            }

            if case .low = panel, rows.isEmpty {
                Text("Nothing is low \(range == .today ? "today" : "this week").")
                    .font(.ui(size: 15)).foregroundColor(Color.ncPrimary.opacity(0.78))
            } else {
                HStack(spacing: 14) {
                    ForEach([(Status.met, c.met), (.onTrack, c.onTrack), (.low, c.low)], id: \.0.word) { s, n in
                        HStack(spacing: 6) {
                            Circle().fill(s.dot).frame(width: 8, height: 8)
                            Text("\(n) \(s.word)").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                                .foregroundColor(.ncPrimary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                if case .group = panel {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(rows) { n in
                                VStack(spacing: 6) {
                                    Vial(n: n, radius: 13).frame(width: 34, height: 56)
                                    Text("\(Int((n.share * 100).rounded()))%").font(.display(11))
                                        .foregroundColor(.ncPrimary).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(width: 40)
                            }
                        }
                    }
                    .accessibilityHidden(true)
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(sections, id: \.1.first?.id) { heading, list in
                            VStack(alignment: .leading, spacing: 0) {
                                if let heading {
                                    Text(heading).font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                                        .foregroundColor(.ncPrimary)
                                        .padding(.bottom, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .overlay(alignment: .bottom) {
                                            Rectangle().fill(Color.ncPrimary.opacity(0.2)).frame(height: 1)
                                        }
                                        .accessibilityAddTraits(.isHeader)
                                }
                                ForEach(Array(list.enumerated()), id: \.element.id) { i, n in
                                    NutrientListRow(n: n)
                                        .overlay(alignment: .top) {
                                            if i > 0 || heading != nil {
                                                Rectangle().fill(Color.ncPrimary.opacity(0.12)).frame(height: 1)
                                            }
                                        }
                                }
                            }
                        }
                        Text("Targets follow NIH dietary reference intakes for your age and sex.")
                            .font(.ui(size: 12)).foregroundColor(Color.ncPrimary.opacity(0.6))
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(.top, 20).padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .bottomTrailing) {
            Image(art.rawValue).resizable().scaledToFit().frame(width: 240, height: 240)
                .opacity(0.12).offset(x: 50, y: 40)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Controls

/// TODAY | WEEK on a glass capsule; the selected segment is a Paper capsule with dark text that slides across.
private struct RangeSwitch: View {
    @Binding var selection: MicronutrientsView.Range
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            segment(.today, "Today")
            segment(.week, "Week")
        }
        .padding(4)
        .glass(.clear, in: Capsule())
    }

    private func segment(_ value: MicronutrientsView.Range, _ label: String) -> some View {
        let on = selection == value
        return Button {
            guard !on else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { selection = value }
        } label: {
            Text(label).font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                .foregroundColor(on ? .ncOnPrimary : .ncPrimary)
                .padding(.horizontal, 16)
                .frame(minWidth: 64, minHeight: 36)
                .background { if on { Capsule().fill(Color.ncPrimary).matchedGeometryEffect(id: "pill", in: pill) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Row

/// Name, a LOW / MET pill when it applies, amount against target; then the bar and the percent.
private struct NutrientListRow: View {
    let n: NutrientInfo

    private var status: Status { Status(n) }
    private var fill: Color {
        switch status {
        case .met: .ncMoss
        case .low: .ncEmber
        case .onTrack: .ncPrimary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(n.name).font(.ui(size: 14, weight: .semibold)).foregroundColor(.ncPrimary).lineLimit(1)
                switch status {
                case .met: pill("Met", .ncMoss)
                case .low: pill("Low", .ncEmber)
                case .onTrack: EmptyView()
                }
                Spacer(minLength: 8)
                Text("\(NutrientRow.dec(n.current)) / \(NutrientRow.dec(n.goal)) \(n.unit)")
                    .font(.mono(11)).textCase(.uppercase).foregroundColor(.ncPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.ncPrimary.opacity(0.18))
                        Capsule().fill(fill).frame(width: geo.size.width * min(max(n.share, 0), 1))
                    }
                }
                .frame(height: 5)
                Text("\(Int((n.share * 100).rounded()))%").font(.display(13)).foregroundColor(.ncPrimary)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(n.name)
        .accessibilityValue("\(Int((n.share * 100).rounded())) percent, \(NutrientRow.dec(n.current)) of \(NutrientRow.dec(n.goal)) \(n.unit)"
                            + (status == .met ? ", met" : status == .low ? ", low" : ""))
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.mono(9, .semibold)).tracking(0.72).textCase(.uppercase)
            .foregroundColor(.ncOnPrimary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color))
            .fixedSize()
    }
}
