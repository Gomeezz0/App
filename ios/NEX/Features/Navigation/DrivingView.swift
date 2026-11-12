import MapKit
import NEXCore
import SwiftUI

extension ManeuverKind {
    var symbol: String {
        switch self {
        case .straight: return "arrow.up"
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .slightLeft: return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .uTurn: return "arrow.uturn.left"
        case .roundabout: return "arrow.triangle.2.circlepath"
        case .arrive: return "flag.checkered"
        }
    }
}

/// Navegación activa. El mapa manda; encima solo la maniobra, el aviso más cercano,
/// la llegada y tres botones grandes.
struct DrivingView: View {
    let onReport: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var cameraHeading = 0.0
    @State private var following = true
    @State private var confirmEnd = false
    @State private var voteError: String?
    @State private var muted = false
    /// Fracción de la ruta ya dibujada (animación al iniciar).
    @State private var drawn = 0.0

    private var nav: NavigationSession { model.navigation }

    var body: some View {
        Map(position: $camera) {
            if model.mapIsNight { MapShade() }
            if let route = nav.route {
                let travelled = nav.progress?.distanceTravelled ?? 0
                // Lo ya recorrido se apaga; lo que queda, en rojo.
                RouteLine(route: route, from: 0, to: travelled, selected: false)
                RouteLine(route: route, from: travelled, to: travelled + (route.polyline.length - travelled) * drawn)
            }
            AlertMarkers(alerts: nav.alertsAhead.map(\.alert)) { _ in }
            if let destination = nav.destination {
                Annotation(destination.name, coordinate: destination.coordinate.cl, anchor: .center) { DestinationPin() }
            }
            if let progress = nav.progress {
                Annotation("Tu posición", coordinate: progress.snapped.cl, anchor: .center) {
                    VehiclePuck()
                        .rotationEffect(.degrees(progress.snappedBearing - cameraHeading))
                }
                .annotationTitles(.hidden)
            } else {
                UserAnnotation { _ in VehiclePuck(showsHeading: false, size: 30) }
            }
        }
        .nexMapStyle(traffic: model.settings.showTraffic, night: model.mapIsNight)
        .mapControls {}
        .onMapCameraChange(frequency: .onEnd) { context in cameraHeading = context.camera.heading }
        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in following = false })
        .overlay { MapScrim(edge: .top, height: 170) }
        .safeAreaInset(edge: .top) { top }
        .safeAreaInset(edge: .bottom) { bottom }
        .onAppear {
            if let progress = nav.progress { follow(progress, animated: false) }
            drawRoute()
        }
        .onChange(of: nav.progress) { _, progress in
            guard following, let progress else { return }
            follow(progress)
        }
        // Tras un recálculo, la ruta nueva vuelve a trazarse.
        .onChange(of: nav.route?.id) { _, _ in drawRoute() }
        .confirmationDialog("¿Terminar la navegación?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Terminar", role: .destructive) { model.stopNavigation() }
            Button("Seguir", role: .cancel) {}
        }
    }

    private func drawRoute() {
        guard !reduceMotion, !model.isConstrained else {
            drawn = 1
            return
        }
        drawn = 0
        Task {
            // Unos pocos pasos bastan: el trazo avanza en menos de un segundo.
            for step in 1...12 {
                try? await Task.sleep(for: .milliseconds(55))
                drawn = Double(step) / 12
            }
        }
    }

    private func follow(_ progress: RouteProgress, animated: Bool = true) {
        // Cuanto más rápido, más lejos mira la cámara.
        let distance = min(1400, max(450, 450 + nav.speed * 28))
        let target = MapCameraPosition.camera(
            MapCamera(centerCoordinate: progress.snapped.cl, distance: distance, heading: progress.snappedBearing, pitch: 55))
        if !animated || model.isConstrained || reduceMotion {
            camera = target
        } else {
            withAnimation(.linear(duration: 1)) { camera = target }
        }
        cameraHeading = progress.snappedBearing
    }

    // MARK: - Parte superior

    private var top: some View {
        VStack(spacing: 8) {
            maneuver
            if let ahead = nav.alertsAhead.first, ahead.distance <= AlertMonitor.warningDistance(speed: nav.speed) * 2 {
                alertBanner(ahead)
            }
            if let message = nav.rerouteError ?? voteError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.nexCaption)
                    .foregroundStyle(NEXColor.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .nexPanel(radius: 16)
                    .transition(NEXMotion.rise)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .nexAnimation(NEXMotion.panel, value: nav.alertsAhead.first?.id)
        .nexAnimation(value: nav.phase)
        .nexAppear()
    }

    private var maneuverSymbol: String {
        switch nav.phase {
        case .arrived: return "flag.checkered"
        case .rerouting: return "arrow.triangle.2.circlepath"
        default:
            guard let index = nav.progress?.stepIndex, let route = nav.route else { return "location.north.fill" }
            return ManeuverKind(instruction: route.steps[index].instruction).symbol
        }
    }

    private var maneuver: some View {
        let progress = nav.progress
        return HStack(spacing: 16) {
            Image(systemName: maneuverSymbol)
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(NEXColor.redGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(NEXColor.edge, lineWidth: 1))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                switch nav.phase {
                case .arrived:
                    Text("Has llegado").font(.nexNumber(34)).foregroundStyle(NEXColor.text)
                    Text(nav.destination?.name ?? "Tu destino").font(.nexHeadline).foregroundStyle(NEXColor.textDim).lineLimit(1)
                case .rerouting:
                    Text("Recalculando").font(.nexNumber(30)).foregroundStyle(NEXColor.text)
                    Text("Buscando la mejor ruta desde aquí").font(.nexHeadline).foregroundStyle(NEXColor.textDim)
                default:
                    if let progress, let index = progress.stepIndex, let route = nav.route {
                        Text(NEXFormat.distance(progress.distanceToManeuver))
                            .font(.nexNumber(42))
                            .foregroundStyle(NEXColor.text)
                            .contentTransition(.numericText())
                        Text(route.steps[index].instruction)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(NEXColor.text.opacity(0.86))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text(progress == nil ? "Buscando señal GPS…" : "Sigue la ruta")
                            .font(.nexTitle).foregroundStyle(NEXColor.text)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .nexPanel(radius: 28)
        .accessibilityElement(children: .combine)
    }

    private func alertBanner(_ ahead: AlertAhead) -> some View {
        let alert = ahead.alert
        // Se puede valorar un aviso ajeno cuando ya se está junto a él.
        let canVote = model.isSignedIn && !alert.mine && !alert.isOfficial && alert.myVote == nil && ahead.distance < 300
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                AlertBadge(type: alert.type, level: alert.isOfficial ? .high : alert.level, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.displayTitle).font(.nexHeadline).foregroundStyle(NEXColor.text)
                    Text(detail(for: alert)).font(.nexCaption).foregroundStyle(NEXColor.textDim)
                }
                Spacer()
                if !alert.approximate || ahead.distance > 0 {
                    Text(NEXFormat.distance(ahead.distance))
                        .font(.nexNumber(24))
                        .foregroundStyle(NEXColor.text)
                        .contentTransition(.numericText())
                }
            }
            if canVote {
                HStack(spacing: 10) {
                    voteButton("Sigue ahí", "hand.thumbsup.fill", .confirm, alert)
                    voteButton("Ya no está", "hand.thumbsdown.fill", .deny, alert)
                }
            }
        }
        .padding(12)
        .nexPanel(radius: 22)
        .transition(NEXMotion.slide(from: .top))
    }

    private func detail(for alert: CommunityAlert) -> String {
        if alert.isOfficial { return "Dato oficial" }
        if alert.approximate { return "Respeta los límites de velocidad" }
        let confirmed = alert.confirmations == 1 ? "1 confirmación" : "\(alert.confirmations) confirmaciones"
        return "\(alert.level.title) · \(confirmed)"
    }

    private func voteButton(_ title: String, _ symbol: String, _ vote: AlertVote, _ alert: CommunityAlert) -> some View {
        Button {
            Task {
                do {
                    try await model.vote(vote, on: alert)
                    voteError = nil
                } catch {
                    voteError = error.localizedDescription
                }
            }
        } label: {
            Label(title, systemImage: symbol)
                .font(.nexHeadline)
                .foregroundStyle(NEXColor.text)
                .frame(maxWidth: .infinity, minHeight: NEXMetric.driveTarget)
                .background(NEXColor.surfaceHigh, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(NEXRowButtonStyle())
    }

    // MARK: - Parte inferior

    private var bottom: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom) {
                speedometer
                Spacer()
                VStack(spacing: 10) {
                    if !following {
                        MapButton(systemImage: "location.north.line.fill", label: "Volver a centrar", prominent: true, size: 56) {
                            following = true
                            if let progress = nav.progress { follow(progress) }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    MapButton(
                        systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: muted ? "Activar la voz" : "Silenciar la voz", size: 56
                    ) {
                        muted.toggle()
                        model.speech.isMuted = muted
                    }
                }
            }
            .padding(.horizontal, 12)
            .nexAnimation(value: following)

            VStack(spacing: 12) {
                tripProgress
                HStack(spacing: 12) {
                    driveButton("xmark", "Terminar navegación", prominent: false) {
                        if nav.phase == .arrived { model.stopNavigation() } else { confirmEnd = true }
                    }
                    summary
                    driveButton("plus.bubble.fill", "Avisar de una incidencia", prominent: true, action: onReport)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .nexPanel(radius: 30)
            .padding(.horizontal, 8)
        }
        .nexAppear(delay: 0.08)
    }

    /// Barra fina con la parte del viaje ya recorrida.
    private var tripProgress: some View {
        let fraction: Double = {
            guard let progress = nav.progress else { return 0 }
            let total = progress.distanceTravelled + progress.distanceRemaining
            return total > 0 ? progress.distanceTravelled / total : 0
        }()
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(NEXColor.mid)
                Capsule().fill(NEXColor.red).frame(width: max(4, geometry.size.width * fraction))
            }
        }
        .frame(height: 4)
        .nexAnimation(.linear(duration: 1), value: fraction)
        .accessibilityHidden(true)
    }

    private var speedometer: some View {
        VStack(spacing: -2) {
            Text("\(NEXFormat.kmh(nav.speed))")
                .font(.nexNumber(28))
                .foregroundStyle(NEXColor.text)
                .contentTransition(.numericText())
            Text("km/h").font(.system(size: 11, weight: .semibold)).foregroundStyle(NEXColor.textDim)
        }
        .frame(width: 74, height: 74)
        .nexPanel(radius: 37)
        .nexAnimation(NEXMotion.quick, value: NEXFormat.kmh(nav.speed))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Velocidad \(NEXFormat.kmh(nav.speed)) kilómetros por hora")
    }

    private var summary: some View {
        VStack(spacing: 2) {
            if let progress = nav.progress, nav.phase != .arrived {
                Text(Date().addingTimeInterval(progress.timeRemaining).formatted(date: .omitted, time: .shortened))
                    .font(.nexNumber(32))
                    .foregroundStyle(NEXColor.text)
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Text(NEXFormat.duration(progress.timeRemaining)).foregroundStyle(NEXColor.text)
                    Text("·").foregroundStyle(NEXColor.mid)
                    Text(NEXFormat.distance(progress.distanceRemaining)).foregroundStyle(NEXColor.textDim)
                }
                .font(.nexCaption)
            } else if nav.phase == .arrived {
                Text("Fin del viaje").font(.nexHeadline).foregroundStyle(NEXColor.text)
            } else if let route = nav.route {
                Text(NEXFormat.duration(route.expectedTravelTime)).font(.nexNumber(32)).foregroundStyle(NEXColor.text)
                Text(NEXFormat.distance(route.distance)).font(.nexCaption).foregroundStyle(NEXColor.textDim)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func driveButton(_ symbol: String, _ label: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: NEXMetric.driveTarget, height: NEXMetric.driveTarget)
                .background(prominent ? AnyShapeStyle(NEXColor.redGradient) : AnyShapeStyle(NEXColor.mid), in: Circle())
                .overlay(Circle().strokeBorder(NEXColor.edge, lineWidth: 1))
        }
        .buttonStyle(NEXRowButtonStyle())
        .accessibilityLabel(label)
    }
}
