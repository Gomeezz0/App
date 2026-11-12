import NEXCore
import SwiftUI

/// Buscador de destinos con resultados sesgados a la zona del usuario y destinos recientes.
struct SearchView: View {
    let onSelect: (Place) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    let recents = model.trips.recentPlaces
                    if recents.isEmpty {
                        NEXNotice(
                            systemImage: "magnifyingglass", title: "Busca un destino",
                            message: "Escribe una dirección, un lugar o un negocio.")
                            .listRowBackground(Color.clear)
                    } else {
                        Section("Recientes") { rows(recents, symbol: "clock") }
                    }
                } else if let errorMessage {
                    NEXNotice(systemImage: "wifi.exclamationmark", title: "No se pudo buscar", message: errorMessage)
                        .listRowBackground(Color.clear)
                    Button("Reintentar") { Task { await search() } }
                        .listRowBackground(NEXColor.surface)
                } else if results.isEmpty, !isSearching {
                    NEXNotice(systemImage: "mappin.slash", title: "Sin resultados", message: "Prueba con otro nombre o dirección.")
                        .listRowBackground(Color.clear)
                } else {
                    Section { rows(results, symbol: "mappin.circle.fill") }
                }
            }
            .listStyle(.plain)
            .nexScreen("Destino")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Dirección o lugar")
            .autocorrectionDisabled()
            .overlay(alignment: .top) {
                if isSearching { ProgressView().tint(NEXColor.red).padding(.top, 8) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            // Espera a que el usuario deje de teclear para no gastar peticiones.
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await search()
            }
        }
    }

    private func rows(_ places: [Place], symbol: String) -> some View {
        ForEach(places) { place in
            Button {
                onSelect(place)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol).foregroundStyle(NEXColor.red).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.nexHeadline).foregroundStyle(NEXColor.text)
                        if !place.subtitle.isEmpty {
                            Text(place.subtitle).font(.nexCaption).foregroundStyle(NEXColor.textDim)
                        }
                    }
                    Spacer()
                    if let here = model.here {
                        Text(NEXFormat.distance(Geo.distance(here, place.coordinate)))
                            .font(.nexCaption)
                            .foregroundStyle(NEXColor.textDim)
                    }
                }
                .frame(minHeight: 48)
            }
            .listRowBackground(NEXColor.surface)
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
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
            if (error as NSError).domain == MKErrorDomainName, (error as NSError).code == 4 {
                results = []
                errorMessage = nil
            } else {
                errorMessage = "Comprueba la conexión e inténtalo de nuevo."
            }
        }
    }
}

private let MKErrorDomainName = "MKErrorDomain"
