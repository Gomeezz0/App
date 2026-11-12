import NEXCore
import SwiftUI

/// Sistema de diseño de NEX: negro profundo, antracita para superficies y rojo solo para la acción.
enum NEXColor {
    static let black = Color(red: 0.031, green: 0.031, blue: 0.039)
    static let surface = Color(red: 0.090, green: 0.094, blue: 0.106)
    static let surfaceHigh = Color(red: 0.137, green: 0.141, blue: 0.157)
    static let stroke = Color.white.opacity(0.08)
    static let red = Color(red: 0.882, green: 0.071, blue: 0.137)
    static let text = Color(red: 0.961, green: 0.961, blue: 0.969)
    static let textDim = Color(red: 0.663, green: 0.678, blue: 0.710)
    static let amber = Color(red: 1.0, green: 0.71, blue: 0.16)
    static let green = Color(red: 0.25, green: 0.80, blue: 0.47)
}

enum NEXMetric {
    static let radius: CGFloat = 18
    static let padding: CGFloat = 16
    /// Objetivo táctil mínimo durante la conducción.
    static let driveTarget: CGFloat = 64
}

extension Font {
    /// Cifras grandes (ETA, velocidad, distancia a la maniobra).
    static func nexNumber(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static let nexTitle = Font.system(size: 28, weight: .bold)
    static let nexHeadline = Font.system(size: 17, weight: .semibold)
    static let nexBody = Font.system(size: 16, weight: .regular)
    static let nexCaption = Font.system(size: 13, weight: .medium)
}

// MARK: - Botones

struct NEXPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nexHeadline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(NEXColor.red.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: NEXMetric.radius))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct NEXSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nexHeadline)
            .foregroundStyle(NEXColor.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(NEXColor.surfaceHigh, in: RoundedRectangle(cornerRadius: NEXMetric.radius))
            .overlay(RoundedRectangle(cornerRadius: NEXMetric.radius).stroke(NEXColor.stroke))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Botón redondo que flota sobre el mapa.
struct MapButton: View {
    let systemImage: String
    let label: String
    var prominent = false
    var size: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(prominent ? .white : NEXColor.text)
                .frame(width: size, height: size)
                .background(prominent ? NEXColor.red : NEXColor.surface, in: Circle())
                .overlay(Circle().stroke(NEXColor.stroke))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Superficies

extension View {
    /// Panel antracita con borde fino.
    func nexCard(padding: CGFloat = NEXMetric.padding) -> some View {
        self.padding(padding)
            .background(NEXColor.surface, in: RoundedRectangle(cornerRadius: NEXMetric.radius))
            .overlay(RoundedRectangle(cornerRadius: NEXMetric.radius).stroke(NEXColor.stroke))
    }

    /// Fondo y barra de navegación de las pantallas secundarias.
    func nexScreen(_ title: String) -> some View {
        self.scrollContentBackground(.hidden)
            .background(NEXColor.black.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NEXColor.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(NEXColor.red)
    }
}

// MARK: - Marca

/// Logotipo: dos barras y una diagonal roja que las une, como una ruta entre dos puntos.
struct NEXLogo: View {
    var size: CGFloat = 72

    var body: some View {
        Canvas { context, canvas in
            let bar = canvas.width * 0.2
            let style = StrokeStyle(lineWidth: bar, lineCap: .round)
            let left = bar / 2, right = canvas.width - bar / 2
            let top = bar / 2, bottom = canvas.height - bar / 2

            var bars = Path()
            bars.move(to: CGPoint(x: left, y: top))
            bars.addLine(to: CGPoint(x: left, y: bottom))
            bars.move(to: CGPoint(x: right, y: top))
            bars.addLine(to: CGPoint(x: right, y: bottom))
            context.stroke(bars, with: .color(NEXColor.text), style: style)

            var diagonal = Path()
            diagonal.move(to: CGPoint(x: left, y: top))
            diagonal.addLine(to: CGPoint(x: right, y: bottom))
            context.stroke(diagonal, with: .color(NEXColor.red), style: style)
        }
        .frame(width: size * 0.92, height: size)
        .accessibilityLabel("NEX")
    }
}

// MARK: - Avisos

extension AlertType {
    var symbol: String {
        switch self {
        case .police: return "shield.lefthalf.filled"
        case .speedCamera: return "camera.fill"
        case .accident: return "car.side.rear.and.collision.and.car.side.front"
        case .trafficJam: return "car.2.fill"
        case .stoppedVehicle: return "car.side.fill"
        case .roadObject: return "shippingbox.fill"
        case .roadworks: return "cone.fill"
        case .roadClosed: return "xmark.octagon.fill"
        case .weather: return "cloud.heavyrain.fill"
        case .hazard: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .police, .speedCamera: return Color(red: 0.30, green: 0.56, blue: 1.0)
        case .accident, .roadClosed: return NEXColor.red
        case .trafficJam, .roadworks, .stoppedVehicle: return NEXColor.amber
        case .roadObject, .hazard, .weather: return Color(red: 1.0, green: 0.52, blue: 0.20)
        }
    }
}

/// Distintivo de aviso: rombo redondeado propio de NEX. Los avisos sin verificar se ven huecos.
struct AlertBadge: View {
    let type: AlertType
    var level: ConfidenceLevel = .high
    var size: CGFloat = 36

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26)
        ZStack {
            shape
                .fill(level == .low ? NEXColor.surface : type.color)
                .overlay(shape.stroke(level == .low ? type.color : NEXColor.black.opacity(0.6), lineWidth: 2))
                .rotationEffect(.degrees(45))
                .frame(width: size * 0.78, height: size * 0.78)
            Image(systemName: type.symbol)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(level == .low ? type.color : .white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(type.title), \(level.title.lowercased())")
    }
}

/// Mensaje de estado vacío o de función no disponible.
struct NEXNotice: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(NEXColor.textDim)
            Text(title).font(.nexHeadline).foregroundStyle(NEXColor.text)
            Text(message).font(.nexBody).foregroundStyle(NEXColor.textDim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}
