import ActivityKit
import Foundation

/// Mantiene la Live Activity de la navegación (pantalla bloqueada e Isla Dinámica).
/// Si el usuario las tiene desactivadas, no hace nada.
@MainActor
final class LiveActivityController {
    typealias State = NavigationActivityAttributes.ContentState

    private var activity: Activity<NavigationActivityAttributes>?
    private var lastState: State?
    private var lastUpdate = Date.distantPast

    func start(destinationName: String, state: State) {
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(
            attributes: NavigationActivityAttributes(destinationName: destinationName),
            content: ActivityContent(state: state, staleDate: nil))
        lastState = state
        lastUpdate = Date()
    }

    /// Actualiza como mucho cada 5 s, salvo que cambie la maniobra o la fase: así no gasta de más.
    func update(_ state: State) {
        guard let activity, state != lastState else { return }
        let changed = state.phase != lastState?.phase || state.instruction != lastState?.instruction
        guard changed || Date().timeIntervalSince(lastUpdate) >= 5 else { return }
        lastState = state
        lastUpdate = Date()
        Task {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(120)))
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        lastState = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
