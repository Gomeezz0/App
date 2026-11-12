import SwiftUI

/// Bienvenida: presenta NEX y pide el permiso de ubicación explicando para qué.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            NEXLogo(size: 84)
            Text("NEX")
                .font(.system(size: 54, weight: .heavy))
                .kerning(4)
                .foregroundStyle(NEXColor.text)
                .padding(.top, 20)
            Text("Navegación clara.\nAvisos en los que puedes confiar.")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(NEXColor.textDim)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 18) {
                feature("location.north.line.fill", "Guía giro a giro con voz y tráfico en el tiempo estimado")
                feature("checkmark.shield.fill", "Avisos de la comunidad, ponderados por fiabilidad")
                feature("battery.75percent", "Sin publicidad y sin GPS en segundo plano fuera de un viaje")
            }
            .padding(.top, 36)
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
        .background(NEXColor.black.ignoresSafeArea())
        .onChange(of: model.location.isAuthorized) { _, authorized in
            if authorized { finish() }
        }
    }

    private func finish() {
        model.settings.hasOnboarded = true
        model.setForeground(true)
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(NEXColor.red)
                .frame(width: 28)
            Text(text).font(.nexBody).foregroundStyle(NEXColor.text)
        }
    }
}
