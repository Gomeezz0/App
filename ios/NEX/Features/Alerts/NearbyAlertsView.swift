import NEXCore
import SwiftUI

/// Panel de avisos cercanos, del más próximo al más lejano.
struct NearbyAlertsView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: CommunityAlert?
    @State private var showAuth = false

    private var sorted: [(alert: CommunityAlert, distance: Double?)] {
        let here = model.here
        return model.alerts.alerts
            .filter { model.settings.preference(for: $0.type) != .hidden }
            .map { alert in (alert: alert, distance: here.map { Geo.distance($0, alert.coordinate) }) }
            .sorted { ($0.distance ?? 0) < ($1.distance ?? 0) }
    }

    var body: some View {
        List {
            if model.alerts.isStale {
                Label("Sin conexión: la lista puede no estar al día.", systemImage: "wifi.slash")
                    .font(.nexCaption)
                    .foregroundStyle(NEXColor.amber)
                    .listRowBackground(NEXColor.surface)
            }
            if sorted.isEmpty {
                NEXNotice(
                    systemImage: "checkmark.seal", title: "Sin avisos cerca",
                    message: "No hay incidencias reportadas en un radio de 15 km.")
                    .listRowBackground(Color.clear)
            }
            ForEach(sorted, id: \.alert.id) { item in
                Button {
                    selected = item.alert
                } label: {
                    AlertRow(alert: item.alert, distance: item.distance)
                }
                .buttonStyle(NEXRowButtonStyle())
                .listRowBackground(NEXColor.surface)
                .listRowSeparatorTint(NEXColor.mid)
            }
        }
        .nexScreen("Avisos cercanos")
        .refreshable { model.refreshAlerts(force: true) }
        .onAppear { model.refreshAlerts() }
        .sheet(item: $selected) { alert in
            AlertDetailView(alertID: alert.id, onNeedsAccount: {
                selected = nil
                showAuth = true
            })
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAuth) { AuthView() }
    }
}

struct AlertRow: View {
    let alert: CommunityAlert
    let distance: Double?

    var body: some View {
        HStack(spacing: 12) {
            AlertBadge(type: alert.type, level: alert.isOfficial ? .high : alert.level, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(alert.displayTitle).font(.nexHeadline).foregroundStyle(NEXColor.text)
                    NEXTag(text: alert.isOfficial ? "Oficial" : alert.level.title, color: levelColor)
                }
                Text(subtitle).font(.nexCaption).foregroundStyle(NEXColor.textDim)
            }
            Spacer()
            if let distance {
                Text(NEXFormat.distance(distance)).font(.nexNumber(17)).foregroundStyle(NEXColor.text)
            }
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var levelColor: Color {
        if alert.isOfficial { return NEXColor.text }
        switch alert.level {
        case .high: return NEXColor.green
        case .medium: return NEXColor.amber
        case .low: return NEXColor.textDim
        }
    }

    private var subtitle: String {
        if alert.isOfficial { return "Fuente oficial" }
        let age = alert.createdAt.formatted(.relative(presentation: .named))
        let confirmed = alert.confirmations == 1 ? "1 confirmación" : "\(alert.confirmations) confirmaciones"
        return "\(confirmed) · \(age)"
    }
}

/// Detalle de un aviso, con las acciones de la comunidad.
struct AlertDetailView: View {
    let alertID: String
    let onNeedsAccount: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var message: String?

    /// Se lee del servicio para reflejar el resultado del voto al instante.
    private var alert: CommunityAlert? { model.alerts.alerts.first { $0.id == alertID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let alert {
                AlertRow(alert: alert, distance: model.here.map { Geo.distance($0, alert.coordinate) })

                if alert.approximate {
                    info("La ubicación es aproximada: en este país los avisos de este tipo se muestran por zonas.")
                }
                if alert.level == .low, !alert.isOfficial {
                    info("Aviso sin verificar: lo ha enviado una sola persona y nadie lo ha confirmado todavía.")
                }

                if alert.isOfficial {
                    info("Procede de una fuente oficial y no admite votos.")
                } else if alert.mine {
                    info("Este aviso es tuyo. Ganarás reputación cuando otros conductores lo confirmen.")
                } else if !model.isSignedIn {
                    Button("Inicia sesión para valorarlo", action: onNeedsAccount).buttonStyle(NEXSecondaryButtonStyle())
                } else {
                    HStack(spacing: 12) {
                        voteButton("Sigue ahí", "hand.thumbsup.fill", .confirm, alert)
                        voteButton("Ya no está", "hand.thumbsdown.fill", .deny, alert)
                    }
                    if let vote = alert.myVote {
                        Text(vote == .confirm ? "Lo has confirmado." : "Has indicado que ya no está.")
                            .font(.nexCaption).foregroundStyle(NEXColor.textDim)
                    }
                }
            } else {
                NEXNotice(systemImage: "checkmark.circle", title: "Aviso retirado", message: "Este aviso ya no está activo.")
            }
            if let message {
                Label(message, systemImage: "exclamationmark.circle.fill").font(.nexCaption).foregroundStyle(NEXColor.amber)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nexAnimation(value: alert)
    }

    private func info(_ text: String) -> some View {
        Text(text).font(.nexBody).foregroundStyle(NEXColor.textDim)
    }

    private func voteButton(_ title: String, _ symbol: String, _ vote: AlertVote, _ alert: CommunityAlert) -> some View {
        Button {
            isWorking = true
            message = nil
            Task {
                defer { isWorking = false }
                do {
                    try await model.vote(vote, on: alert)
                } catch APIError.unauthorized {
                    onNeedsAccount()
                } catch {
                    message = error.localizedDescription
                }
            }
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(NEXSecondaryButtonStyle())
        .disabled(isWorking || alert.myVote == vote)
    }
}
