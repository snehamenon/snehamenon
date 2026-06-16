import SwiftUI
import AVFoundation
import Vision

/// The headline tutorial feature: shows the user's live (mirrored) face and
/// paints a translucent, color-tinted overlay on the exact zone the current
/// step applies to — gold on the eyelids for golden eyeshadow, etc. Tracks the
/// face per-frame with Vision landmarks so the overlay stays glued as they move.
///
/// Works on any device with a front camera. On the simulator (no camera),
/// `isSupported` is false and the caller falls back to the stylized diagram.
struct LiveTutorialFaceView: UIViewRepresentable {
    let zone: FaceZone
    let tint: Color

    static var isSupported: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    func makeUIView(context: Context) -> LiveFacePreviewView {
        let view = LiveFacePreviewView()
        view.configure()
        view.update(zone: zone, tint: UIColor(tint))
        view.start()
        return view
    }

    func updateUIView(_ uiView: LiveFacePreviewView, context: Context) {
        uiView.update(zone: zone, tint: UIColor(tint))
    }

    static func dismantleUIView(_ uiView: LiveFacePreviewView, coordinator: ()) {
        uiView.stop()
    }
}

/// Owns the front-camera session, the preview layer, and the overlay shape
/// layer. Per frame: detect face landmarks, build the zone path in view space,
/// and redraw the overlay.
final class LiveFacePreviewView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.snehamenon.muse.tutorialcam")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private let overlayLayer = CAShapeLayer()

    private var zone: FaceZone = .fullFace
    private var tint: UIColor = .systemOrange
    private var frameCounter = 0

    // MARK: Lifecycle

    func configure() {
        backgroundColor = UIColor(MuseTheme.surface)

        session.beginConfiguration()
        session.sessionPreset = .high

        var captureDevice: AVCaptureDevice?
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            captureDevice = device
        }
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        layer.addSublayer(preview)
        previewLayer = preview

        // Let iOS compute the correct upright angle for this device's front camera,
        // and apply the SAME angle to both the preview and the analyzed buffer (so
        // the overlay lines up with what's on screen). Mirror both for a selfie feel.
        if let device = captureDevice {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
            rotationCoordinator = coordinator
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            for connection in [preview.connection, output.connection(with: .video)].compactMap({ $0 }) {
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
        }

        overlayLayer.fillColor = UIColor.systemOrange.withAlphaComponent(0.3).cgColor
        overlayLayer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.9).cgColor
        overlayLayer.lineWidth = 2
        overlayLayer.lineJoin = .round
        layer.addSublayer(overlayLayer)
    }

    func start() {
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func update(zone: FaceZone, tint: UIColor) {
        self.zone = zone
        self.tint = tint
        overlayLayer.fillColor = tint.withAlphaComponent(0.32).cgColor
        overlayLayer.strokeColor = tint.withAlphaComponent(0.95).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        overlayLayer.frame = bounds
    }

    // MARK: Per-frame detection

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCounter += 1
        guard frameCounter % 2 == 0,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let bufW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])

        guard let face = request.results?.first, let landmarks = face.landmarks else {
            DispatchQueue.main.async { [weak self] in self?.overlayLayer.path = nil }
            return
        }

        let currentZone = zone
        // Snapshot the bounds on main isn't needed here; bounds is read-only and
        // stable enough between layout passes for mapping.
        let viewBounds = bounds
        let path = Self.overlayPath(
            zone: currentZone,
            landmarks: landmarks,
            boundingBox: face.boundingBox,
            bufW: bufW, bufH: bufH,
            viewBounds: viewBounds
        )
        DispatchQueue.main.async { [weak self] in
            self?.overlayLayer.path = path
        }
    }

    // MARK: Coordinate mapping

    /// Maps a Vision-normalized point (origin bottom-left, y-up, normalized to
    /// the buffer) to view space, matching the preview's resize-aspect-fill.
    /// If the overlay ever appears mirrored, flipping `nx` here is the one-line fix.
    private static func mapPoint(
        _ p: CGPoint, bufW: CGFloat, bufH: CGFloat, viewBounds: CGRect
    ) -> CGPoint {
        let nx = p.x
        let ny = 1 - p.y // Vision y-up → UIKit y-down
        let viewW = viewBounds.width
        let viewH = viewBounds.height
        guard bufW > 0, bufH > 0, viewW > 0, viewH > 0 else { return .zero }
        let scale = max(viewW / bufW, viewH / bufH)
        let dispW = bufW * scale
        let dispH = bufH * scale
        let offsetX = (dispW - viewW) / 2
        let offsetY = (dispH - viewH) / 2
        return CGPoint(x: nx * dispW - offsetX, y: ny * dispH - offsetY)
    }

    // MARK: Zone geometry

    private static func overlayPath(
        zone: FaceZone,
        landmarks: VNFaceLandmarks2D,
        boundingBox: CGRect,
        bufW: CGFloat, bufH: CGFloat,
        viewBounds: CGRect
    ) -> CGPath? {
        // Convert a landmark region to view-space points.
        func pts(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            guard let region else { return [] }
            return region.normalizedPoints.map { np in
                let imageX = boundingBox.minX + CGFloat(np.x) * boundingBox.width
                let imageY = boundingBox.minY + CGFloat(np.y) * boundingBox.height
                return mapPoint(CGPoint(x: imageX, y: imageY), bufW: bufW, bufH: bufH, viewBounds: viewBounds)
            }
        }
        func bbox(_ points: [CGPoint]) -> CGRect? {
            guard !points.isEmpty else { return nil }
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }

        let leftEye = pts(landmarks.leftEye)
        let rightEye = pts(landmarks.rightEye)
        let leftBrow = pts(landmarks.leftEyebrow)
        let rightBrow = pts(landmarks.rightEyebrow)
        let nose = pts(landmarks.nose)
        let outerLips = pts(landmarks.outerLips)
        let contour = pts(landmarks.faceContour)

        let path = CGMutablePath()

        func addEllipse(center: CGPoint, width: CGFloat, height: CGFloat) {
            guard width > 1, height > 1 else { return }
            path.addEllipse(in: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
        }
        func addPolygon(_ points: [CGPoint]) {
            guard points.count > 2 else { return }
            path.addLines(between: points)
            path.closeSubpath()
        }

        switch zone {
        case .lips:
            addPolygon(outerLips)

        case .brows:
            for brow in [leftBrow, rightBrow] {
                if let b = bbox(brow) {
                    addEllipse(center: CGPoint(x: b.midX, y: b.midY), width: b.width * 1.15, height: max(b.height, 6) * 1.8)
                }
            }

        case .eyelids:
            for (eye, brow) in [(leftEye, leftBrow), (rightEye, rightBrow)] {
                guard let e = bbox(eye) else { continue }
                let browBottom = bbox(brow)?.maxY ?? (e.minY - e.height * 1.4)
                let top = min(browBottom, e.midY - 2)
                let height = max(e.midY - top, e.height * 1.1)
                addEllipse(center: CGPoint(x: e.midX, y: top + height / 2), width: e.width * 1.3, height: height)
            }

        case .lashLine:
            for eye in [leftEye, rightEye] {
                if let e = bbox(eye) {
                    addEllipse(center: CGPoint(x: e.midX, y: e.minY + e.height * 0.35), width: e.width * 1.1, height: max(e.height * 0.5, 5))
                }
            }

        case .underEye:
            for eye in [leftEye, rightEye] {
                if let e = bbox(eye) {
                    addEllipse(center: CGPoint(x: e.midX, y: e.maxY + e.height * 0.7), width: e.width * 1.15, height: max(e.height * 1.2, 8))
                }
            }

        case .cheeks, .cheekbones:
            guard let l = bbox(leftEye), let r = bbox(rightEye) else { return path.isEmpty ? nil : path }
            let eyeSpan = abs(l.midX - r.midX)
            let radius = max(eyeSpan * 0.32, 18)
            let noseMidY = bbox(nose)?.midY ?? ((l.maxY + r.maxY) / 2 + radius)
            for e in [l, r] {
                if zone == .cheeks {
                    addEllipse(center: CGPoint(x: e.midX, y: max(e.maxY + radius * 0.6, noseMidY)), width: radius * 2, height: radius * 1.7)
                } else {
                    // Cheekbones sit higher and more lateral than the apples.
                    let lateral = e.midX + (e.midX > (l.midX + r.midX) / 2 ? radius * 0.5 : -radius * 0.5)
                    addEllipse(center: CGPoint(x: lateral, y: e.maxY + radius * 0.2), width: radius * 1.9, height: radius * 1.3)
                }
            }

        case .nose:
            if let n = bbox(nose) {
                let top = min(bbox(leftEye)?.maxY ?? n.minY, bbox(rightEye)?.maxY ?? n.minY)
                let bottom = n.maxY
                addEllipse(center: CGPoint(x: n.midX, y: (top + bottom) / 2), width: max(n.width * 0.85, 14), height: max(bottom - top, 20))
            }

        case .forehead:
            let brows = leftBrow + rightBrow
            if let b = bbox(brows) {
                let height = max(b.height * 2.4, 40)
                addEllipse(center: CGPoint(x: b.midX, y: b.minY - height * 0.5), width: b.width * 1.1, height: height)
            }

        case .jawline:
            if let c = bbox(contour), !contour.isEmpty {
                // Highlight the lower face outline: a few markers along the jaw.
                let lower = contour.filter { $0.y > c.midY }
                let markers = [lower.first, lower.min(by: { $0.y < $1.y }).flatMap { _ in lower.max(by: { $0.y < $1.y }) }, lower.last].compactMap { $0 }
                for point in markers {
                    addEllipse(center: point, width: c.width * 0.18, height: c.width * 0.18)
                }
            }

        case .fullFace:
            if contour.count > 2 {
                addPolygon(contour)
            } else if let c = bbox(leftEye + rightEye + outerLips) {
                addEllipse(center: CGPoint(x: c.midX, y: c.midY), width: c.width * 1.8, height: c.height * 2.4)
            }
        }

        return path.isEmpty ? nil : path
    }
}
