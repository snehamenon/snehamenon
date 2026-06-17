import SwiftUI
import AVFoundation
import Vision

/// One painted region of a look: which face zone, what color, what finish.
struct MakeupZone: Equatable {
    let zone: FaceZone
    let colorHex: String
    let finish: MakeupFinish
}

/// How the overlay renders:
/// - `.coach` — one zone, bright fill + outline that clearly points to WHERE
///   (used during the step-by-step tutorial).
/// - `.preview` — a whole look painted as soft, blended makeup so the user can
///   see themselves in it and choose (used on the look-selection screen).
enum FaceOverlayStyle {
    case coach
    case preview
}

/// Live, mirrored front-camera view that tracks the face with Vision landmarks
/// and paints makeup zones on it. Works on any device with a front camera;
/// `isSupported` is false on the simulator so callers can fall back.
struct LiveTutorialFaceView: UIViewRepresentable {
    let zones: [MakeupZone]
    let style: FaceOverlayStyle

    static var isSupported: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    func makeUIView(context: Context) -> LiveFacePreviewView {
        let view = LiveFacePreviewView()
        view.configure()
        view.update(zones: zones, style: style)
        view.start()
        return view
    }

    func updateUIView(_ uiView: LiveFacePreviewView, context: Context) {
        uiView.update(zones: zones, style: style)
    }

    static func dismantleUIView(_ uiView: LiveFacePreviewView, coordinator: ()) {
        uiView.stop()
    }
}

