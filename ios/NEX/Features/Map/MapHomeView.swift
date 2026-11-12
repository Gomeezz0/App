import MapKit
import NEXCore
import SwiftUI

/// Pantalla principal: el mapa ocupa todo y solo flotan el buscador y tres botones.
struct MapHomeView: View {
    enum Sheet: Identifiable {
        case report, menu, auth
        case alert(CommunityAlert)

        var id: String {
            switch self {
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
    @State private var showSearch = false

    var body: some View {
        @Bindable var model = model
        ZStack {
            if model.navigation.isActive {
                DrivingView(onReport: { sheet = .report })
                    .transition(.opacity)
            } else {
                browsing
                    .transition(.opacity)
            }
            if showSearch {
                SearchView(
                    onSelect: { place in
                        closeSearch()
                        model.pendingDestination = place
                    },
                    onClose: closeSearch)
                    .transition(NEXMotion.slide(from: .bottom))
                    .zIndex(2)
            }
        }
        .nexAnimation(NEXMotion.panel, value: model.navigation.isActive)
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
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
            .presentationBackground(NEXColor.black)
            .presentationCornerRadius(28)
        }
        .fullScreenCover(item: $model.pendingDestination) { place in
            RoutePreviewView(destination: place)
        }
        // El widget de inicio abre la app con nex://search.
        .onOpenURL { url in
            if url.scheme == "nex", url.host == "search", !model.navigation.isActive { openSearch() }
        }
    }

    private func openSearch() {
        NEXMotion.animate(NEXMotion.panel) { showSearch = true }
    }

    private func closeSearch() {
        NEXMotion.animate(NEXMotion.panel) { showSearch = false }
    }

    private var visibleAlerts: [CommunityAlert] {
        model.alerts.alerts.filter { model.settings.preference(for: $0.type) != .hidden }
    }

    private var browsing: some View {
        Map(position: $camera) {
            if model.mapIsNight { MapShade() }
            UserAnnotation { _ in VehiclePuck(showsHeading: false, size: 26) }
            AlertMarkers(alerts: visibleAlerts) { sheet = .alert($0) }
        }
        .nexMapStyle(traffic: model.settings.showTraffic, night: model.mapIsNight)
        .mapControls {}
        .overlay { MapScrim(edge: .top, height: 190) }
        .overlay { MapScrim(edge: .bottom, height: 130) }
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { footer }
        .onAppear { model.refreshAlerts() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: openSearch) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(NEXColor.red)
                        Text("¿A dónde vamos?").font(.nexHeadline).foregroundStyle(NEXColor.text)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .nexPanel(radius: 28)
                }
                .buttonStyle(NEXRowButtonStyle())
                .accessibilityLabel("Buscar destino")
                MapButton(systemImage: "line.3.horizontal", label: "Menú", size: 56) { sheet = .menu }
            }

            shortcuts

            if model.location.isDenied {
                notice("Ubicación desactivada. Actívala en Ajustes para situarte en el mapa.", symbol: "location.slash.fill")
            } else if model.alerts.isStale {
                notice("Sin conexión con NEX: los avisos pueden no estar al día.", symbol: "wifi.slash")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .nexAppear()
    }

