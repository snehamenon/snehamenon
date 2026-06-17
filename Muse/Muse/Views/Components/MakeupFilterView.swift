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
    /// Fine detail (lashes) — painted with a much smaller feather so the
    /// individual strokes stay crisp instead of smearing into a blob.
    private static let fineZones: Set<FaceZone> = [.lashes]

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
        session.sessionPreset = .hd1920x1080

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
        let extent = camera.extent

        // Smoothing and makeup are low-frequency, so we compute them at reduced
        // resolution and composite onto the FULL-res camera image — the picture
        // stays sharp while the heavy work stays cheap.
        var base = smoothed(camera, extent: extent)
        if let face, let landmarks = face.landmarks, !paints.isEmpty {
            base = applyMakeup(on: base, landmarks: landmarks, boundingBox: face.boundingBox, bufW: bufW, bufH: bufH, extent: extent)
        }

        let final = base.cropped(to: extent)
        guard let cgImage = ciContext.createCGImage(final, from: extent) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.renderLayer.contents = cgImage
        }
    }

    // MARK: Skin smoothing

    private func smoothed(_ image: CIImage, extent: CGRect) -> CIImage {
        // Compute the blur at ~1/3 resolution (it's low-frequency, so this looks
        // identical and is ~9x cheaper), then blend it back lightly so skin is
        // softened — not blurred — and detail is preserved.
        let blurScale: CGFloat = 0.3
        let blurredUp = image
            .transformed(by: CGAffineTransform(scaleX: blurScale, y: blurScale))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 3.0)
            .transformed(by: CGAffineTransform(scaleX: 1 / blurScale, y: 1 / blurScale))
            .cropped(to: extent)
        let faded = blurredUp.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.2)
        ])
        let softened = faded.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: image
        ])
        return softened.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0.015,
            kCIInputSaturationKey: 1.03,
            kCIInputContrastKey: 1.0
        ])
    }

    // MARK: Makeup compositing

    private func applyMakeup(
        on base: CIImage,
        landmarks: VNFaceLandmarks2D,
        boundingBox: CGRect,
        bufW: CGFloat, bufH: CGFloat,
        extent: CGRect
    ) -> CIImage {
        // Rasterize the makeup masks at half resolution (they're feathered, so
        // it's invisible) and upscale — cheap, and keeps the camera sharp.
        let maskScale: CGFloat = 0.5
        let maskW = bufW * maskScale
        let maskH = bufH * maskScale
        // Map an image-normalized (y-up) landmark point to mask pixels (y-down,
        // matching the Core Graphics context).
        let map: (CGPoint) -> CGPoint = { CGPoint(x: $0.x * maskW, y: (1 - $0.y) * maskH) }

        let colorImage = drawGroup(maskW: maskW, maskH: maskH, maskScale: maskScale, extent: extent, landmarks: landmarks, boundingBox: boundingBox, map: map, featherFactor: 0.025) { Self.colorZones.contains($0) }
        let diffuseImage = drawGroup(maskW: maskW, maskH: maskH, maskScale: maskScale, extent: extent, landmarks: landmarks, boundingBox: boundingBox, map: map, featherFactor: 0.025) { !Self.colorZones.contains($0) && !Self.fineZones.contains($0) }
        let lashImage = drawGroup(maskW: maskW, maskH: maskH, maskScale: maskScale, extent: extent, landmarks: landmarks, boundingBox: boundingBox, map: map, featherFactor: 0.006) { Self.fineZones.contains($0) }

        var result = base
        if let colorImage {
            result = colorImage.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: result])
        }
        if let diffuseImage {
            result = diffuseImage.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: result])
        }
        if let lashImage {
            result = lashImage.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: result])
        }
        return result
    }

    /// Paints the included zones into one feathered color layer at mask
    /// resolution, then upscales it to the full image extent.
    private func drawGroup(
        maskW: CGFloat, maskH: CGFloat, maskScale: CGFloat,
        extent: CGRect,
        landmarks: VNFaceLandmarks2D,
        boundingBox: CGRect,
        map: (CGPoint) -> CGPoint,
        featherFactor: CGFloat,
        include: (FaceZone) -> Bool
    ) -> CIImage? {
        let group = paints.filter { include($0.zone) }
        guard !group.isEmpty else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: maskW, height: maskH), format: format)
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
        // Feather the edges, then upscale to full resolution.
        return CIImage(cgImage: cgImage)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(maskW * featherFactor))
            .transformed(by: CGAffineTransform(scaleX: 1 / maskScale, y: 1 / maskScale))
            .cropped(to: extent)
    }

    private static func previewAlpha(zone: FaceZone, finish: MakeupFinish) -> CGFloat {
        var alpha: CGFloat
        switch finish {
        case .matte: alpha = 0.80
        case .satin: alpha = 0.72
        case .dewy: alpha = 0.60
        case .shimmer: alpha = 0.68
        }
        switch zone {
        case .lips: break               // full strength — lips read most pigmented
        case .eyelids: alpha *= 0.95
        case .lashLine: alpha *= 0.85
        case .lashes: break               // mascara reads dark and full
        case .brows: alpha *= 0.7
        case .cheeks, .cheekbones: alpha *= 0.7   // blush stays softer than color zones
        case .underEye: alpha *= 0.6
        case .nose, .forehead, .jawline: alpha *= 0.6
        case .fullFace: alpha *= 0.4
        }
        return min(max(alpha, 0.1), 0.88)
    }
}
