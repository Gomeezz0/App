import NEXCore
import SwiftUI

/// Buscador de destinos: campo destacado, favoritos, recientes y sugerencias mientras se escribe.
/// Se muestra sobre el mapa con una transición suave (ver `MapHomeView`).
struct SearchView: View {
    let onSelect: (Place) -> Void
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if trimmed.count < 2 {
                        idle
                    } else if let errorMessage {
                        NEXNotice(systemImage: "wifi.exclamationmark", title: "No se pudo buscar", message: errorMessage)
                        Button("Reintentar") { Task { await search() } }
                            .buttonStyle(NEXSecondaryButtonStyle())
                    } else if results.isEmpty, !isSearching {
                        NEXNotice(systemImage: "mappin.slash", title: "Sin resultados", message: "Prueba con otro nombre o dirección.")
                    } else {
                        NEXSectionLabel("Resultados").padding(.top, 6)
                        rows(results, symbol: "mappin", identifier: "search-result")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .nexAnimation(value: results)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(NEXColor.surface.ignoresSafeArea())
        .onAppear { focused = true }
        // Espera a que el usuario deje de teclear para no gastar peticiones.
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            NEXField(systemImage: "magnifyingglass", focused: focused) {
                TextField("Dirección o lugar", text: $query, prompt: Text("Dirección o lugar").foregroundStyle(NEXColor.textDim))
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("search-field")
                if isSearching {
                    NEXLoader(size: 20)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(NEXColor.textDim)
                    }
                    .accessibilityLabel("Borrar búsqueda")
                }
            }
            Button("Cancelar") {
                focused = false
                onClose()
            }
            .font(.nexHeadline)
            .foregroundStyle(NEXColor.red)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    /// Antes de escribir: origen, favoritos y recientes.
    @ViewBuilder private var idle: some View {
        HStack(spacing: 14) {
            NEXIconTile(systemImage: model.here == nil ? "location.slash" : "location.fill", tint: NEXColor.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Desde tu ubicación").font(.nexHeadline).foregroundStyle(NEXColor.text)
                Text(model.here == nil ? "Sin señal GPS todavía" : "Las distancias se calculan desde donde estás")
                    .font(.nexCaption).foregroundStyle(NEXColor.textDim)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)

        let favorites = model.favorites.places
        if !favorites.isEmpty {
            NEXSectionLabel("Favoritos").padding(.top, 10)
            rows(favorites, symbol: "star.fill", identifier: "favorite")
        }
        let recents = model.trips.recentPlaces.filter { place in !favorites.contains { $0.id == place.id } }
        if !recents.isEmpty {
            NEXSectionLabel("Recientes").padding(.top, 10)
            rows(recents, symbol: "clock", identifier: "recent")
        }
        if favorites.isEmpty, recents.isEmpty {
            NEXNotice(
                systemImage: "magnifyingglass", title: "¿A dónde vamos?",
                message: "Escribe una dirección, un lugar o un negocio. Tus destinos recientes y favoritos aparecerán aquí.")
        }
    }

    private func rows(_ places: [Place], symbol: String, identifier: String) -> some View {
        ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
            Button {
                focused = false
                onSelect(place)
            } label: {
                HStack(spacing: 14) {
                    NEXIconTile(systemImage: symbol, tint: symbol == "star.fill" ? NEXColor.red : NEXColor.text)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.nexHeadline).foregroundStyle(NEXColor.text).lineLimit(1)
                        if !place.subtitle.isEmpty {
                            Text(place.subtitle).font(.nexCaption).foregroundStyle(NEXColor.textDim).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if let here = model.here {
                        Text(NEXFormat.distance(Geo.distance(here, place.coordinate)))
                            .font(.nexNumber(15))
                            .foregroundStyle(NEXColor.textDim)
                    }
                }
                .frame(minHeight: 60)
            }
            .buttonStyle(NEXRowButtonStyle())
            .accessibilityIdentifier("\(identifier)-\(index)")
            .nexAppear(delay: Double(min(index, 8)) * 0.03)
        }
    }

    private func search() async {
        let text = trimmed
        guard text.count >= 2 else {
            results = []
            errorMessage = nil
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await model.search.search(text, near: model.here)
            guard !Task.isCancelled else { return }
            results = found
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            // MapKit devuelve error cuando no hay coincidencias; se distingue de un fallo de red.
            if (error as NSError).domain == "MKErrorDomain", (error as NSError).code == 4 {
                results = []
                errorMessage = nil
            } else {
                errorMessage = "Comprueba la conexión e inténtalo de nuevo."
            }
        }
    }
}
