import Foundation

/// Drives look generation and its loading/error states.
@MainActor
final class LooksViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading(message: String)
        case loaded
        case failed(message: String)
    }

    @Published private(set) var state: State = .idle

    private static let loadingMessages = [
        "Reading your features…",
        "Checking today's weather against your products…",
        "Sketching palettes for your undertone…",
        "Directing your looks…",
    ]

    private var messageRotation: Task<Void, Never>?

    /// Called when looks already exist (e.g. returning from a tutorial) so a
    /// fresh view model doesn't sit in `.idle` showing the loader forever.
    func adoptExistingLooks() {
        state = .loaded
    }

    func generate(into app: AppState) async {
        guard let profile = app.faceProfile else {
            state = .failed(message: "No face profile yet — rescan to continue.")
            return
        }
        state = .loading(message: Self.loadingMessages[0])
        rotateLoadingMessages()
        defer { messageRotation?.cancel() }

        do {
            let looks = try await app.director.generateLooks(
                profile: profile,
                intent: app.intent,
                weather: app.weatherService.snapshot
            )
            guard !looks.isEmpty else {
                state = .failed(message: "No looks came back. Try again.")
                return
            }
            app.looks = looks
            state = .loaded
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    /// Lets the user keep moving even if the API call fails (network, key, etc).
    func fallBackToMock(into app: AppState) async {
        state = .loading(message: "Loading sample looks…")
        if let looks = try? await MockLookDirector().generateLooks(
            profile: app.faceProfile ?? .sample,
            intent: app.intent,
            weather: app.weatherService.snapshot
        ) {
            app.looks = looks
            state = .loaded
        } else {
            state = .failed(message: "Could not load sample looks.")
        }
    }

    private func rotateLoadingMessages() {
        messageRotation?.cancel()
        messageRotation = Task {
            var index = 1
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                guard case .loading = state else { return }
                state = .loading(message: Self.loadingMessages[index % Self.loadingMessages.count])
                index += 1
            }
        }
    }
}
