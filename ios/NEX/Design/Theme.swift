import NEXCore
import SwiftUI
import UIKit

// MARK: - Color

/// Paleta de NEX: negro profundo, antracita y rojo. Sin tonos azulados.
/// El rojo se reserva para la acción principal, la ruta y el peligro.
enum NEXColor {
    /// #090A0D — fondo.
    static let black = Color(red: 0.035, green: 0.039, blue: 0.051)
    /// #191B20 — superficies y paneles.
    static let surface = Color(red: 0.098, green: 0.106, blue: 0.125)
    /// #23252B — campos y superficies elevadas sobre un panel.
    static let surfaceHigh = Color(red: 0.137, green: 0.145, blue: 0.169)
    /// #34363D — gris medio: bordes marcados, pistas, elementos inactivos.
    static let mid = Color(red: 0.204, green: 0.212, blue: 0.239)
    static let stroke = Color.white.opacity(0.07)
    /// #F32635 — acción, ruta y alertas graves.
    static let red = Color(red: 0.953, green: 0.149, blue: 0.208)
    static let redDeep = Color(red: 0.72, green: 0.07, blue: 0.13)
    /// #F5F5F7 — texto principal.
    static let text = Color(red: 0.961, green: 0.961, blue: 0.969)
    /// #A5A7AE — texto secundario.
    static let textDim = Color(red: 0.647, green: 0.655, blue: 0.682)
    // Semánticos: solo para estado (precaución, correcto, tráfico).
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.20)
    static let orange = Color(red: 1.0, green: 0.48, blue: 0.18)
    static let green = Color(red: 0.27, green: 0.82, blue: 0.50)

    /// Degradado del botón principal.
    static let redGradient = LinearGradient(colors: [red, redDeep], startPoint: .top, endPoint: .bottom)
    /// Brillo sutil del borde superior de paneles y tarjetas.
    static let edge = LinearGradient(
        colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom)
}

enum NEXMetric {
    static let radius: CGFloat = 20
    static let radiusSmall: CGFloat = 14
    static let padding: CGFloat = 16
    /// Objetivo táctil mínimo durante la conducción.
    static let driveTarget: CGFloat = 64
}

// MARK: - Tipografía

/// Sistema tipográfico: SF Pro (la fuente del sistema, que pasa sola a SF Pro Display en
/// tamaños grandes), con variante ancha para la marca y redondeada para las cifras.
/// Seis estilos y nada más.
extension Font {
    /// Marca y grandes titulares.
    static let nexDisplay = Font.system(size: 34, weight: .heavy).width(.expanded)
    static let nexTitle = Font.system(size: 24, weight: .bold)
    static let nexHeadline = Font.system(size: 17, weight: .semibold)
    static let nexBody = Font.system(size: 16, weight: .regular)
    static let nexCaption = Font.system(size: 13, weight: .medium)
    /// Etiquetas de sección, en mayúsculas.
    static let nexLabel = Font.system(size: 11, weight: .bold).width(.expanded)
    /// Cifras (ETA, velocidad, distancias).
    static func nexNumber(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

/// Etiqueta de sección en mayúsculas.
struct NEXSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.nexLabel)
            .kerning(1.2)
            .foregroundStyle(NEXColor.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Movimiento

/// Curvas de animación de NEX: rápidas y sin rebote. Con «Reducir movimiento» activado
/// en el sistema, los desplazamientos se sustituyen por un fundido breve o se omiten.
enum NEXMotion {
    static let quick = Animation.easeOut(duration: 0.16)
    static let standard = Animation.smooth(duration: 0.30)
    static let panel = Animation.snappy(duration: 0.36, extraBounce: 0)

    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// `withAnimation` que respeta «Reducir movimiento».
    static func animate(_ animation: Animation = standard, _ changes: () -> Void) {
        if reduced {
            withAnimation(.easeOut(duration: 0.12), changes)
        } else {
            withAnimation(animation, changes)
        }
    }

    /// Transición de un panel que entra desde un borde (solo fundido si se reduce el movimiento).
    static func slide(from edge: Edge) -> AnyTransition {
        reduced ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    static var rise: AnyTransition {
        reduced ? .opacity : .offset(y: 14).combined(with: .opacity)
    }
}

private struct MotionAwareAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .easeOut(duration: 0.12) : animation, value: value)
    }
}

