import MapKit
import NEXCore
import SwiftUI

/// Navegación activa. Solo lo esencial: maniobra, aviso más cercano, llegada y tres botones grandes.
struct DrivingView: View {
    let onReport: () -> Void

    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var following = true
    @State private var confirmEnd = false
    @State private var voteError: String?

    private var nav: NavigationSession { model.navigation }

    var body: some View {
        Map(position: $camera) {
            if let route = nav.route { RouteLine(route: route) }
            UserAnnotation()
            AlertMarkers(alerts: nav.alertsAhead.map(\.alert)) { _ in }
            if let destination = nav.destination {
                Marker(destination.name, systemImage: "flag.checkered", coordinate: destination.coordinate.cl)
                    .tint(NEXColor.red)
            }
        }
        .nexMapStyle(traffic: model.settings.showTraffic, night: model.mapIsNight)
        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in following = false })
        .safeAreaInset(edge: .top) { top }
        .safeAreaInset(edge: .bottom) { bottom }
        .onChange(of: nav.progress) { _, progress in
            guard following, let progress else { return }
            follow(progress)
        }
        .confirmationDialog("¿Terminar la navegación?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Terminar", role: .destructive) { model.stopNavigation() }
            Button("Seguir", role: .cancel) {}
        }
    }

    private func follow(_ progress: RouteProgress) {
        // Cuanto más rápido, más lejos mira la cámara.
        let distance = min(1400, max(450, 450 + nav.speed * 28))
        let target = MapCameraPosition.camera(
            MapCamera(centerCoordinate: progress.snapped.cl, distance: distance, heading: progress.snappedBearing, pitch: 55))
        if model.isConstrained {
            camera = target
        } else {
            withAnimation(.linear(duration: 1)) { camera = target }
        }
    }

    // MARK: - Parte superior

    private var top: some View {
        VStack(spacing: 8) {
            maneuver
            if let ahead = nav.alertsAhead.first, ahead.distance <= AlertMonitor.warningDistance(speed: nav.speed) * 2 {
                alertBanner(ahead)
            }
            if let message = nav.rerouteError ?? voteError {
                Text(message)
                    .font(.nexCaption)
                    .foregroundStyle(NEXColor.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nexCard(padding: 10)
            }
        }
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.25), value: nav.alertsAhead.first?.id)
    }

    @ViewBuilder private var maneuver: some View {
        let progress = nav.progress
        HStack(spacing: 14) {
            switch nav.phase {
            case .arrived:
                Image(systemName: "flag.checkered").font(.system(size: 34, weight: .bold)).foregroundStyle(NEXColor.red)
                Text("Has llegado a \(nav.destination?.name ?? "tu destino")").font(.nexTitle).foregroundStyle(NEXColor.text)
            case .rerouting:
                ProgressView().tint(NEXColor.red).scaleEffect(1.4).frame(width: 40)
                Text("Recalculando ruta…").font(.nexTitle).foregroundStyle(NEXColor.text)
            default:
                if let progress, let index = progress.stepIndex, let route = nav.route {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NEXFormat.distance(progress.distanceToManeuver))
                            .font(.nexNumber(40))
                            .foregroundStyle(NEXColor.text)
                            .contentTransition(.numericText())
                        Text(route.steps[index].instruction)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(NEXColor.textDim)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                } else {
                    Image(systemName: "location.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(NEXColor.red)
                    Text(progress == nil ? "Buscando señal GPS…" : "Sigue la ruta")
                        .font(.nexTitle).foregroundStyle(NEXColor.text)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(16)
        .background(NEXColor.black, in: RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(NEXColor.red).frame(width: 5).padding(.vertical, 16).padding(.leading, 5)
        }
        .accessibilityElement(children: .combine)
    }

    private func alertBanner(_ ahead: AlertAhead) -> some View {
        let alert = ahead.alert
        // Se puede valorar un aviso ajeno cuando ya se está junto a él.
        let canVote = model.isSignedIn && !alert.mine && !alert.isOfficial && alert.myVote == nil && ahead.distance < 300
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                AlertBadge(type: alert.type, level: alert.isOfficial ? .high : alert.level, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.displayTitle)
                        .font(.nexHeadline).foregroundStyle(NEXColor.text)
                    Text(detail(for: alert)).font(.nexCaption).foregroundStyle(NEXColor.textDim)
                }
                Spacer()
                if !alert.approximate || ahead.distance > 0 {
                    Text(NEXFormat.distance(ahead.distance)).font(.nexNumber(22)).foregroundStyle(NEXColor.text)
                }
            }
            if canVote {
                HStack(spacing: 10) {
                    voteButton("Sigue ahí", "hand.thumbsup.fill", .confirm, alert)
                    voteButton("Ya no está", "hand.thumbsdown.fill", .deny, alert)
                }
            }
        }
        .nexCard(padding: 12)
        .transition(.move(edge: .top).combined(with: .opacity))
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
                .background(NEXColor.surfaceHigh, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Parte inferior

    private var bottom: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom) {
                speedometer
                Spacer()
                if !following {
                    MapButton(systemImage: "location.north.line.fill", label: "Volver a centrar", size: NEXMetric.driveTarget) {
                        following = true
                        if let progress = nav.progress { follow(progress) }
                    }
                }
            }
            .padding(.horizontal, 12)

            HStack(spacing: 12) {
                driveButton("xmark", "Terminar navegación", background: NEXColor.surfaceHigh) {
                    if nav.phase == .arrived { model.stopNavigation() } else { confirmEnd = true }
                }
                summary
                driveButton("plus.bubble.fill", "Avisar de una incidencia", background: NEXColor.red, action: onReport)
            }
            .padding(12)
            .background(NEXColor.black, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        }
    }

    private var speedometer: some View {
        VStack(spacing: -2) {
            Text("\(NEXFormat.kmh(nav.speed))").font(.nexNumber(26)).foregroundStyle(NEXColor.text)
            Text("km/h").font(.system(size: 11, weight: .semibold)).foregroundStyle(NEXColor.textDim)
        }
        .frame(width: 68, height: 68)
        .background(NEXColor.black, in: Circle())
        .overlay(Circle().stroke(NEXColor.stroke, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Velocidad \(NEXFormat.kmh(nav.speed)) kilómetros por hora")
    }

    private var summary: some View {
        VStack(spacing: 2) {
            if let progress = nav.progress, nav.phase != .arrived {
                Text(Date().addingTimeInterval(progress.timeRemaining).formatted(date: .omitted, time: .shortened))
                    .font(.nexNumber(30))
                    .foregroundStyle(NEXColor.text)
                Text("\(NEXFormat.duration(progress.timeRemaining)) · \(NEXFormat.distance(progress.distanceRemaining))")
                    .font(.nexCaption)
                    .foregroundStyle(NEXColor.textDim)
            } else if nav.phase == .arrived {
                Text("Fin del viaje").font(.nexHeadline).foregroundStyle(NEXColor.text)
            } else if let route = nav.route {
                Text(NEXFormat.duration(route.expectedTravelTime)).font(.nexNumber(30)).foregroundStyle(NEXColor.text)
                Text(NEXFormat.distance(route.distance)).font(.nexCaption).foregroundStyle(NEXColor.textDim)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func driveButton(_ symbol: String, _ label: String, background: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: NEXMetric.driveTarget, height: NEXMetric.driveTarget)
                .background(background, in: Circle())
        }
        .accessibilityLabel(label)
    }
}
