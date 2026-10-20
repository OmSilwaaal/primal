import SwiftUI
import SwiftData

struct CameraView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var barcodeService = BarcodeLookupService()
    @StateObject private var aiService = AIService.shared

    @State private var selectedMode = "Barcode"
    @State private var servingSize: Double = 100.0
    @State private var currentZoomFactor: CGFloat = 1.0

    private var sheetShown: Bool {
        if selectedMode == "Barcode" { if case .found = barcodeService.state { return true }; return false }
        return aiService.result != nil && !aiService.isAnalyzing
    }

    var body: some View {
        ZStack {
            Color.ncBg.ignoresSafeArea()

            if cameraManager.isAuthorized {
                CameraPreviewView(cameraManager: cameraManager)
                    .ignoresSafeArea()
                    .gesture(
                        MagnificationGesture()
                            .onChanged { cameraManager.setZoom(factor: currentZoomFactor * $0) }
                            .onEnded { value in
                                currentZoomFactor = max(1.0, currentZoomFactor * value)
                                cameraManager.setZoom(factor: currentZoomFactor)
                            }
                    )

                ViewfinderCorners(showsScanLine: selectedMode == "Barcode")
                    .offset(y: -25)
                    .allowsHitTesting(false)
            } else {
                permissionPrompt
            }

            VStack(spacing: 0) {
                GlassSegmented(options: [("Barcode", "Barcode"), ("Image", "Food image")],
                               selection: $selectedMode, height: 44)
                    .padding(.horizontal, Space.margin)
                    .padding(.top, 4)
                Spacer()
                bottomControls
                    .padding(.horizontal, Space.margin)
                    .padding(.bottom, 110)
            }

            if sheetShown { quickLogSheet }
        }
        .hidesTabBar(sheetShown)
        .onAppear {
            cameraManager.checkPermissions()
            cameraManager.setBarcodeScanning(selectedMode == "Barcode")
        }
        .onDisappear { cameraManager.stopSession() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { cameraManager.checkPermissions() }
        }
        .onChange(of: cameraManager.scannedBarcode) { _, code in
            if let code, selectedMode == "Barcode" { barcodeService.lookup(code) }
        }
        .onChange(of: cameraManager.capturedPhotoData) { _, data in
            if let data, selectedMode == "Image" { Task { await aiService.analyzeImage(data) } }
        }
        .onChange(of: barcodeService.state.foodServing) { _, grams in
            if let grams { servingSize = grams }
        }
        .onChange(of: aiService.result?.servingSize) { _, grams in
            if let grams { servingSize = grams.rounded() }
        }
        .onChange(of: selectedMode) { _, mode in
            resetBarcode()
            resetAI()
            cameraManager.setBarcodeScanning(mode == "Barcode")
        }
    }

    // MARK: - Pieces

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Camera access needed").monoLabel()
            Text("Allow camera access to scan barcodes and photograph meals.")
                .font(.system(size: 15)).foregroundColor(.ncPrimary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.vitalis)
            .padding(.top, 6)
        }
        .padding(.horizontal, Space.margin)
    }

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 14) {
            if selectedMode == "Barcode" {
                switch barcodeService.state {
                case .idle:
                    StatusPill(text: "Align barcode within frame")
                case .loading:
                    StatusPill(text: "Looking up product…")
                case .found:
                    EmptyView()
                case .notFound:
                    ErrorCard(text: "Product not found", actionTitle: "Scan again") { resetBarcode() }
                case .failed(let message):
                    ErrorCard(text: message, actionTitle: "Scan again") { resetBarcode() }
                }
            } else if aiService.isAnalyzing {
                StatusPill(text: "Analyzing image with AI…")
            } else if aiService.result != nil {
                EmptyView()
            } else if let err = aiService.errorMessage {
                ErrorCard(text: err, actionTitle: "Try again") { resetAI() }
            } else if cameraManager.isAuthorized {
                Text("Place the whole plate in frame").font(.mono(12)).tracking(1.2).foregroundColor(.ncSoft)
                    .textCase(.uppercase)
                Button { cameraManager.capturePhoto() } label: {
                    Circle().fill(Color.ncPrimary).padding(5)
                        .overlay(Circle().strokeBorder(Color.ncPrimary, lineWidth: 3))
                        .frame(width: 76, height: 76)
                }
                .buttonStyle(PressScaleStyle(scale: 0.94))
                .accessibilityLabel("Capture")
            }
        }
    }

    @ViewBuilder
    private var quickLogSheet: some View {
        if selectedMode == "Barcode", case .found(let food) = barcodeService.state {
            QuickLogSheet(title: food.subtitle.isEmpty ? "Found food" : "Found food · \(food.subtitle)", foodName: food.description,
                          per100g: .init(food), servingSize: $servingSize,
                          onLog: { log(MealEntry(from: food, servingSize: servingSize)); resetBarcode() },
                          onCancel: { resetBarcode() })
        } else if let food = aiService.result {
            QuickLogSheet(title: "AI identified", foodName: food.name, per100g: .init(food), servingSize: $servingSize,
                          onLog: { log(MealEntry(from: food, servingSize: servingSize)); resetAI() },
                          onCancel: { resetAI() })
        }
    }

    // MARK: - Actions

    private func log(_ entry: MealEntry) {
        MealLogger.log(entry, in: modelContext)
        ToastCenter.shared.show(QuickLogCard.loggedMessage(entry.foodName, grams: entry.servingSize))
    }

    private func resetBarcode() {
        cameraManager.resetBarcode()
        barcodeService.reset()
        servingSize = 100.0
    }

    private func resetAI() {
        cameraManager.capturedPhotoData = nil
        aiService.clearResult()
        servingSize = 100.0
    }
}

