import Foundation
import ARKit
import AVFoundation
import Vision

/// One measurement of the face. Metrics a capture path can't measure are nil
/// (e.g. the ARKit mesh path doesn't estimate brow arch).
struct FaceSample {
    /// face height / face width
    var faceLengthToWidth: Double
    /// jaw width / cheek width
    var jawToCheekWidth: Double
    /// forehead width / cheek width
    var foreheadToCheekWidth: Double
    /// eye height / eye width
    var eyeOpenness: Double?
    /// lip height / face height
    var lipHeightRatio: Double?
    /// 0 = straight … 1 = high arch
    var browArch: Double?
}

/// Orchestrates a ~3 second scan: collects geometry samples from ARKit
/// (TrueDepth mesh) or Vision (landmarks), averages them, and maps the ratios
/// to trait labels. All processing is on-device; the camera image never leaves
/// the phone. The resulting labels are deliberately user-correctable in the UI —
/// the ratio→label thresholds are rough heuristics, not ground truth.
@MainActor
final class FaceScanService: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning(progress: Double)
        case done
        case unavailable
    }

    @Published private(set) var phase: Phase = .idle
    @Published var profile: FaceProfile?

    let usesARKit = ARFaceTrackingConfiguration.isSupported

    private(set) lazy var arController: ARFaceScanController? =
        usesARKit ? ARFaceScanController(service: self) : nil
    private(set) lazy var visionController: VisionFaceScanController? =
        usesARKit ? nil : VisionFaceScanController(service: self)

    private var samples: [FaceSample] = []
    private let requiredSamples = 24

    func start() {
        samples.removeAll()
        if usesARKit, let arController {
            arController.start()
            phase = .scanning(progress: 0)
        } else if let visionController {
            phase = .scanning(progress: 0)
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted, visionController.isConfigured {
                    visionController.start()
                } else {
                    self.phase = .unavailable
                }
            }
        } else {
            phase = .unavailable
        }
    }

    func stop() {
        arController?.stop()
        visionController?.stop()
    }

    /// Skip the camera entirely (simulator, denied permission, demos).
    func useSampleProfile() {
        stop()
        profile = .sample
        phase = .done
    }

    func ingest(_ sample: FaceSample) {
        guard case .scanning = phase else { return }
        samples.append(sample)
        if samples.count >= requiredSamples {
            stop()
            profile = Self.profile(from: samples)
            phase = .done
        } else {
            phase = .scanning(progress: Double(samples.count) / Double(requiredSamples))
        }
    }

    // MARK: - Ratios → traits (rough heuristics; user can correct every label)

    static func profile(from samples: [FaceSample]) -> FaceProfile {
        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let length = mean(samples.map(\.faceLengthToWidth)) ?? 1.3
        let jaw = mean(samples.map(\.jawToCheekWidth)) ?? 0.85
        let forehead = mean(samples.map(\.foreheadToCheekWidth)) ?? 0.9
        let openness = mean(samples.compactMap(\.eyeOpenness))
        let lipRatio = mean(samples.compactMap(\.lipHeightRatio))
        let brow = mean(samples.compactMap(\.browArch))

        let faceShape: FaceShape
        if length > 1.5 {
            faceShape = .oblong
        } else if forehead > 0.92, jaw < 0.78 {
            faceShape = .heart
        } else if forehead < 0.85, jaw < 0.85 {
            faceShape = .diamond
        } else if jaw > 0.95, length < 1.35 {
            faceShape = .square
        } else if length < 1.2 {
            faceShape = .round
        } else {
            faceShape = .oval
        }

        let eyeShape: EyeShape
        switch openness {
        case .some(let value) where value < 0.30: eyeShape = .hooded
        case .some(let value) where value > 0.45: eyeShape = .round
        default: eyeShape = .almond
        }

        let lips: LipFullness
        switch lipRatio {
        case .some(let value) where value > 0.14: lips = .full
        case .some(let value) where value < 0.09: lips = .thin
        default: lips = .balanced
        }

        let cheekbones = min(1, max(0, (1 - jaw) * 2.5))

        return FaceProfile(
            faceShape: faceShape,
            eyeShape: eyeShape,
            lipFullness: lips,
            undertone: .neutral, // not measurable from geometry; the user picks via the vein check
            cheekboneProminence: cheekbones,
            browArch: brow ?? 0.5
        )
    }
}

// MARK: - ARKit capture (TrueDepth devices)

/// Samples the true 3D face mesh. Width ratios come from mesh extents,
/// partitioned vertically into forehead / cheek / jaw bands.
final class ARFaceScanController: NSObject, ARSessionDelegate {
    let sceneView: ARSCNView
    private weak var service: FaceScanService?
    private var frameCount = 0

    @MainActor
    init(service: FaceScanService) {
        self.sceneView = ARSCNView(frame: .zero)
        self.service = service
        super.init()
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
    }

    func start() {
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        sceneView.session.pause()
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first, face.isTracked else { return }
        frameCount += 1
        guard frameCount % 3 == 0 else { return }
        let sample = Self.sample(from: face.geometry)
        Task { @MainActor [weak service] in
            service?.ingest(sample)
        }
    }

