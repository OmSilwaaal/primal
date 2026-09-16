import SwiftUI
import SwiftData

struct CameraView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var usdaService = USDAService.shared
    @StateObject private var aiService = AIService.shared
    
    @State private var selectedMode = "Barcode"
    @State private var servingSize: Double = 100.0
    @State private var currentZoomFactor: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.ncBg.ignoresSafeArea()
            
            if cameraManager.isAuthorized {
                CameraPreviewView(cameraManager: cameraManager)
                    .ignoresSafeArea(edges: .top)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newZoom = currentZoomFactor * value
                                cameraManager.setZoom(factor: newZoom)
                            }
                            .onEnded { value in
                                currentZoomFactor = max(1.0, currentZoomFactor * value)
                                cameraManager.setZoom(factor: currentZoomFactor)
                            }
                    )
                
                // Viewfinder Animation Overlay
                ViewfinderCorners()
                    .padding(.bottom, 50) // center roughly over the actual camera viewport
            } else {
                VStack {
                    Image(systemName: "video.slash")
                        .font(.system(size: 60, weight: .ultraLight))
                        .foregroundColor(.ncSecondary)
                    Text("CAMERA ACCESS DENIED")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.ncSecondary)
                        .padding(.top, 16)
                }
            }
            
            VStack {
                // Top controls
                HStack {
                    Picker("Scan Mode", selection: $selectedMode) {
                        Text("Barcode").tag("Barcode")
                        Text("Food Image").tag("Image")
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    .background(Color.ncSurface.opacity(0.8))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.top, 20)
                
                Spacer()
                
                // Bottom controls based on mode
                if selectedMode == "Barcode" {
                    if let code = cameraManager.scannedBarcode {
                        if usdaService.isLoading {
                            LoadingCard(text: "SEARCHING USDA...")
                        } else if let food = usdaService.results.first {
                            // Barcode Quick Log Card
                            QuickLogCard(
                                title: "FOUND FOOD",
                                foodName: food.description,
                                servingSize: $servingSize
                            ) {
                                let entry = MealEntry(from: food, servingSize: servingSize)
                                modelContext.insert(entry)
                                resetBarcode()
                            }
                        } else {
                            ErrorCard(text: "NO MATCH FOUND") { resetBarcode() }
                        }
                    } else {
                        PromptCard(text: "ALIGN BARCODE WITHIN FRAME")
                    }
                } else {
                    // Image Mode
                    if aiService.isAnalyzing {
                        LoadingCard(text: "ANALYZING IMAGE WITH AI...")
                    } else if let food = aiService.result {
                        // AI Quick Log Card
                        QuickLogCard(
                            title: "AI IDENTIFIED",
                            foodName: food.name,
                            servingSize: $servingSize
                        ) {
                            let entry = MealEntry()
                            entry.foodName = food.name
                            entry.servingSize = servingSize
                            
                            // Scale AI macros by serving size
                            let f = servingSize / food.servingSize
                            entry.calories = food.calories * f
                            entry.protein = food.protein * f
                            entry.carbohydrates = food.carbohydrates * f
                            entry.totalFat = food.totalFat * f
                            
                            modelContext.insert(entry)
                            resetAI()
                        }
                    } else if let err = aiService.errorMessage {
                        ErrorCard(text: err.uppercased()) { resetAI() }
                    } else {
                        Button(action: {
                            cameraManager.capturePhoto()
                        }) {
                            Circle()
                                .stroke(Color.ncPrimary, lineWidth: 3)
                                .frame(width: 70, height: 70)
                                .overlay(
                                    Circle()
                                        .fill(Color.ncPrimary)
                                        .frame(width: 60, height: 60)
                                )
                        }
                        .smoothButton()
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .onAppear {
            cameraManager.checkPermissions()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: cameraManager.scannedBarcode) { _, newValue in
            if let code = newValue, selectedMode == "Barcode" {
                usdaService.search(code)
            }
        }
        .onChange(of: cameraManager.capturedPhotoData) { _, newValue in
            if let data = newValue, selectedMode == "Image" {
                Task {
                    await aiService.analyzeImage(data)
                }
            }
        }
        .onChange(of: selectedMode) { _, _ in
            resetBarcode()
            resetAI()
        }
    }
    
    private func resetBarcode() {
        cameraManager.scannedBarcode = nil
        usdaService.clearResults()
        servingSize = 100.0
    }
    
    private func resetAI() {
        cameraManager.capturedPhotoData = nil
        aiService.clearResult()
        servingSize = 100.0
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
            .stroke(Color.ncPrimary, style: StrokeStyle(lineWidth: thick, lineCap: .square, lineJoin: .miter))
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
            ProgressView().tint(.ncPrimary)
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(.ncSecondary)
        }
        .padding()
        .background(Color.ncSurface.opacity(0.9))
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
            .foregroundColor(.ncPrimary)
            .padding()
            .background(Color.black.opacity(0.5))
            .cornerRadius(8)
            .padding(.bottom, 30)
    }
}

struct ErrorCard: View {
    let text: String
    let onRescan: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(.red)
            Button("Rescan") { onRescan() }
                .font(.system(size: 14))
                .foregroundColor(.ncPrimary)
        }
        .padding()
        .background(Color.ncSurface.opacity(0.9))
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
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(.ncSecondary)
            
            Text(foodName.capitalized)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.ncPrimary)
                .lineLimit(2)
            
            HStack {
                Text("Serving (g):")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.ncSecondary)
                TextField("100", value: $servingSize, format: .number)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 14))
                    .foregroundColor(.ncPrimary)
                    .padding(8)
                    .background(Color.ncSurface2)
                    .cornerRadius(8)
                    .frame(width: 80)
            }
            
            Button(action: onLog) {
                Text("LOG FOOD")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.ncBg)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.ncPrimary)
                    .cornerRadius(8)
            }
            .smoothButton()
        }
        .padding()
        .background(Color.ncSurface.opacity(0.95))
        .cornerRadius(16)
        .padding(.horizontal)
        .padding(.bottom, 30)
    }
}
