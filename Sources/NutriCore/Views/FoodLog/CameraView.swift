import SwiftUI
import SwiftData

/// Scan: the camera full screen, round glass controls along the top (close, Meal/Barcode, flash), white viewfinder
/// corners, and a thick glass sheet when food is found. Monochrome.
struct CameraView: View {
    /// Close: leaves Scan for Home.
    var onClose: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var barcodeService = BarcodeLookupService()
    @StateObject private var aiService = AIService.shared

    @State private var selectedMode = "Barcode"
    @State private var servingSize: Double = 100.0
    @State private var currentZoomFactor: CGFloat = 1.0
    /// Bumped when a barcode or photo locks on; flashes the ᛉ in the frame.
    @State private var lockFlash = 0

    private var sheetShown: Bool {
        if selectedMode == "Barcode" { if case .found = barcodeService.state { return true }; return false }
        return aiService.result != nil && !aiService.isAnalyzing
    }

    var body: some View {
        ZStack {
            Mono.base.ignoresSafeArea()

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
                // The tool's signature: a small ᛉ under the frame (outside what the camera reads), and a brief
                // flash of it in the frame when something locks on.
                AlgizMark().fill(Mono.text.opacity(0.55))
                    .frame(width: 12, height: 15)
                    .offset(y: -25 + 125 + 22)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                RuneFlash(trigger: lockFlash)
                    .offset(y: -25)
            } else {
                permissionPrompt
            }

            VStack(spacing: 0) {
                topControls
                    .padding(.horizontal, Bento.margin)
                    .padding(.top, 4)
                Spacer()
                bottomControls
                    .padding(.horizontal, Space.margin)
                    .padding(.bottom, 110)
            }

            if sheetShown { quickLogSheet }
        }
        .hidesTabBar(sheetShown)
        .onChange(of: sheetShown) { _, shown in if shown { lockFlash += 1 } }
        .onAppear {
            cameraManager.checkPermissions()
            cameraManager.setBarcodeScanning(selectedMode == "Barcode")
        }
        .onDisappear { cameraManager.stopSession() }
        .onChange(of: sheetShown) { _, shown in if shown && cameraManager.torchOn { cameraManager.setTorch(false) } }
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

    private var topControls: some View {
        HStack(spacing: 12) {
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.bentoRound)
                .accessibilityLabel("Close")
            BentoSegmented(options: [("Image", "Meal"), ("Barcode", "Barcode")], selection: $selectedMode)
                .frame(maxWidth: 220)
                .frame(maxWidth: .infinity)
            Button { cameraManager.setTorch(!cameraManager.torchOn) } label: {
                Image(systemName: cameraManager.torchOn ? "bolt.fill" : "bolt.slash")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bentoRound)
            .disabled(!cameraManager.isAuthorized || !cameraManager.hasTorch)
            .opacity(cameraManager.isAuthorized && cameraManager.hasTorch ? 1 : 0.4)
            .accessibilityLabel(cameraManager.torchOn ? "Flash on" : "Flash off")
            .accessibilityHint("Turns the light on or off")
        }
    }

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Camera access needed").font(.ui(size: 22, weight: .bold)).foregroundColor(Mono.text)
            Text("Allow camera access to scan barcodes and photograph meals.")
                .font(.bentoBody).foregroundColor(Mono.label)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.bentoPrimary)
            .padding(.top, 6)
        }
        .bentoTile(padding: 20)
        .padding(.horizontal, Bento.margin)
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
                Text("Place the whole plate in frame").font(.ui(size: 13, weight: .medium)).foregroundColor(Mono.label)
                Button { cameraManager.capturePhoto() } label: {
                    Circle().fill(Mono.text).padding(5)
                        .overlay(Circle().strokeBorder(Mono.text, lineWidth: 3))
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
        ToastCenter.shared.show(QuickLogCard.loggedMessage(entry.foodName, grams: entry.servingSize), branded: true)
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

/// 250 pt frame with four white 30 pt corners; in barcode mode a white scan line runs across the middle.
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
                ctx.stroke(p, with: .color(Mono.text), style: StrokeStyle(lineWidth: t, lineCap: .round, lineJoin: .round))
            }
            if showsScanLine {
                Capsule().fill(Mono.text.opacity(0.7)).frame(height: 2).padding(.horizontal, 16)
            }
        }
        .frame(width: 250, height: 250)
    }
}