/// Aparición escalonada: el contenido sube unos puntos y se funde al mostrarse.
private struct AppearModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.smooth(duration: 0.45).delay(reduceMotion ? 0 : delay)) { shown = true }
            }
    }
}

extension View {
    func nexAnimation<Value: Equatable>(_ animation: Animation = NEXMotion.standard, value: Value) -> some View {
        modifier(MotionAwareAnimation(animation: animation, value: value))
    }

    func nexAppear(delay: Double = 0) -> some View {
        modifier(AppearModifier(delay: delay))
    }
}

// MARK: - Botones

/// Respuesta al pulsar común a todos los botones: se hunden un poco y se atenúan.
private struct PressEffect: ViewModifier {
    let pressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.97 : 1)
            .brightness(pressed ? -0.06 : 0)
            .animation(NEXMotion.quick, value: pressed)
    }
}

struct NEXPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: NEXMetric.radius, style: .continuous)
        configuration.label
            .font(.nexHeadline)
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(isEnabled ? AnyShapeStyle(NEXColor.redGradient) : AnyShapeStyle(NEXColor.mid), in: shape)
            .overlay(shape.strokeBorder(NEXColor.edge, lineWidth: 1))
            .shadow(color: NEXColor.red.opacity(isEnabled ? 0.32 : 0), radius: 14, y: 6)
            .modifier(PressEffect(pressed: configuration.isPressed))
            .animation(NEXMotion.standard, value: isEnabled)
    }
}

struct NEXSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: NEXMetric.radius, style: .continuous)
        configuration.label
            .font(.nexHeadline)
            .foregroundStyle(NEXColor.text)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(NEXColor.surfaceHigh, in: shape)
            .overlay(shape.strokeBorder(NEXColor.edge, lineWidth: 1))
            .modifier(PressEffect(pressed: configuration.isPressed))
    }
}

/// Estilo para filas y tarjetas pulsables: solo la respuesta al toque.
struct NEXRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .modifier(PressEffect(pressed: configuration.isPressed))
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
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(prominent ? .white : NEXColor.text)
                .frame(width: size, height: size)
                .background {
                    if prominent {
                        Circle().fill(NEXColor.redGradient)
                    } else {
                        Circle().fill(NEXColor.surface.opacity(0.92))
                    }
                }
                .overlay(Circle().strokeBorder(NEXColor.edge, lineWidth: 1))
                .shadow(color: (prominent ? NEXColor.red : Color.black).opacity(0.4), radius: 12, y: 5)
        }
        .buttonStyle(NEXRowButtonStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Superficies

extension View {
    /// Tarjeta antracita con borde luminoso fino.
    func nexCard(padding: CGFloat = NEXMetric.padding, radius: CGFloat = NEXMetric.radius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self.padding(padding)
            .background(NEXColor.surface, in: shape)
            .overlay(shape.strokeBorder(NEXColor.edge, lineWidth: 1))
    }

    /// Panel flotante sobre el mapa: antracita translúcido con desenfoque, borde y sombra.
    func nexPanel(radius: CGFloat = 26) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background {
                shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                shape.fill(NEXColor.black.opacity(0.72))
            }
            .overlay(shape.strokeBorder(NEXColor.edge, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
    }

    /// Fondo y barra de navegación de las pantallas secundarias.
    func nexScreen(_ title: String) -> some View {
        self.scrollContentBackground(.hidden)
            .background(NEXColor.black.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NEXColor.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(NEXColor.red)
    }
}

/// Icono dentro de un cuadrado redondeado: la pieza común de menús, listas y resultados.
struct NEXIconTile: View {
    let systemImage: String
    var tint: Color = NEXColor.text
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(NEXColor.surfaceHigh, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(NEXColor.stroke))
    }
}

/// Campo de texto de NEX (búsqueda, formularios).
struct NEXField<Content: View>: View {
    var systemImage: String?
    var focused = false
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: NEXMetric.radiusSmall + 2, style: .continuous)
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(focused ? NEXColor.red : NEXColor.textDim)
                    .frame(width: 22)
            }
            content
                .font(.nexHeadline)
                .foregroundStyle(NEXColor.text)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background(NEXColor.surfaceHigh, in: shape)
        .overlay(shape.strokeBorder(focused ? NEXColor.red.opacity(0.7) : NEXColor.stroke, lineWidth: focused ? 1.5 : 1))
        .nexAnimation(NEXMotion.quick, value: focused)
    }
}

