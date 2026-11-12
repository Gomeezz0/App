import MapKit
import NEXCore
import SwiftUI

/// Avisos sobre el mapa: distintivo en los puntuales y círculo en las zonas aproximadas.
struct AlertMarkers: MapContent {
    let alerts: [CommunityAlert]
    let onSelect: (CommunityAlert) -> Void

    var body: some MapContent {
        ForEach(alerts.filter(\.approximate)) { alert in
            MapCircle(center: alert.coordinate.cl, radius: alert.zoneRadiusM ?? 1000)
                .foregroundStyle(alert.type.color.opacity(0.14))
                .stroke(alert.type.color.opacity(0.6), lineWidth: 1.5)
        }
        ForEach(alerts) { alert in
            Annotation(alert.type.title, coordinate: alert.coordinate.cl, anchor: .center) {
                Button {
                    onSelect(alert)
                } label: {
                    AlertBadge(type: alert.type, level: alert.isOfficial ? .high : alert.level)
                }
            }
            .annotationTitles(.hidden)
        }
    }
}

/// Trazado de una ruta con borde oscuro para que se lea sobre cualquier fondo.
struct RouteLine: MapContent {
    let route: Route
    var selected = true

    var body: some MapContent {
        let coordinates = route.polyline.points.map(\.cl)
        MapPolyline(coordinates: coordinates)
            .stroke(.black.opacity(selected ? 0.55 : 0.3), style: StrokeStyle(lineWidth: selected ? 10 : 7, lineCap: .round, lineJoin: .round))
        MapPolyline(coordinates: coordinates)
            .stroke(selected ? NEXColor.red : Color.gray, style: StrokeStyle(lineWidth: selected ? 6 : 4, lineCap: .round, lineJoin: .round))
    }
}

extension View {
    /// Estilo de mapa de NEX: sobrio, sin puntos de interés, con tráfico opcional y modo noche.
    func nexMapStyle(traffic: Bool, night: Bool) -> some View {
        self.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: traffic))
            .environment(\.colorScheme, night ? .dark : .light)
    }
}

extension Polyline {
    /// Encuadre de cámara que contiene toda la polilínea con margen.
    var cameraRect: MKMapRect {
        let coordinates = points.map(\.cl)
        let rect = MKPolyline(coordinates: coordinates, count: coordinates.count).boundingMapRect
        return rect.insetBy(dx: -rect.width * 0.25, dy: -rect.height * 0.45)
    }
}
