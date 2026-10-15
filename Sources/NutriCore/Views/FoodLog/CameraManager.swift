import AVFoundation
import Combine
import CoreImage

class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var isAuthorized = false
    @Published var scannedBarcode: String? = nil
    @Published var capturedPhotoData: Data? = nil
    
    private let output = AVCaptureMetadataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    private var isConfigured = false
    private var ignoreBarcodesUntil = Date.distantPast
    private var videoDevice: AVCaptureDevice?
    
    /// Product barcodes only (UPC-A is reported as EAN-13). QR/PDF417 would trigger pointless lookups.
    private static let barcodeTypes: [AVMetadataObject.ObjectType] = [.ean8, .ean13, .upce]

    // The session is started from CameraView.onAppear, not here, so the camera (and its permission
    // prompt) doesn't spin up at launch while the Scan tab is still off screen.
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupSession()
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }
    
    private func setupSession() {
        sessionQueue.async {
            if self.isConfigured {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                return
            }
            
            self.session.beginConfiguration()
            
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.session.canAddInput(videoDeviceInput) else {
                self.session.commitConfiguration()
                return
            }
            
            self.videoDevice = videoDevice
            self.session.addInput(videoDeviceInput)
            
            // Barcode setup
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
                self.output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                self.output.metadataObjectTypes = Self.barcodeTypes
            }
            
            // Photo setup
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            
            self.session.commitConfiguration()
            self.isConfigured = true
            self.session.startRunning()
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    /// Only decode barcodes while the barcode mode is active.
    func setBarcodeScanning(_ enabled: Bool) {
        sessionQueue.async {
            self.output.metadataObjectTypes = enabled ? Self.barcodeTypes.filter { self.output.availableMetadataObjectTypes.contains($0) } : []
        }
    }

    /// Clears the current barcode and ignores re-detections for a moment so a logged item isn't instantly re-scanned.
    func resetBarcode() {
        scannedBarcode = nil
        ignoreBarcodesUntil = Date().addingTimeInterval(2)
    }
    
    func setZoom(factor: CGFloat) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
            device.unlockForConfiguration()
        } catch {
            print("Failed to set zoom: \(error.localizedDescription)")
        }
    }
}

extension CameraManager: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue else { return }
            
            // Avoid repeatedly scanning the same barcode instantly
            if scannedBarcode != stringValue, Date() >= ignoreBarcodesUntil {
                scannedBarcode = stringValue
            }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let imageData = photo.fileDataRepresentation() else { return }
        DispatchQueue.main.async {
            self.capturedPhotoData = imageData
        }
    }
}
