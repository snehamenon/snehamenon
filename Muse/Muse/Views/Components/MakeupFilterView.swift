import SwiftUI
import AVFoundation
import Vision
import CoreImage

/// Live "filtered" makeup try-on: softens the skin (a light beauty-filter blur)
/// and paints each makeup zone as feathered, blended color so the result reads
/// as applied makeup rather than shapes sitting on the face. Used on the look
/// selector. Renders through Core Image to a layer; falls back (via
/// `isSupported`) on the simulator.
struct MakeupPreviewView: UIViewRepresentable {
    let zones: [MakeupZone]

    static var isSupported: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    func makeUIView(context: Context) -> MakeupFilterUIView {
        let view = MakeupFilterUIView()
        view.configure()
        view.update(zones: zones)
        view.start()
        return view
    }

    func updateUIView(_ uiView: MakeupFilterUIView, context: Context) {
        uiView.update(zones: zones)
    }

    static func dismantleUIView(_ uiView: MakeupFilterUIView, coordinator: ()) {
        uiView.stop()
    }
}

final class MakeupFilterUIView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    private struct Paint {
        let zone: FaceZone
        let color: UIColor
        let finish: MakeupFinish
    }

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.snehamenon.muse.makeupfilter")
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let renderLayer = CALayer()
    private var paints: [Paint] = []
    private var frameCounter = 0

    /// Zones rendered as rich color (multiply); the rest blend as soft light.
    private static let colorZones: Set<FaceZone> = [.lips, .eyelids, .lashLine, .brows]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(MuseTheme.surface)
        renderLayer.contentsGravity = .resizeAspectFill
        renderLayer.masksToBounds = true
        layer.addSublayer(renderLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderLayer.frame = bounds
    }

    // MARK: Camera

    func configure() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        var device: AVCaptureDevice?
        if let found = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let input = try? AVCaptureDeviceInput(device: found),
           session.canAddInput(input) {
            session.addInput(input)
            device = found
        }
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()

        if let device, let connection = output.connection(with: .video) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            rotationCoordinator = coordinator
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }

    func start() {
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func update(zones: [MakeupZone]) {
        paints = zones.map { Paint(zone: $0.zone, color: UIColor(Color(hex: $0.colorHex)), finish: $0.finish) }
    }

    // MARK: Per-frame render

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCounter += 1
        guard frameCounter % 2 == 0, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let bufW = CGFloat(CVPixelBufferGetWidth(buffer))
        let bufH = CGFloat(CVPixelBufferGetHeight(buffer))
        guard bufW > 0, bufH > 0 else { return }

        let request = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]).perform([request])
        let face = request.results?.first

        let camera = CIImage(cvPixelBuffer: buffer)
        // Work at reduced resolution for performance; the layer scales up.
        let scale = min(1, 720 / bufW)
        let procW = bufW * scale
        let procH = bufH * scale
        let extent = CGRect(x: 0, y: 0, width: procW, height: procH)
        let scaled = camera.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        var base = smoothed(scaled, extent: extent, procW: procW)

        if let face, let landmarks = face.landmarks, !paints.isEmpty {
            base = applyMakeup(on: base, landmarks: landmarks, boundingBox: face.boundingBox, procW: procW, procH: procH, extent: extent)
        }

        let final = base.cropped(to: extent)
        guard let cgImage = ciContext.createCGImage(final, from: extent) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.renderLayer.contents = cgImage
        }
    }

    // MARK: Skin smoothing

    private func smoothed(_ image: CIImage, extent: CGRect, procW: CGFloat) -> CIImage {
        let blurred = image.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(procW * 0.012))
            .cropped(to: extent)
        // Blend the blurred copy over the sharp one at partial strength so skin
        // softens but features keep some definition.
        let faded = blurred.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.55)
        ])
        let softened = faded.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: image
        ])
        return softened.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0.02,
            kCIInputSaturationKey: 1.04,
            kCIInputContrastKey: 1.0
        ])
    }

    // MARK: Makeup compositing

    private func applyMakeup(
        on base: CIImage,
        landmarks: VNFaceLandmarks2D,
        boundingBox: CGRect,
        procW: CGFloat, procH: CGFloat,
        extent: CGRect
    ) -> CIImage {
        // Map an image-normalized (y-up) landmark point to processing-buffer
        // pixels (y-down, matching the Core Graphics context we paint into).
        let map: (CGPoint) -> CGPoint = { CGPoint(x: $0.x * procW, y: (1 - $0.y) * procH) }

        let colorImage = drawGroup(extent: extent, procW: procW, procH: procH, landmarks: landmarks, boundingBox: boundingBox, map: map) { Self.colorZones.contains($0) }
        let diffuseImage = drawGroup(extent: extent, procW: procW, procH: procH, landmarks: landmarks, boundingBox: boundingBox, map: map) { !Self.colorZones.contains($0) }

        var result = base
        if let colorImage {
            result = colorImage.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: result])
        }
        if let diffuseImage {
            result = diffuseImage.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: result])
        }
        return result
    }

    /// Paints the included zones into one feathered color layer.
    private func drawGroup(
        extent: CGRect,
        procW: CGFloat, procH: CGFloat,
        landmarks: VNFaceLandmarks2D,
        boundingBox: CGRect,
        map: (CGPoint) -> CGPoint,
        include: (FaceZone) -> Bool
    ) -> CIImage? {
        let group = paints.filter { include($0.zone) }
        guard !group.isEmpty else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: procW, height: procH), format: format)
        let painted = renderer.image { ctx in
            let cg = ctx.cgContext
            for paint in group {
                guard let path = LiveFacePreviewView.zonePath(
                    zone: paint.zone, landmarks: landmarks, boundingBox: boundingBox, map: map
                ) else { continue }
                cg.addPath(path)
                cg.setFillColor(paint.color.withAlphaComponent(Self.previewAlpha(zone: paint.zone, finish: paint.finish)).cgColor)
                cg.fillPath()
            }
        }
        guard let cgImage = painted.cgImage else { return nil }
        // Feather the edges so the makeup melts into the skin.
        return CIImage(cgImage: cgImage)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(procW * 0.018))
            .cropped(to: extent)
    }

    private static func previewAlpha(zone: FaceZone, finish: MakeupFinish) -> CGFloat {
        var alpha: CGFloat
        switch finish {
        case .matte: alpha = 0.55
        case .satin: alpha = 0.50
        case .dewy: alpha = 0.42
        case .shimmer: alpha = 0.48
        }
        switch zone {
        case .lips: break
        case .eyelids: alpha *= 0.9
        case .lashLine: alpha *= 0.8
        case .brows: alpha *= 0.7
        case .cheeks, .cheekbones: alpha *= 0.8
        case .underEye: alpha *= 0.6
        case .nose, .forehead, .jawline: alpha *= 0.6
        case .fullFace: alpha *= 0.4
        }
        return min(max(alpha, 0.1), 0.7)
    }
}