private extension BarcodeLookupService.State {
    /// The default portion for a found product, so the card opens on the label serving.
    var foodServing: Double? {
        if case .found(let food) = self { return food.defaultServingGrams }
        return nil
    }
}

// MARK: - Scan pieces

/// 250 pt frame with four 30 pt corners; in barcode mode a Moss scan line runs across the middle.
struct ViewfinderCorners: View {
    var showsScanLine = false

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let w = size.width, h = size.height, l: CGFloat = 30, t: CGFloat = 4, o = t / 2
                var p = Path()
                p.move(to: .init(x: o, y: l)); p.addLine(to: .init(x: o, y: o)); p.addLine(to: .init(x: l, y: o))
                p.move(to: .init(x: w - l, y: o)); p.addLine(to: .init(x: w - o, y: o)); p.addLine(to: .init(x: w - o, y: l))
                p.move(to: .init(x: w - o, y: h - l)); p.addLine(to: .init(x: w - o, y: h - o)); p.addLine(to: .init(x: w - l, y: h - o))
                p.move(to: .init(x: l, y: h - o)); p.addLine(to: .init(x: o, y: h - o)); p.addLine(to: .init(x: o, y: h - l))
                ctx.stroke(p, with: .color(.ncPrimary), style: StrokeStyle(lineWidth: t, lineCap: .butt, lineJoin: .miter))
            }
            if showsScanLine {
                Rectangle().fill(Color.ncMoss).frame(height: 2).padding(.horizontal, 16)
            }
        }
        .frame(width: 250, height: 250)
    }
}

/// Clear-glass status message ("ALIGN BARCODE WITHIN FRAME", "ANALYZING IMAGE WITH AI…").
struct StatusPill: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.mono(12, .semibold)).tracking(1.44)
            .foregroundColor(.ncPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Rectangle().fill(.ultraThinMaterial).overlay(Color(red: 20 / 255, green: 22 / 255, blue: 20 / 255).opacity(0.5)))
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}

