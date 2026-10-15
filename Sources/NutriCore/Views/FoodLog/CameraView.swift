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
    @State private var loggedToast: String?

    /// Clears the floating tab bar.
    private let controlsBottomPadding: CGFloat = 100

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraManager.isAuthorized {
                CameraPreviewView(cameraManager: cameraManager)
                    .ignoresSafeArea(edges: .top)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { cameraManager.setZoom(factor: currentZoomFactor * $0) }
                            .onEnded { value in
                                currentZoomFactor = max(1.0, currentZoomFactor * value)
                                cameraManager.setZoom(factor: currentZoomFactor)
                            }
                    )

                ViewfinderCorners()
                    .padding(.bottom, 50)
                    .allowsHitTesting(false)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 60, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.6))
                    Text("CAMERA ACCESS NEEDED")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white)
                    Text("Allow camera access to scan barcodes and food.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(10)
                    .padding(.top, 8)
                }
            }

            VStack {
                header
                Spacer()
                bottomControls
            }

            if let toast = loggedToast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(20)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 110)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
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

    private var header: some View {
        HStack {
            Text("SCANNER")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 6) {
                ForEach(["Barcode", "Image"], id: \.self) { mode in
                    Button(mode.uppercased()) { selectedMode = mode }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(selectedMode == mode ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedMode == mode ? Color.white : Color.white.opacity(0.18))
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 76)
    }

    @ViewBuilder
    private var bottomControls: some View {
        Group {
            if selectedMode == "Barcode" {
                switch barcodeService.state {
                case .idle:
                    PromptCard(text: "ALIGN BARCODE WITHIN FRAME")
                case .loading:
                    LoadingCard(text: "LOOKING UP PRODUCT...")
                case .found(let food):
                    QuickLogCard(title: food.subtitle, foodName: food.description, servingSize: $servingSize) {
                        log(MealEntry(from: food, servingSize: servingSize))
                        resetBarcode()
                    }
                case .notFound:
                    ErrorCard(text: "PRODUCT NOT FOUND", actionTitle: "Scan again") { resetBarcode() }
                case .failed(let message):
                    ErrorCard(text: message.uppercased(), actionTitle: "Scan again") { resetBarcode() }
                }
            } else if aiService.isAnalyzing {
                LoadingCard(text: "ANALYZING PHOTO...")
            } else if let food = aiService.result {
                QuickLogCard(title: "AI ESTIMATE", foodName: food.name, servingSize: $servingSize) {
                    log(MealEntry(from: food, servingSize: servingSize))
                    resetAI()
                }
            } else if let err = aiService.errorMessage {
                ErrorCard(text: err, actionTitle: "Try again") { resetAI() }
            } else {
                Button { cameraManager.capturePhoto() } label: {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 74, height: 74)
                        .overlay(Circle().fill(Color.white).frame(width: 60, height: 60))
                }
                .smoothButton()
                .padding(.bottom, 30)
            }
        }
        .padding(.bottom, controlsBottomPadding - 24)
    }

    // MARK: - Actions

    private func log(_ entry: MealEntry) {
        MealLogger.log(entry, in: modelContext)
        withAnimation { loggedToast = "Logged \(Int(entry.calories)) kcal" }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { loggedToast = nil }
        }
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

// MARK: - Reusable UI Components

struct ViewfinderCorners: View {
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let length: CGFloat = 30
            let thick: CGFloat = 4
            
            Path { path in
                // Top Left
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))
                
                // Top Right
                path.move(to: CGPoint(x: w - length, y: 0))
                path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: length))
                
                // Bottom Right
                path.move(to: CGPoint(x: w, y: h - length))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w - length, y: h))
                
                // Bottom Left
                path.move(to: CGPoint(x: length, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: 0, y: h - length))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: thick, lineCap: .square, lineJoin: .miter))
        }
        .frame(width: 250, height: 250)
        .scaleEffect(isAnimating ? 1.05 : 0.95)
        .opacity(isAnimating ? 1.0 : 0.3)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

struct LoadingCard: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            ProgressView().tint(.white)
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.75))
        .cornerRadius(12)
        .padding(.bottom, 30)
    }
}

struct PromptCard: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .tracking(1)
            .foregroundColor(.white)
            .padding()
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)
            .padding(.bottom, 30)
    }
}

struct ErrorCard: View {
    let text: String
    var actionTitle = "Rescan"
    let onRescan: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
            Button(actionTitle) { onRescan() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(Color.white)
                .cornerRadius(10)
        }
        .padding()
        .frame(maxWidth: 300)
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .padding(.bottom, 30)
    }
}

struct QuickLogCard: View {
    let title: String
    let foodName: String
    @Binding var servingSize: Double
    let onLog: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.2))
                .frame(width: 40, height: 4)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 14) {
                // Title block
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.6))
                    Text(foodName.uppercased())
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                // Serving size control
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PORTION TELEMETRY")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        HStack(spacing: 6) {
                            Text(String(format: "%.0fg", servingSize))
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                            Button {
                                servingSize = max(5, servingSize - 25)
                            } label: {
                                Text("−")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ncBorder, lineWidth: 1))
                            }
                            Button {
                                servingSize = min(1000, servingSize + 25)
                            } label: {
                                Text("+")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ncBorder, lineWidth: 1))
                            }
                        }
                    }
                    Slider(value: $servingSize, in: 5...1000, step: 5)
                        .tint(.white)
                    HStack {
                        ForEach(["5g", "250g", "500g", "1000g"], id: \.self) { label in
                            Text(label)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                            if label != "1000g" { Spacer() }
                        }
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.4))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))

                // Log CTA
                Button(action: {
                    let isHapticsEnabled = UserDefaults.standard.object(forKey: "isHapticsEnabled") as? Bool ?? true
                    if isHapticsEnabled {
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                    onLog()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 15, weight: .bold))
                        Text("LOG ENTRY")
                            .font(.system(size: 13, weight: .black))
                            .tracking(2)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white)
                    .cornerRadius(14)
                }
                .smoothButton()
            }
            .padding(16)
        }
        .background(
            ZStack {
                Color(red: 0.063, green: 0.063, blue: 0.063)
            }
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
        )
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.08), lineWidth: 1),
            alignment: .top
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
    }
}

