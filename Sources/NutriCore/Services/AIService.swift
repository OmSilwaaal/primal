import Foundation
import UIKit

/// Photo meal recognition: the photo goes to the `ai` Edge Function (Claude Haiku 5.5, rate limited on the server);
/// each food it names is then matched to USDA on the device for its full nutrient profile (see `PhotoMeal`).
@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()
    private init() {}

    @Published var isAnalyzing = false
    /// The photo's foods, matched to USDA.
    @Published var result: PhotoMeal.Result?
    @Published var errorMessage: String?
    /// The server's latest word on photo scans left today (nil until the first scan of the session).
    @Published private(set) var scansLeftToday: Int?
    /// Set when the refusal is a limit Pro would lift, so the scan screen can offer Vitalis Pro.
    @Published private(set) var limitReached = false

    func analyzeImage(_ imageData: Data) async {
        isAnalyzing = true
        errorMessage = nil
        limitReached = false
        result = nil
        defer { isAnalyzing = false }

        do {
            let jpeg = try await Task.detached(priority: .userInitiated) { try Self.prepare(imageData) }.value
            let reply = try await VitalisAI.scan(jpeg: jpeg)
            scansLeftToday = reply.remaining
            result = await PhotoMeal.resolve(reply.items)
        } catch let failure as VitalisAI.Failure {
            errorMessage = failure.message
            if failure.code == "quota" { scansLeftToday = 0; limitReached = !SubscriptionManager.shared.isSubscribed }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearResult() {
        result = nil
        errorMessage = nil
        limitReached = false
    }

    /// Downscale + recompress: full-resolution photos are several MB and slow the request for no accuracy gain.
    /// The server only accepts JPEGs up to 1.2 MB, so this also keeps every photo inside that.
    nonisolated static func prepare(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else { throw PrepareError.badImage }
        let maxSide: CGFloat = 1024
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.7, 0.55, 0.4] {
            if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count <= 1_100_000 { return jpeg }
        }
        throw PrepareError.badImage
    }

    enum PrepareError: LocalizedError {
        case badImage
        var errorDescription: String? { "Couldn't read the photo." }
    }
}