/// Tinted-glass status message ("Align barcode within frame", "Analyzing image with AI…").
struct StatusPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.ui(size: 14, weight: .semibold))
            .foregroundColor(Mono.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20).padding(.vertical, 13)
            .glass(.tinted, in: Capsule())
    }
}

struct ErrorCard: View {
    let text: String
    var actionTitle = "Rescan"
    let onRescan: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            StatusPill(text: text)
            Button(actionTitle, action: onRescan)
                .buttonStyle(BentoCapsuleButtonStyle(solid: false, height: 44))
                .fixedSize()
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

    private var kcal: Double { per100g.kcal * k }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(Color.white.opacity(0.3)).frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, -6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.ui(size: 13, weight: .medium)).foregroundColor(Mono.label).lineLimit(1)
                Text(foodName.capitalized).font(.ui(size: 22, weight: .bold)).foregroundColor(Mono.text).lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Int(kcal).formatted()).font(.bentoNumber(34)).tracking(Font.bentoTracking(34))
                        .contentTransition(.numericText())
                    Text("kcal").font(.bentoBody).foregroundColor(Mono.label)
                }
                .foregroundColor(Mono.text)
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 10) {
                macro("Protein", per100g.protein * k, kcalPerGram: 4)
                macro("Carbs", per100g.carbs * k, kcalPerGram: 4)
                macro("Fat", per100g.fat * k, kcalPerGram: 9)
            }

            HStack {
                Text("Serving").font(.ui(size: 13, weight: .medium)).foregroundColor(Mono.label)
                Spacer()
                HStack(spacing: 4) {
                    step("minus", "Less") { servingSize = max(25, servingSize - 25) }
                    Text("\(Int(servingSize)) g").font(.ui(size: 16, weight: .semibold)).monospacedDigit()
                        .foregroundColor(Mono.text)
                        .contentTransition(.numericText())
                        .frame(minWidth: 72)
                    step("plus", "More") { servingSize = min(2000, servingSize + 25) }
                }
                .padding(4)
                .glass(.clear, in: Capsule())
                .animation(.smooth, value: Int(servingSize))
            }

            HStack(spacing: 10) {
                Button("Retake", action: onCancel).buttonStyle(.bentoSecondary)
                Button("Add to \(MealSlot.name())") {
                    Haptics.success()
                    onLog()
                }
                .buttonStyle(.bentoPrimary)
            }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 18)
        .glass(.thick, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    /// A small tile: grams, the macro's name, and a bar for its share of this food's energy.
    private func macro(_ name: String, _ grams: Double, kcalPerGram: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.ui(size: 12, weight: .medium)).foregroundColor(Mono.label).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(NutrientRow.dec(grams)).font(.bentoNumber(22)).tracking(Font.bentoTracking(22))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text("g").font(.ui(size: 12)).foregroundColor(Mono.label)
            }
            .foregroundColor(Mono.text)
            BentoBar(value: kcal > 0 ? grams * kcalPerGram / kcal : 0, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glass(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func step(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: symbol).font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
                .frame(width: 40, height: 40)
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

/// A ᛉ that flashes in the viewfinder when a scan locks on: grows in, then fades. Fades only with Reduce Motion.
private struct RuneFlash: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        AlgizMark().fill(Mono.text)
            .frame(width: 76, height: 98)
            .scaleEffect(visible || reduceMotion ? 1 : 0.7)
            .opacity(visible ? 0.85 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: trigger) { _, _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { visible = true }
                withAnimation(.easeOut(duration: 0.4).delay(0.35)) { visible = false }
            }
    }
}
