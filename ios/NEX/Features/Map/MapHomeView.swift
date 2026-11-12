import MapKit
import NEXCore
import SwiftUI

/// Pantalla principal: el mapa ocupa todo y solo flotan el buscador y tres botones.
struct MapHomeView: View {
    enum Sheet: Identifiable {
        case search, report, menu, auth
        case alert(CommunityAlert)

        var id: String {
            switch self {
            case .search: return "search"
            case .report: return "report"
            case .menu: return "menu"
            case .auth: return "auth"
            case .alert(let alert): return "alert-\(alert.id)"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var sheet: Sheet?

    var body: some View {
        @Bindable var model = model
        Group {
            if model.navigation.isActive {
                DrivingView(onReport: { sheet = .report })
            } else {
                browsing
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .search:
                SearchView { place in
                    self.sheet = nil
                    model.pendingDestination = place
                }
            case .report:
                ReportSheet(onNeedsAccount: { self.sheet = .auth })
                    .presentationDetents([.large])
            case .menu:
                MenuView()
            case .auth:
                AuthView()
            case .alert(let alert):
                AlertDetailView(alertID: alert.id, onNeedsAccount: { self.sheet = .auth })
                    .presentationDetents([.medium])
            }
        }
        .fullScreenCover(item: $model.pendingDestination) { place in
            RoutePreviewView(destination: place)
        }
        // El widget de inicio abre la app con nex://search.
        .onOpenURL { url in
            if url.scheme == "nex", url.host == "search", !model.navigation.isActive { sheet = .search }
        }
    }

    private var visibleAlerts: [CommunityAlert] {
        model.alerts.alerts.filter { model.settings.preference(for: $0.type) != .hidden }
    }

    private var browsing: some View {
        Map(position: $camera) {
            UserAnnotation()
            AlertMarkers(alerts: visibleAlerts) { sheet = .alert($0) }
        }
        .nexMapStyle(traffic: model.settings.showTraffic, night: model.mapIsNight)
        .mapControls { MapCompass() }
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { footer }
        .onAppear { model.refreshAlerts() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    sheet = .search
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(NEXColor.red)
                        Text("¿A dónde vamos?").foregroundStyle(NEXColor.textDim)
                        Spacer()
                    }
                    .font(.nexHeadline)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(NEXColor.surface, in: Capsule())
                    .overlay(Capsule().stroke(NEXColor.stroke))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                }
                .accessibilityLabel("Buscar destino")
                MapButton(systemImage: "line.3.horizontal", label: "Menú") { sheet = .menu }
            }

            let suggestions = RoutineDetector.suggestions(from: model.trips.trips, at: Date(), near: model.here)
            ForEach(suggestions) { suggestion in
                Button {
                    model.pendingDestination = suggestion.place
                } label: {
                    Label("Ir a \(suggestion.place.name)", systemImage: "clock.arrow.circlepath")
                        .font(.nexCaption)
                        .foregroundStyle(NEXColor.text)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(NEXColor.surface, in: Capsule())
                        .overlay(Capsule().stroke(NEXColor.stroke))
                }
                .accessibilityHint("Ruta habitual a esta hora")
            }

            if model.location.isDenied {
                notice("Ubicación desactivada. Actívala en Ajustes para situarte en el mapa.", symbol: "location.slash.fill")
            } else if model.alerts.isStale {
                notice("Sin conexión con NEX: los avisos pueden no estar al día.", symbol: "wifi.slash")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Spacer()
            VStack(spacing: 12) {
                MapButton(systemImage: "location.fill", label: "Centrar en mi posición") {
                    withAnimation { camera = .userLocation(fallback: .automatic) }
                }
                MapButton(systemImage: "plus.bubble.fill", label: "Avisar de una incidencia", prominent: true, size: 64) {
                    sheet = .report
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func notice(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.nexCaption)
            .foregroundStyle(NEXColor.amber)
            .padding(10)
            .background(NEXColor.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Menú principal: acceso al resto de pantallas.
struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Perfil", model.user?.displayName ?? "Sin sesión", "person.crop.circle.fill") { ProfileView() }
                    row("Avisos cercanos", "\(model.alerts.alerts.count)", "bell.badge.fill") { NearbyAlertsView() }
                    row("Historial de viajes", "\(model.trips.trips.count)", "clock.fill") { TripHistoryView() }
                    row("Ajustes", "", "gearshape.fill") { SettingsView() }
                }
                .listRowBackground(NEXColor.surface)
            }
            .nexScreen("NEX")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
        }
    }

    private func row<Destination: View>(
        _ title: String, _ detail: String, _ symbol: String, @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(title, systemImage: symbol).foregroundStyle(NEXColor.text)
                Spacer()
                Text(detail).foregroundStyle(NEXColor.textDim)
            }
            .frame(minHeight: 44)
        }
    }
}