struct ErrorCard: View {
    let text: String
    var actionTitle = "Rescan"
    let onRescan: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            StatusPill(text: text)
            Button(actionTitle, action: onRescan).buttonStyle(.glass)
        }
        .frame(maxWidth: 320)
    }
}

struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.98
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Quick log

/// Energy and macros per 100 g, used to preview a serving before it's logged.
struct Per100g {
    var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0

    init(_ food: FoodSearchResult) {
        kcal = food.caloriesPer100g; protein = food.proteinPer100g; carbs = food.carbsPer100g; fat = food.fatPer100g
    }
    init(_ ai: AIFoodResult) {
        let k = ai.servingSize > 0 ? 100 / ai.servingSize : 1
        kcal = ai.calories * k; protein = ai.protein * k; carbs = ai.carbohydrates * k; fat = ai.totalFat * k
    }
}

/// Thick-glass card over a dimmed screen: what was found, energy and macros for the serving, a 25 g stepper.
struct QuickLogSheet: View {
    let title: String
    let foodName: String
    let per100g: Per100g
    @Binding var servingSize: Double
    let onLog: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Dismiss")
            QuickLogCard(title: title, foodName: foodName, per100g: per100g, servingSize: $servingSize,
                         onLog: onLog, onCancel: onCancel)
                .padding(10)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(40)
    }
}

struct QuickLogCard: View {
    let title: String
    let foodName: String
    let per100g: Per100g
    @Binding var servingSize: Double
    let onLog: () -> Void
    let onCancel: () -> Void

    private var k: Double { servingSize / 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(Color.white.opacity(0.3)).frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, -8)

            VStack(alignment: .leading, spacing: 6) {
                Text(title).monoLabel().lineLimit(1)
                Text(foodName.capitalized).font(.system(size: 20, weight: .bold)).foregroundColor(.ncPrimary).lineLimit(2)
            }

            HStack(spacing: 0) {
                cell(Int(per100g.kcal * k).formatted(), "Kcal", first: true)
                cell(NutrientRow.dec(per100g.protein * k), "Protein g")
                cell(NutrientRow.dec(per100g.carbs * k), "Carbs g")
                cell(NutrientRow.dec(per100g.fat * k), "Fat g")
            }
            .overlay(alignment: .top) { Rule() }
            .overlay(alignment: .bottom) { Rule() }

            HStack {
                Text("Serving").monoLabel()
                Spacer()
                HStack(spacing: 4) {
                    step("−", "Less") { servingSize = max(25, servingSize - 25) }
                    Text("\(Int(servingSize)) G").font(.mono(16, .semibold)).foregroundColor(.ncPrimary)
                        .contentTransition(.numericText())
                        .frame(minWidth: 84)
                    step("+", "More") { servingSize = min(2000, servingSize + 25) }
                }
                .padding(4)
                .background(Color.white.opacity(0.08))
                .overlay(Rectangle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .animation(.smooth, value: Int(servingSize))
            }

            Button("Log food") {
                Haptics.success()
                onLog()
            }
            .buttonStyle(.vitalis)

            Button("Cancel", action: onCancel)
                .buttonStyle(TextButtonStyle(height: 40))
                .frame(maxWidth: .infinity)
                .padding(.top, -6)
        }
        .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 18)
        .glass(.thick)
    }

    private func cell(_ value: String, _ label: String, first: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20)).foregroundColor(.ncPrimary).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(label.uppercased()).font(.mono(10)).tracking(1).foregroundColor(.ncSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.leading, first ? 0 : 12)
        .overlay(alignment: .leading) { if !first { Rectangle().fill(Color.ncPrimary).frame(width: 2) } }
    }

    private func step(_ glyph: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(glyph).font(.system(size: 22)).foregroundColor(.ncPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .accessibilityLabel(label)
    }

    /// "LOGGED — RIBEYE STEAK 250 G"
    static func loggedMessage(_ name: String, grams: Double) -> String {
        "Logged — \(name.components(separatedBy: ",").first ?? name) \(Int(grams)) g"
    }
}
