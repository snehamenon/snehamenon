import Foundation
import SwiftUI

/// Source of truth for the session: stage routing plus everything gathered
/// along the way (face profile, intent, weather, generated looks).
@MainActor
final class AppState: ObservableObject {
    enum Stage: Equatable {
        case onboarding
        case scan
        case intent
        case looks
        case tutorial
    }

    @Published var stage: Stage = .onboarding
    @Published var faceProfile: FaceProfile?
    @Published var intent = LookIntent()
    @Published var looks: [Look] = []
    @Published var selectedLook: Look?

    let weatherService = WeatherService()

    /// Claude when a key is configured, canned looks otherwise.
    let director: LookDirector

    var isMockMode: Bool { director.isMock }

    init() {
        if let claude = ClaudeLookDirector.ifConfigured() {
            director = claude
        } else {
            director = MockLookDirector()
        }
    }

    func advanceToIntent(with profile: FaceProfile) {
        faceProfile = profile
        weatherService.refresh()
        stage = .intent
    }

    func startTutorial(with look: Look) {
        selectedLook = look
        stage = .tutorial
    }

    func restart() {
        looks = []
        selectedLook = nil
        intent = LookIntent()
        stage = .scan
    }
}
