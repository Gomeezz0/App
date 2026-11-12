import MapKit
import NEXCore
import SwiftUI

// MARK: - Posición del vehículo

/// Indicador de posición de NEX: punta de flecha roja sobre un disco blanco frío,
/// con un halo que respira despacio. Sustituye al punto azul del sistema.
struct VehiclePuck: View {
    /// Flecha (en marcha) o punto (parado o en el mapa general).
    var showsHeading = true
    var size: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(NEXColor.red.opacity(0.22))
                .frame(width: size * 1.7, height: size * 1.7)
                .scaleEffect(pulse ? 1 : 0.62)
                .opacity(pulse ? 0 : 0.9)
            Circle()
                .fill(NEXColor.text)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.55), radius: 6, y: 3)
            if showsHeading {
                Image(systemName: "location.north.fill")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(NEXColor.red)
            } else {
                Circle().fill(NEXColor.red).frame(width: size * 0.52, height: size * 0.52)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityLabel("Tu posición")
    }
}

// MARK: - Avisos

/// Los distintivos aparecen creciendo un poco, sin rebote.
private struct PopIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.5)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.smooth(duration: 0.35)) { shown = true } }
    }
}

/// Avisos sobre el mapa: distintivo en los puntuales y círculo en las zonas aproximadas.
struct AlertMarkers: MapContent {
    let alerts: [CommunityAlert]
    let onSelect: (CommunityAlert) -> Void

    var body: some MapContent {
        ForEach(alerts.filter(\.approximate)) { alert in
            MapCircle(center: alert.coordinate.cl, radius: alert.zoneRadiusM ?? 1000)
                .foregroundStyle(alert.type.color.opacity(0.10))
                .stroke(alert.type.color.opacity(0.55), lineWidth: 1.5)
                .mapOverlayLevel(level: .aboveRoads)
        }
        ForEach(alerts) { alert in
            Annotation(alert.type.title, coordinate: alert.coordinate.cl, anchor: .center) {
                Button {
                    onSelect(alert)
                } label: {
                    AlertBadge(type: alert.type, level: alert.isOfficial ? .high : alert.level, size: 40)
                        .modifier(PopIn())
                }
                .buttonStyle(NEXRowButtonStyle())
            }
            .annotationTitles(.hidden)
        }
    }
}

// MARK: - Ruta

/// Trazado de una ruta: núcleo rojo con borde oscuro para que destaque sobre cualquier calle.
/// Las alternativas no seleccionadas se dibujan en gris medio.
struct RouteLine: MapContent {
    let coordinates: [CLLocationCoordinate2D]
    var selected = true

    init(route: Route, selected: Bool = true) {
        coordinates = route.polyline.points.map(\.cl)
        self.selected = selected
    }

    /// Tramo de la ruta entre dos distancias desde el inicio (para animar el trazado y
    /// para apagar lo ya recorrido).
    init(route: Route, from start: Double, to end: Double, selected: Bool = true) {
        let line = route.polyline
        guard line.segmentCount > 0, end > start else {
            coordinates = []
            self.selected = selected
            return
        }
        let first = line.segmentIndex(atDistance: max(0, start))
        let last = min(line.points.count - 1, line.segmentIndex(atDistance: min(line.length, end)) + 1)
        coordinates = first <= last ? line.points[first...last].map(\.cl) : []
        self.selected = selected
    }

    var body: some MapContent {
        if coordinates.count > 1 {
            MapPolyline(coordinates: coordinates)
                .stroke(
                    NEXColor.black.opacity(selected ? 0.9 : 0.6),
                    style: StrokeStyle(lineWidth: selected ? 11 : 8, lineCap: .round, lineJoin: .round))
                .mapOverlayLevel(level: .aboveRoads)
            MapPolyline(coordinates: coordinates)
                .stroke(
                    selected ? NEXColor.red : NEXColor.mid,
                    style: StrokeStyle(lineWidth: selected ? 6.5 : 4.5, lineCap: .round, lineJoin: .round))
                .mapOverlayLevel(level: .aboveRoads)
        }
    }
}

/// Marcador de destino con identidad NEX.
struct DestinationPin: View {
    var body: some View {
        ZStack {
            Circle().fill(NEXColor.black).frame(width: 40, height: 40)
            Circle().strokeBorder(NEXColor.red, lineWidth: 3).frame(width: 40, height: 40)
            Image(systemName: "flag.checkered")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(NEXColor.text)
        }
        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
        .modifier(PopIn())
        .accessibilityLabel("Destino")
    }
}

// MARK: - Estilo

/// Velo negro de NEX para el mapa oscuro de MapKit.
///
/// MapKit no permite cambiar los colores del mapa, pero sí dibujar capas en dos niveles:
/// encima de las calles o encima de los nombres. Este velo va **encima de las calles y debajo
/// de los nombres**, así que el fondo y las vías se oscurecen hacia el negro mientras los
/// nombres de calles y carreteras siguen nítidos. No dibuja ninguna calle: solo atenúa las reales.
struct MapShade: MapContent {
    var opacity = 0.52

    /// Rectángulo que cubre todo el mapa. Los puntos intermedios evitan que MapKit
    /// interprete el borde de ±180° como un polígono de anchura cero.
    private static let world: [CLLocationCoordinate2D] = {
        let lons: [Double] = [-179.9, -90, 0, 90, 179.9]
        return lons.map { CLLocationCoordinate2D(latitude: 85, longitude: $0) }
            + lons.reversed().map { CLLocationCoordinate2D(latitude: -85, longitude: $0) }
    }()

    var body: some MapContent {
        MapPolygon(coordinates: Self.world)
            .foregroundStyle(Color.black.opacity(opacity))
            .mapOverlayLevel(level: .aboveRoads)
    }
}

extension View {
    /// Estilo de mapa de NEX con lo que MapKit permite de forma nativa: oscuro, colores
    /// atenuados (sin el tinte del estilo normal), sin puntos de interés y con tráfico opcional.
    /// MapKit no admite definir colores de calles ni de autopistas; ver docs/DISENO.md.
    func nexMapStyle(traffic: Bool, night: Bool) -> some View {
        self.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: traffic))
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

/// Velo degradado que da profundidad al mapa bajo los controles flotantes.
struct MapScrim: View {
    let edge: VerticalEdge
    var height: CGFloat = 150

    var body: some View {
        LinearGradient(
            colors: [NEXColor.black.opacity(0.85), NEXColor.black.opacity(0)],
            startPoint: edge == .top ? .top : .bottom, endPoint: edge == .top ? .bottom : .top)
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