    /// Accesos rápidos: rutas habituales a esta hora y favoritos.
    @ViewBuilder private var shortcuts: some View {
        let routines = RoutineDetector.suggestions(from: model.trips.trips, at: Date(), near: model.here).map(\.place)
        let favorites = model.favorites.places.filter { place in !routines.contains { $0.id == place.id } }.prefix(4)
        if !routines.isEmpty || !favorites.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(routines) { chip($0, symbol: "clock.arrow.circlepath", hint: "Ruta habitual a esta hora") }
                    ForEach(Array(favorites)) { chip($0, symbol: "star.fill", hint: "Favorito") }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func chip(_ place: Place, symbol: String, hint: String) -> some View {
        Button {
            model.pendingDestination = place
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(NEXColor.red)
                Text(place.name).font(.nexCaption).foregroundStyle(NEXColor.text).lineLimit(1)
            }
            .padding(.horizontal, 13)
            .frame(height: 38)
            .nexPanel(radius: 19)
        }
        .buttonStyle(NEXRowButtonStyle())
        .accessibilityLabel("Ir a \(place.name)")
        .accessibilityHint(hint)
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Spacer()
            VStack(spacing: 12) {
                MapButton(systemImage: "location.fill", label: "Centrar en mi posición") {
                    NEXMotion.animate { camera = .userLocation(fallback: .automatic) }
                }
                MapButton(systemImage: "plus.bubble.fill", label: "Avisar de una incidencia", prominent: true, size: 66) {
                    sheet = .report
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .nexAppear(delay: 0.1)
    }

    private func notice(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.nexCaption)
            .foregroundStyle(NEXColor.amber)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nexPanel(radius: 16)
            .transition(NEXMotion.rise)
    }
}

/// Menú principal: acceso al resto de pantallas.
struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        NEXLogo(size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.user?.displayName ?? "NEX").font(.nexTitle).foregroundStyle(NEXColor.text)
                            Text(model.user == nil ? "Sin sesión iniciada" : "Reputación \(model.user?.reputation ?? 0)")
                                .font(.nexCaption).foregroundStyle(NEXColor.textDim)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)

                    row("Perfil", model.user == nil ? "Entrar" : "", "person.fill", 0) { ProfileView() }
                    row("Avisos cercanos", "\(model.alerts.alerts.count)", "bell.fill", 1) { NearbyAlertsView() }
                    row("Favoritos", "\(model.favorites.places.count)", "star.fill", 2) { FavoritesView() }
                    row("Historial de viajes", "\(model.trips.trips.count)", "clock.fill", 3) { TripHistoryView() }
                    row("Ajustes", "", "gearshape.fill", 4) { SettingsView() }
                }
                .padding(16)
            }
            .nexScreen("Menú")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
        }
    }

    private func row<Destination: View>(
        _ title: String, _ detail: String, _ symbol: String, _ index: Int,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                NEXIconTile(systemImage: symbol, tint: NEXColor.red)
                Text(title).font(.nexHeadline).foregroundStyle(NEXColor.text)
                Spacer()
                Text(detail).font(.nexNumber(15)).foregroundStyle(NEXColor.textDim)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(NEXColor.mid)
            }
            .nexCard(padding: 12)
        }
        .buttonStyle(NEXRowButtonStyle())
        .nexAppear(delay: Double(index) * 0.04)
    }
}

/// Lugares favoritos guardados en el dispositivo.
struct FavoritesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if model.favorites.places.isEmpty {
                    NEXNotice(
                        systemImage: "star", title: "Sin favoritos",
                        message: "Marca un destino con la estrella en la vista de rutas para tenerlo siempre a mano.")
                }
                ForEach(model.favorites.places) { place in
                    HStack(spacing: 14) {
                        Button {
                            model.pendingDestination = place
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                NEXIconTile(systemImage: "star.fill", tint: NEXColor.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name).font(.nexHeadline).foregroundStyle(NEXColor.text).lineLimit(1)
                                    if !place.subtitle.isEmpty {
                                        Text(place.subtitle).font(.nexCaption).foregroundStyle(NEXColor.textDim).lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(NEXRowButtonStyle())
                        .accessibilityHint("Abre la ruta a este destino")
                        Button {
                            NEXMotion.animate { model.favorites.toggle(place) }
                        } label: {
                            Image(systemName: "trash").font(.system(size: 16, weight: .semibold)).foregroundStyle(NEXColor.textDim)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Quitar \(place.name) de favoritos")
                    }
                    .nexCard(padding: 12)
                    .transition(.opacity)
                }
            }
            .padding(16)
        }
        .nexScreen("Favoritos")
    }
}
