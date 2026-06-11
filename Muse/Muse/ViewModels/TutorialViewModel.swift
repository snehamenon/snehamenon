import Foundation
import UIKit

/// Step-through state for a tutorial session.
@MainActor
final class TutorialViewModel: ObservableObject {
    let look: Look

    @Published var stepIndex = 0
    @Published var isFinished = false
    @Published var afterSelfie: UIImage?

    init(look: Look) {
        self.look = look
    }

    var currentStep: TutorialStep? {
        guard look.steps.indices.contains(stepIndex) else { return nil }
        return look.steps[stepIndex]
    }

    var progress: Double {
        guard !look.steps.isEmpty else { return 0 }
        return Double(stepIndex + 1) / Double(look.steps.count)
    }

    var isLastStep: Bool {
        stepIndex >= look.steps.count - 1
    }

    func next() {
        if isLastStep {
            isFinished = true
        } else {
            stepIndex += 1
        }
    }

    func previous() {
        if isFinished {
            isFinished = false
        } else if stepIndex > 0 {
            stepIndex -= 1
        }
    }
}