    static func sample(from geometry: ARFaceGeometry) -> FaceSample {
        let vertices = geometry.vertices
        guard !vertices.isEmpty else {
            return FaceSample(faceLengthToWidth: 1.3, jawToCheekWidth: 0.85, foreheadToCheekWidth: 0.9)
        }
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        for vertex in vertices {
            minX = min(minX, vertex.x); maxX = max(maxX, vertex.x)
            minY = min(minY, vertex.y); maxY = max(maxY, vertex.y)
        }
        let width = Double(maxX - minX)
        let height = Double(maxY - minY)
        let lowerCut = minY + (maxY - minY) / 3
        let upperCut = minY + 2 * (maxY - minY) / 3

        func bandWidth(_ belongs: (Float) -> Bool) -> Double {
            var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
            for vertex in vertices where belongs(vertex.y) {
                lo = min(lo, vertex.x); hi = max(hi, vertex.x)
            }
            return hi > lo ? Double(hi - lo) : 0
        }
        let jawWidth = bandWidth { $0 < lowerCut }
        let cheekWidth = bandWidth { $0 >= lowerCut && $0 < upperCut }
        let foreheadWidth = bandWidth { $0 >= upperCut }
        let safeCheek = max(cheekWidth, 0.0001)

        // Eye openness, lip fullness, and brow arch aren't derivable from mesh
        // extents without relying on undocumented vertex indices — left nil here;
        // defaults apply and the user can correct on the summary card.
        return FaceSample(
            faceLengthToWidth: width > 0 ? height / width : 1.3,
            jawToCheekWidth: jawWidth / safeCheek,
            foreheadToCheekWidth: foreheadWidth / safeCheek,
            eyeOpenness: nil,
            lipHeightRatio: nil,
            browArch: nil
        )
    }
}

// MARK: - Vision capture (all other devices)

/// Front-camera capture session feeding Vision face-landmark detection.
final class VisionFaceScanController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private(set) var isConfigured = false

    private let output = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "com.snehamenon.muse.facescan")
    private weak var service: FaceScanService?
    private var frameCount = 0

    init(service: FaceScanService) {
        self.service = service
        super.init()
        configure()
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .vga640x480
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        // Deliver upright, mirrored frames so Vision ratios are orientation-stable.
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        isConfigured = true
    }

    func start() {
        videoQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        videoQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCount += 1
        guard frameCount % 5 == 0,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let sample = VisionFaceAnalyzer.analyze(pixelBuffer: pixelBuffer)
        else { return }
        Task { @MainActor [weak service] in
            service?.ingest(sample)
        }
    }
}

/// Turns one camera frame into a `FaceSample` using Vision face landmarks.
enum VisionFaceAnalyzer {
    static func analyze(pixelBuffer: CVPixelBuffer) -> FaceSample? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
        guard let face = request.results?.first, let landmarks = face.landmarks else { return nil }

        let imageWidth = Double(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = Double(CVPixelBufferGetHeight(pixelBuffer))
        // Landmark points are normalized to the face bounding box; scale to pixels
        // so x/y distances are comparable.
        let scaleX = Double(face.boundingBox.width) * imageWidth
        let scaleY = Double(face.boundingBox.height) * imageHeight
        guard scaleX > 0, scaleY > 0 else { return nil }

        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint]? {
            guard let region, region.pointCount > 1 else { return nil }
            return region.normalizedPoints.map {
                CGPoint(x: Double($0.x) * scaleX, y: Double($0.y) * scaleY)
            }
        }
        func width(_ pts: [CGPoint]) -> Double {
            let xs = pts.map(\.x)
            return Double((xs.max() ?? 0) - (xs.min() ?? 0))
        }
        func height(_ pts: [CGPoint]) -> Double {
            let ys = pts.map(\.y)
            return Double((ys.max() ?? 0) - (ys.min() ?? 0))
        }

        guard let contour = points(landmarks.faceContour) else { return nil }
        let cheekWidth = width(contour)
        guard cheekWidth > 0 else { return nil }

        // The contour runs ear → jaw → chin → jaw → ear; points at the 1/4 and 3/4
        // marks approximate the mid-jaw.
        let quarter = contour[contour.count / 4]
        let threeQuarter = contour[(contour.count * 3) / 4]
        let jawWidth = abs(Double(quarter.x - threeQuarter.x))

        // Vision has no forehead landmarks; the brow span is a serviceable proxy.
        var foreheadWidth = cheekWidth * 0.9
        if let leftBrow = points(landmarks.leftEyebrow), let rightBrow = points(landmarks.rightEyebrow) {
            let xs = (leftBrow + rightBrow).map(\.x)
            foreheadWidth = Double((xs.max() ?? 0) - (xs.min() ?? 0))
        }

        let faceLength = Double(face.boundingBox.height) * imageHeight
        let faceWidth = Double(face.boundingBox.width) * imageWidth

        var eyeOpenness: Double?
        if let leftEye = points(landmarks.leftEye), let rightEye = points(landmarks.rightEye) {
            let left = width(leftEye) > 0 ? height(leftEye) / width(leftEye) : 0
            let right = width(rightEye) > 0 ? height(rightEye) / width(rightEye) : 0
            if left > 0, right > 0 { eyeOpenness = (left + right) / 2 }
        }

        var lipHeightRatio: Double?
        if let lips = points(landmarks.outerLips), faceLength > 0 {
            lipHeightRatio = height(lips) / faceLength
        }

        var browArch: Double?
        if let brow = points(landmarks.leftEyebrow), brow.count >= 3 {
            let ys = brow.map(\.y)
            let endsAverage = Double(brow.first!.y + brow.last!.y) / 2
            let peak = Double(ys.max() ?? 0)
            let browWidth = width(brow)
            if browWidth > 0 {
                browArch = min(1, max(0, (peak - endsAverage) / browWidth * 4))
            }
        }

        return FaceSample(
            faceLengthToWidth: faceWidth > 0 ? faceLength / faceWidth : 1.3,
            jawToCheekWidth: jawWidth / cheekWidth,
            foreheadToCheekWidth: foreheadWidth / cheekWidth,
            eyeOpenness: eyeOpenness,
            lipHeightRatio: lipHeightRatio,
            browArch: browArch
        )
    }
}