final class LiveFacePreviewView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    private struct ZoneDescriptor {
        let zone: FaceZone
        let color: UIColor
        let finish: MakeupFinish
    }

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.snehamenon.muse.tutorialcam")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    private var makeupLayers: [CAShapeLayer] = []
    private var descriptors: [ZoneDescriptor] = []
    private var style: FaceOverlayStyle = .coach
    private var frameCounter = 0

    // MARK: Camera setup

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

        // Let iOS pick the correct upright angle for this device's front camera,
        // applied identically to preview and analyzed buffer; mirror both.
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

    // MARK: Zone configuration

    func update(zones newZones: [MakeupZone], style newStyle: FaceOverlayStyle) {
        style = newStyle
        descriptors = newZones.map {
            ZoneDescriptor(zone: $0.zone, color: UIColor(Color(hex: $0.colorHex)), finish: $0.finish)
        }

        // Grow/shrink the layer pool to match the number of zones.
        while makeupLayers.count < descriptors.count {
            let shape = CAShapeLayer()
            shape.actions = ["path": NSNull(), "shadowPath": NSNull(), "fillColor": NSNull(), "opacity": NSNull()]
            layer.addSublayer(shape)
            makeupLayers.append(shape)
        }
        while makeupLayers.count > descriptors.count {
            makeupLayers.removeLast().removeFromSuperlayer()
        }
        for (index, descriptor) in descriptors.enumerated() {
            styleLayer(makeupLayers[index], descriptor: descriptor, style: newStyle)
        }
    }

    private func styleLayer(_ shape: CAShapeLayer, descriptor: ZoneDescriptor, style: FaceOverlayStyle) {
        shape.frame = bounds
        shape.masksToBounds = false
        switch style {
        case .coach:
            shape.fillColor = descriptor.color.withAlphaComponent(0.32).cgColor
            shape.strokeColor = descriptor.color.withAlphaComponent(0.95).cgColor
            shape.lineWidth = 2
            shape.lineJoin = .round
            shape.compositingFilter = nil
            shape.shadowOpacity = 0
        case .preview:
            let params = Self.previewParams(zone: descriptor.zone, finish: descriptor.finish)
            shape.fillColor = descriptor.color.withAlphaComponent(params.alpha).cgColor
            shape.strokeColor = UIColor.clear.cgColor
            shape.lineWidth = 0
            shape.compositingFilter = params.blend
            // Feather the edges with a same-color blurred shadow so it reads like
            // applied makeup rather than a flat sticker.
            shape.shadowColor = descriptor.color.cgColor
            shape.shadowOpacity = 0.85
            shape.shadowRadius = params.feather
            shape.shadowOffset = .zero
        }
    }

    /// Per-zone / per-finish opacity, blend mode, and edge feather for the
    /// blended preview. Tuned conservatively; easy to adjust on-device.
    private static func previewParams(zone: FaceZone, finish: MakeupFinish) -> (alpha: CGFloat, blend: String, feather: CGFloat) {
        var alpha: CGFloat
        var blend: String
        switch finish {
        case .matte: alpha = 0.45; blend = "multiplyBlendMode"
        case .satin: alpha = 0.40; blend = "softLightBlendMode"
        case .dewy: alpha = 0.34; blend = "softLightBlendMode"
        case .shimmer: alpha = 0.40; blend = "screenBlendMode"
        }
        var feather: CGFloat = 8
        switch zone {
        case .lips: alpha *= 1.3; feather = 4
        case .eyelids: feather = 7
        case .lashLine: alpha *= 0.9; feather = 4
        case .lashes: feather = 5
        case .cheeks: alpha *= 0.55; feather = 20
        case .cheekbones: alpha *= 0.55; feather = 18
        case .brows: alpha *= 0.8; blend = "multiplyBlendMode"; feather = 4
        case .underEye: alpha *= 0.5; feather = 10
        case .nose, .forehead, .jawline: alpha *= 0.5; feather = 16
        case .fullFace: alpha *= 0.3; feather = 24
        }
        return (min(max(alpha, 0.08), 0.7), blend, feather)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        makeupLayers.forEach { $0.frame = bounds }
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
            DispatchQueue.main.async { [weak self] in
                self?.makeupLayers.forEach { $0.path = nil }
            }
            return
        }

        let currentDescriptors = descriptors
        let currentStyle = style
        let viewBounds = bounds
        let paths: [CGPath?] = currentDescriptors.map { descriptor in
            Self.zonePath(zone: descriptor.zone, landmarks: landmarks, boundingBox: face.boundingBox) { point in
                Self.mapPoint(point, bufW: bufW, bufH: bufH, viewBounds: viewBounds)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (index, shape) in self.makeupLayers.enumerated() where index < paths.count {
                shape.path = paths[index]
                if currentStyle == .preview {
                    shape.shadowPath = paths[index]
                }
            }
            CATransaction.commit()
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

    /// Shared face-zone geometry. `map` converts an image-normalized (y-up, 0–1)
    /// point into the target space — view space for the coaching overlay, or
    /// buffer-pixel space for the makeup filter — so both renderers agree on
    /// where each zone sits.
    static func zonePath(
        zone: FaceZone,
        landmarks: VNFaceLandmarks2D,
        boundingBox: CGRect,
        map: (CGPoint) -> CGPoint
    ) -> CGPath? {
        func pts(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            guard let region else { return [] }
            return region.normalizedPoints.map { np in
                let imageX = boundingBox.minX + CGFloat(np.x) * boundingBox.width
                let imageY = boundingBox.minY + CGFloat(np.y) * boundingBox.height
                return map(CGPoint(x: imageX, y: imageY))
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

        func addEllipse(center: CGPoint, width: CGFloat, height: CGFloat, rotation: CGFloat = 0) {
            guard width > 1, height > 1 else { return }
            if rotation == 0 {
                path.addEllipse(in: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
            } else {
                let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation)
                path.addEllipse(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), transform: transform)
            }
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

        case .lashes:
            for eye in [leftEye, rightEye] {
                if let e = bbox(eye) {
                    // Just above the upper lash line, fanned a touch wider/taller
                    // than the liner to read as full lashes.
                    addEllipse(center: CGPoint(x: e.midX, y: e.minY - e.height * 0.1), width: e.width * 1.25, height: max(e.height * 0.7, 6))
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
            let faceCenterX = (l.midX + r.midX) / 2
            let eyeSpan = max(abs(l.midX - r.midX), 1)
            let radius = max(eyeSpan * 0.30, 18)
            let noseBox = bbox(nose)
            let noseTopY = noseBox?.minY ?? ((l.maxY + r.maxY) / 2 + radius)
            let noseBottomY = noseBox?.maxY ?? (noseTopY + eyeSpan * 0.6)
            for e in [l, r] {
                let outward: CGFloat = e.midX < faceCenterX ? -1 : 1
                if zone == .cheeks {
                    addEllipse(
                        center: CGPoint(x: e.midX + outward * radius * 0.2, y: noseBottomY),
                        width: radius * 2.0, height: radius * 1.7
                    )
                } else {
                    addEllipse(
                        center: CGPoint(x: e.midX + outward * radius * 1.05, y: (noseTopY + noseBottomY) / 2),
                        width: radius * 2.3, height: radius * 1.25,
                        rotation: outward * -0.3
                    )
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
                let lower = contour.filter { $0.y > c.midY }
                let markers = [lower.first, lower.max(by: { $0.y < $1.y }), lower.last].compactMap { $0 }
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
