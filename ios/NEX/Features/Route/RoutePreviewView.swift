import MapKit
import NEXCore
import SwiftUI

/// Vista previa: rutas alternativas con su tiempo y distancia, comparación de horas de salida
/// y aparcamientos cerca del destino.
struct RoutePreviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State var destination: Place
    @State private var routes: [Route] = []
    @State private var selectedID: UUID?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var camera: MapCameraPosition = .automatic
    @State private var departures: [DepartureOption] = []
    @State private var isComparing = false
    @State private var parking: [Place]?
    @State private var isLoadingParking = false

    struct DepartureOption: Identifiable {
        let minutes: Int
        let travelTime: TimeInterval
        var id: Int { minutes }
    }

    private var selected: Route? { routes.first { $0.id == selectedID } ?? routes.first }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(routes.filter { $0.id != selected?.id }) { route in
                RouteLine(route: route, selected: false)
            }
            ForEach(routes.filter { $0.id == selected?.id }) { route in
                RouteLine(route: route)
            }
            Marker(destination.name, systemImage: "flag.checkered", coordinate: destination.coordinate.cl)
                .tint(NEXColor.red)
        }
        .nexMapStyle(traffic: model.settings.showTraffic, night: model.mapIsNight)
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { panel }
        .task(id: destination.id) { await loadRoutes() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MapButton(systemImage: "chevron.left", label: "Volver") { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.name).font(.nexHeadline).foregroundStyle(NEXColor.text).lineLimit(1)
                if !destination.subtitle.isEmpty {
                    Text(destination.subtitle).font(.nexCaption).foregroundStyle(NEXColor.textDim).lineLimit(1)
                }
            }
            Spacer()
        }
        .nexCard(padding: 10)
        .padding(.horizontal, 14)
    }

    @ViewBuilder private var panel: some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView("Calculando rutas…").tint(NEXColor.red).foregroundStyle(NEXColor.textDim).padding(24)
            } else if let errorMessage {
                NEXNotice(systemImage: "exclamationmark.triangle.fill", title: "No se pudo calcular la ruta", message: errorMessage)
                Button("Reintentar") { Task { await loadRoutes() } }.buttonStyle(NEXSecondaryButtonStyle())
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(routes) { route in routeRow(route) }
                        extras
                    }
                }
                .frame(maxHeight: 300)
                .scrollBounceBehavior(.basedOnSize)

                Button {
                    if let selected {
                        model.startNavigation(route: selected, to: destination)
                        dismiss()
                    }
                } label: {
                    Label("Iniciar", systemImage: "location.north.fill")
                }
                .buttonStyle(NEXPrimaryButtonStyle())
            }
        }
        .padding(14)
        .background(NEXColor.black, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
    }

    private func routeRow(_ route: Route) -> some View {
        let isSelected = route.id == selected?.id
        return Button {
            selectedID = route.id
            withAnimation { camera = .rect(route.polyline.cameraRect) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(route.kind.title.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .kerning(0.8)
                            .foregroundStyle(route.kind == .fastest ? NEXColor.red : NEXColor.textDim)
                        if route.hasTolls {
                            Text("PEAJE").font(.system(size: 11, weight: .bold)).foregroundStyle(NEXColor.amber)
                        }
                    }
                    Text("Por \(route.name)").font(.nexBody).foregroundStyle(NEXColor.text).lineLimit(1)
                    if let notice = route.notices.first {
                        Text(notice).font(.nexCaption).foregroundStyle(NEXColor.amber).lineLimit(2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(NEXFormat.duration(route.expectedTravelTime)).font(.nexNumber(20)).foregroundStyle(NEXColor.text)
                    Text(NEXFormat.distance(route.distance)).font(.nexCaption).foregroundStyle(NEXColor.textDim)
                }
            }
            .padding(14)
            .background(NEXColor.surface, in: RoundedRectangle(cornerRadius: NEXMetric.radius))
            .overlay(
                RoundedRectangle(cornerRadius: NEXMetric.radius)
                    .stroke(isSelected ? NEXColor.red : NEXColor.stroke, lineWidth: isSelected ? 2 : 1))
        }
        .accessibilityLabel(
            "\(route.kind.title), por \(route.name), \(NEXFormat.duration(route.expectedTravelTime)), \(NEXFormat.distance(route.distance))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Predicción por hora de salida y aparcamientos: se piden solo si el usuario los quiere.
    @ViewBuilder private var extras: some View {
        if model.routing.capabilities.departureTimeETA {
            if departures.isEmpty {
                Button {
                    Task { await compareDepartures() }
                } label: {
                    if isComparing {
                        ProgressView().tint(NEXColor.text)
                    } else {
                        Label("Comparar con salir más tarde", systemImage: "clock.badge.questionmark")
                    }
                }
                .buttonStyle(NEXSecondaryButtonStyle())
                .disabled(isComparing)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TIEMPO ESTIMADO SEGÚN LA SALIDA").font(.system(size: 11, weight: .bold)).foregroundStyle(NEXColor.textDim)
                    HStack(spacing: 8) {
                        ForEach(departures) { option in
                            VStack(spacing: 2) {
                                Text(option.minutes == 0 ? "Ahora" : "+\(option.minutes) min")
                                    .font(.nexCaption).foregroundStyle(NEXColor.textDim)
                                Text(NEXFormat.duration(option.travelTime))
                                    .font(.nexNumber(16))
                                    .foregroundStyle(option.id == bestDeparture ? NEXColor.green : NEXColor.text)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Text("Estimación de \(model.routing.capabilities.name) con su previsión de tráfico.")
                        .font(.system(size: 11)).foregroundStyle(NEXColor.textDim)
                }
                .nexCard(padding: 12)
            }
        }

        if let parking {
            VStack(alignment: .leading, spacing: 8) {
                Text("APARCAMIENTOS CERCA DEL DESTINO").font(.system(size: 11, weight: .bold)).foregroundStyle(NEXColor.textDim)
                if parking.isEmpty {
                    Text("No se han encontrado aparcamientos a menos de 600 m.").font(.nexCaption).foregroundStyle(NEXColor.textDim)
                }
                ForEach(parking.prefix(4)) { place in
                    Button {
                        destination = place
                        self.parking = nil
                        departures = []
                    } label: {
                        HStack {
                            Image(systemName: "parkingsign.circle.fill").foregroundStyle(NEXColor.red)
                            Text(place.name).foregroundStyle(NEXColor.text).lineLimit(1)
                            Spacer()
                            Text(NEXFormat.distance(Geo.distance(place.coordinate, destination.coordinate)))
                                .foregroundStyle(NEXColor.textDim)
                        }
                        .font(.nexBody)
                        .frame(minHeight: 40)
                    }
                    .accessibilityHint("Cambia el destino a este aparcamiento")
                }
                if !model.parking.providesAvailability {
                    Text("Solo ubicación: no hay datos de plazas libres.").font(.system(size: 11)).foregroundStyle(NEXColor.textDim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nexCard(padding: 12)
        } else {
            Button {
                Task { await loadParking() }
            } label: {
                if isLoadingParking {
                    ProgressView().tint(NEXColor.text)
                } else {
                    Label("Buscar aparcamiento cerca", systemImage: "parkingsign")
                }
            }
            .buttonStyle(NEXSecondaryButtonStyle())
            .disabled(isLoadingParking)
        }
    }

    private var bestDeparture: Int? {
        departures.min { $0.travelTime < $1.travelTime }?.id
    }

    // MARK: - Carga

    private func loadRoutes() async {
        guard let origin = model.here else {
            isLoading = false
            errorMessage = "Aún no hay señal GPS. Comprueba que la ubicación está permitida."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let found = try await model.routing.routes(from: origin, to: destination.coordinate, departure: nil)
            guard !Task.isCancelled else { return }
            routes = found
            selectedID = found.first?.id
            if let first = found.first { camera = .rect(first.polyline.cameraRect) }
        } catch {
            guard !Task.isCancelled else { return }
            routes = []
            errorMessage = (error as? ProviderError)?.errorDescription
                ?? "No hay ruta en coche hasta ese punto o falta conexión."
        }
        isLoading = false
    }

    private func compareDepartures() async {
        guard let origin = model.here, let selected else { return }
        isComparing = true
        defer { isComparing = false }
        var options = [DepartureOption(minutes: 0, travelTime: selected.expectedTravelTime)]
        for minutes in [15, 30, 60] {
            let departure = Date().addingTimeInterval(Double(minutes) * 60)
            if let time = try? await model.routing.travelTime(from: origin, to: destination.coordinate, departure: departure) {
                options.append(DepartureOption(minutes: minutes, travelTime: time))
            }
        }
        // Si no se obtuvo ninguna estimación futura no hay nada que comparar.
        if options.count > 1 { departures = options }
    }

    private func loadParking() async {
        isLoadingParking = true
        defer { isLoadingParking = false }
        parking = (try? await model.parking.parking(near: destination.coordinate)) ?? []
    }
}