// MARK: - Carga y estados vacíos

/// Indicador de carga de NEX: un arco rojo que gira sobre una pista gris.
struct NEXLoader: View {
    var size: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle().stroke(NEXColor.mid, lineWidth: size * 0.12)
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(NEXColor.red, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: reduceMotion ? 1.8 : 0.9).repeatForever(autoreverses: false)) { spinning = true }
        }
        .accessibilityLabel("Cargando")
    }
}

/// Mensaje de estado vacío o de función no disponible.
struct NEXNotice: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(NEXColor.textDim)
                .frame(width: 64, height: 64)
                .background(NEXColor.surfaceHigh, in: Circle())
                .overlay(Circle().strokeBorder(NEXColor.edge, lineWidth: 1))
            Text(title).font(.nexHeadline).foregroundStyle(NEXColor.text)
            Text(message).font(.nexBody).foregroundStyle(NEXColor.textDim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .nexAppear()
    }
}

// MARK: - Marca

/// Logotipo: dos barras y una diagonal roja que las une, como una ruta entre dos puntos.
struct NEXLogo: View {
    var size: CGFloat = 72
    /// Fracción dibujada de la diagonal (para animar el trazo).
    var progress: CGFloat = 1

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
            diagonal.addLine(to: CGPoint(x: left + (right - left) * progress, y: top + (bottom - top) * progress))
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

    /// Tres familias: control (blanco frío), grave (rojo) y precaución (ámbar / naranja).
    var color: Color {
        switch self {
        case .police, .speedCamera: return NEXColor.text
        case .accident, .roadClosed: return NEXColor.red
        case .trafficJam, .roadworks, .stoppedVehicle: return NEXColor.amber
        case .roadObject, .hazard, .weather: return NEXColor.orange
        }
    }

    /// Color del símbolo sobre el fondo del distintivo.
    var symbolColor: Color {
        switch self {
        case .accident, .roadClosed: return .white
        default: return NEXColor.black
        }
    }
}

/// Distintivo de aviso: rombo redondeado propio de NEX. Los avisos sin verificar se ven huecos.
struct AlertBadge: View {
    let type: AlertType
    var level: ConfidenceLevel = .high
    var size: CGFloat = 36

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        let hollow = level == .low
        ZStack {
            shape
                .fill(hollow ? NEXColor.surface : type.color)
                .overlay(shape.strokeBorder(hollow ? type.color : NEXColor.black.opacity(0.75), lineWidth: 2))
                .rotationEffect(.degrees(45))
                .frame(width: size * 0.76, height: size * 0.76)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            Image(systemName: type.symbol)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(hollow ? type.color : type.symbolColor)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(type.title), \(level.title.lowercased())")
    }
}

/// Píldora pequeña de estado (nivel de confianza, peaje, etc.).
struct NEXTag: View {
    let text: String
    var color: Color = NEXColor.textDim

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}
