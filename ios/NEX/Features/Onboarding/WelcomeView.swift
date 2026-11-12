import SwiftUI

/// Bienvenida: presenta NEX y pide el permiso de ubicación explicando para qué.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var logoProgress: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            NEXLogo(size: 88, progress: logoProgress)
                .shadow(color: NEXColor.red.opacity(0.35), radius: 24, y: 8)
                .onAppear {
                    if NEXMotion.reduced {
                        logoProgress = 1
                    } else {
                        withAnimation(.smooth(duration: 0.9).delay(0.15)) { logoProgress = 1 }
                    }
                }
            Text("NEX")
                .font(.system(size: 60, weight: .heavy).width(.expanded))
                .foregroundStyle(NEXColor.text)
                .padding(.top, 22)
                .nexAppear(delay: 0.15)
            Text("Navegación precisa.\nAvisos en los que puedes confiar.")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(NEXColor.textDim)
                .padding(.top, 8)
                .nexAppear(delay: 0.25)

            VStack(alignment: .leading, spacing: 14) {
                feature("location.north.fill", "Guía giro a giro con voz y tráfico en el tiempo estimado").nexAppear(delay: 0.40)
                feature("checkmark.shield.fill", "Avisos de la comunidad, ponderados por fiabilidad").nexAppear(delay: 0.48)
                feature("bolt.fill", "Sin publicidad y sin GPS en segundo plano fuera de un viaje").nexAppear(delay: 0.56)
            }
            .padding(.top, 34)
            Spacer()

            if model.location.isDenied {
                Text("El acceso a la ubicación está desactivado. Sin él, NEX no puede situarte ni guiarte.")
                    .font(.nexCaption)
                    .foregroundStyle(NEXColor.amber)
                    .padding(.bottom, 12)
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(NEXPrimaryButtonStyle())
                Button("Continuar sin ubicación") { model.settings.hasOnboarded = true }
                    .buttonStyle(NEXSecondaryButtonStyle())
                    .padding(.top, 10)
            } else {
                Text("NEX usa tu ubicación solo mientras la app está abierta o hay una navegación en curso.")
                    .font(.nexCaption)
                    .foregroundStyle(NEXColor.textDim)
                    .padding(.bottom, 12)
                Button(model.location.isAuthorized ? "Empezar" : "Permitir ubicación y empezar") {
                    if model.location.isAuthorized {
                        finish()
                    } else {
                        model.location.requestPermission()
                    }
                }
                .buttonStyle(NEXPrimaryButtonStyle())
            }
        }
        .padding(24)
        .background {
            ZStack {
                NEXColor.black
                // Resplandor rojo muy tenue en la esquina: profundidad sin recargar.
                RadialGradient(colors: [NEXColor.red.opacity(0.20), .clear], center: .topTrailing, startRadius: 10, endRadius: 420)
            }
            .ignoresSafeArea()
        }
        .onChange(of: model.location.isAuthorized) { _, authorized in
            if authorized { finish() }
        }
    }

    private func finish() {
        model.settings.hasOnboarded = true
        model.setForeground(true)
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            NEXIconTile(systemImage: symbol, tint: NEXColor.red, size: 44)
            Text(text).font(.nexBody).foregroundStyle(NEXColor.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
