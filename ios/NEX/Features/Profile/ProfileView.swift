import NEXCore
import SwiftUI

/// Perfil: reputación en la comunidad, aportaciones y gestión de la cuenta.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var showAuth = false
    @State private var showDelete = false
    @State private var deletePassword = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let user = model.user {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.displayName).font(.nexTitle).foregroundStyle(NEXColor.text)
                        Text(user.email).font(.nexCaption).foregroundStyle(NEXColor.textDim)
                    }
                    .listRowBackground(NEXColor.surface)
                }
                Section("Comunidad") {
                    value("Reputación", "\(user.reputation)", highlight: true)
                    value("Avisos enviados", "\(user.stats.reports)")
                    value("Confirmaciones recibidas", "\(user.stats.confirmationsReceived)")
                    value("Avisos valorados", "\(user.stats.votesCast)")
                    Text(reputationNote(user.reputation))
                        .font(.nexCaption).foregroundStyle(NEXColor.textDim)
                        .listRowBackground(NEXColor.surface)
                }
                Section {
                    Button("Cerrar sesión") { Task { await model.signOut() } }
                        .listRowBackground(NEXColor.surface)
                    Button("Eliminar cuenta", role: .destructive) { showDelete = true }
                        .listRowBackground(NEXColor.surface)
                } footer: {
                    if let errorMessage { Text(errorMessage).foregroundStyle(NEXColor.amber) }
                }
            } else {
                NEXNotice(
                    systemImage: "person.crop.circle", title: "Sin sesión",
                    message: "Puedes navegar y ver avisos sin cuenta. Para avisar de incidencias o confirmarlas, inicia sesión.")
                    .listRowBackground(Color.clear)
                Button("Iniciar sesión o crear cuenta") { showAuth = true }
                    .buttonStyle(NEXPrimaryButtonStyle())
                    .listRowBackground(Color.clear)
            }
        }
        .nexScreen("Perfil")
        .task { await model.reloadProfile() }
        .sheet(isPresented: $showAuth) { AuthView() }
        .alert("Eliminar cuenta", isPresented: $showDelete) {
            SecureField("Contraseña", text: $deletePassword)
            Button("Eliminar", role: .destructive) { deleteAccount() }
            Button("Cancelar", role: .cancel) { deletePassword = "" }
        } message: {
            Text("Se borrarán tu cuenta, tu reputación y tus votos. Los avisos que enviaste quedarán anónimos hasta que caduquen. No se puede deshacer.")
        }
    }

    private func value(_ title: String, _ value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(NEXColor.text)
            Spacer()
            Text(value).font(.nexNumber(18)).foregroundStyle(highlight ? NEXColor.red : NEXColor.text)
        }
        .listRowBackground(NEXColor.surface)
        .accessibilityElement(children: .combine)
    }

    private func reputationNote(_ reputation: Int) -> String {
        if reputation <= -20 { return "Tu reputación es muy baja: tus avisos y votos no cuentan hasta que mejore." }
        if reputation >= 50 { return "Tus avisos y votos tienen el peso máximo." }
        return "La reputación sube cuando otros conductores confirman tus avisos y baja si se retiran por falsos."
    }

    private func deleteAccount() {
        let password = deletePassword
        deletePassword = ""
        Task {
            do {
                try await model.deleteAccount(password: password)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
