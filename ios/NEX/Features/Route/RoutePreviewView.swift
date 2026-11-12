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
    @State private var expandedNotice: UUID?

    struct DepartureOption: Identifiable {
        let minutes: Int
        let travelTime: TimeInterval
        var id: Int { minutes }
    }

    private var selected: Route? { routes.first { $0.id == selectedID } ?? routes.first }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation { _ in VehiclePuck(showsHeading: false, size: 26) }
            ForEach(routes.filter { $0.id != selected?.id }) { route in
                RouteLine(route: route, selected: false)
            }
            ForEach(routes.filter { $0.id == selected?.id }) { route in
                RouteLine(route: route)
            }
            Annotation(destination.name, coordinate: destination.coordinate.cl, anchor: .center) { DestinationPin() }
        }
        .nexMapStyle(traffic: model.settings.showTraffic, night: model.mapIsNight)
        .mapControls {}
        .overlay { MapScrim(edge: .top, height: 150) }
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { panel }
        .task(id: destination.id) { await loadRoutes() }
    }

    private var header: some View {
        let isFavorite = model.favorites.contains(destination)
        return HStack(spacing: 12) {
            MapButton(systemImage: "chevron.left", label: "Volver", size: 46) { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.name).font(.nexHeadline).foregroundStyle(NEXColor.text).lineLimit(1)
                if !destination.subtitle.isEmpty {
                    Text(destination.subtitle).font(.nexCaption).foregroundStyle(NEXColor.textDim).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                NEXMotion.animate(NEXMotion.quick) { model.favorites.toggle(destination) }
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isFavorite ? NEXColor.red : NEXColor.textDim)
                    .frame(width: 46, height: 46)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(isFavorite ? "Quitar de favoritos" : "Guardar en favoritos")
        }
        .padding(8)
        .nexPanel(radius: 31)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .nexAppear()
    }

    private var panel: some View {
        VStack(spacing: 12) {
            if isLoading {
                VStack(spacing: 14) {
                    NEXLoader(size: 34)
                    Text("Calculando rutas…").font(.nexHeadline).foregroundStyle(NEXColor.textDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .transition(.opacity)
            } else if let errorMessage {
                NEXNotice(systemImage: "exclamationmark.triangle.fill", title: "No se pudo calcular la ruta", message: errorMessage)
                Button("Reintentar") { Task { await loadRoutes() } }.buttonStyle(NEXSecondaryButtonStyle())
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                            routeRow(route).nexAppear(delay: Double(index) * 0.06)
                        }
                        extras
                    }
                    .padding(.top, 2)
                }
                .frame(maxHeight: 300)
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)

                Button {
                    if let selected {
                        model.startNavigation(route: selected, to: destination)
                        dismiss()
                    }
                } label: {
                    Label("Iniciar", systemImage: "location.north.fill")
                }
                .buttonStyle(NEXPrimaryButtonStyle())
                .sensoryFeedback(.impact, trigger: model.navigation.isActive)
            }
        }
        .padding(14)
        .nexPanel(radius: 30)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .nexAnimation(value: isLoading)
        .nexAnimation(NEXMotion.quick, value: selectedID)
    }

    private func routeRow(_ route: Route) -> some View {
        let isSelected = route.id == selected?.id
        return Button {
            selectedID = route.id
            NEXMotion.animate(NEXMotion.panel) { camera = .rect(route.polyline.cameraRect) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        NEXTag(text: route.kind.title, color: route.kind == .fastest ? NEXColor.red : NEXColor.textDim)
                        if route.hasTolls { NEXTag(text: "Peaje", color: NEXColor.amber) }
                    }
                    Text("Por \(route.name)").font(.nexHeadline).foregroundStyle(NEXColor.text).lineLimit(1)
                    if let notice = route.notices.first {
                        // Avisos del proveedor (zonas de bajas emisiones, restricciones…): se despliegan al tocar.
                        Label(notice, systemImage: "info.circle.fill")
                            .font(.nexCaption)
                            .foregroundStyle(NEXColor.amber)
                            .lineLimit(expandedNotice == route.id ? nil : 1)
                            .multilineTextAlignment(.leading)
                            .onTapGesture { NEXMotion.animate { expandedNotice = expandedNotice == route.id ? nil : route.id } }
                            .accessibilityHint("Toca para leer el aviso completo")
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(NEXFormat.duration(route.expectedTravelTime))
                        .font(.nexNumber(22))
                        .foregroundStyle(isSelected ? NEXColor.text : NEXColor.textDim)
                    Text(NEXFormat.distance(route.distance)).font(.nexCaption).foregroundStyle(NEXColor.textDim)
                }
            }
            .padding(14)
            .background(
                isSelected ? NEXColor.red.opacity(0.10) : NEXColor.surfaceHigh.opacity(0.6),
                in: RoundedRectangle(cornerRadius: NEXMetric.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NEXMetric.radius, style: .continuous)
                    .strokeBorder(isSelected ? NEXColor.red : NEXColor.stroke, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(NEXRowButtonStyle())
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
                        NEXLoader(size: 22)
                    } else {
                        Label("Comparar con salir más tarde", systemImage: "clock.badge.questionmark")
                    }
                }
                .buttonStyle(NEXSecondaryButtonStyle())
                .disabled(isComparing)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    NEXSectionLabel("Tiempo estimado según la salida")
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
                .padding(12)
                .background(NEXColor.surfaceHigh.opacity(0.6), in: RoundedRectangle(cornerRadius: NEXMetric.radius, style: .continuous))
                .transition(NEXMotion.rise)
            }
        }

        if let parking {
            VStack(alignment: .leading, spacing: 8) {
                NEXSectionLabel("Aparcamientos cerca del destino")
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
            .padding(12)
                .background(NEXColor.surfaceHigh.opacity(0.6), in: RoundedRectangle(cornerRadius: NEXMetric.radius, style: .continuous))
                .transition(NEXMotion.rise)
        } else {
            Button {
                Task { await loadParking() }
            } label: {
                if isLoadingParking {
                    NEXLoader(size: 22)
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
            if let first = found.first { NEXMotion.animate(NEXMotion.panel) { camera = .rect(first.polyline.cameraRect) } }
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
