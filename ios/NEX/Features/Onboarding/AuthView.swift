import NEXCore
import SwiftUI

/// Registro e inicio de sesión. La cuenta solo hace falta para aportar a la comunidad
/// (reportar y valorar avisos); navegar y ver avisos funciona sin ella.
struct AuthView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Iniciar sesión"
        case register = "Crear cuenta"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        let hasEmail = email.contains("@") && email.contains(".")
        switch mode {
        case .signIn: return hasEmail && !password.isEmpty
        case .register: return hasEmail && password.count >= 10 && displayName.trimmingCharacters(in: .whitespaces).count >= 2
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        NEXLogo(size: 30)
                        Text(mode == .signIn ? "Bienvenido de nuevo" : "Únete a la comunidad")
                            .font(.nexTitle).foregroundStyle(NEXColor.text)
                            .contentTransition(.opacity)
                    }
                    .padding(.bottom, 4)

                    Picker("Modo", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text("Con una cuenta puedes avisar de incidencias y confirmar las de otros conductores.")
                        .font(.nexBody)
                        .foregroundStyle(NEXColor.textDim)

                    if mode == .register {
                        field("Nombre visible", text: $displayName)
                            .textContentType(.nickname)
                    }
                    field("Correo electrónico", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    passwordField
                    if mode == .register {
                        Text("Mínimo 10 caracteres.").font(.nexCaption).foregroundStyle(NEXColor.textDim)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.nexCaption)
                            .foregroundStyle(NEXColor.amber)
                    }

                    Button {
                        submit()
                    } label: {
                        if isWorking { NEXLoader(size: 22) } else { Text(mode.rawValue) }
                    }
                    .buttonStyle(NEXPrimaryButtonStyle())
                    .disabled(!isValid || isWorking)
                    .accessibilityIdentifier("auth-submit")
                    .padding(.top, 8)
                }
                .padding(20)
                .nexAnimation(value: mode)
            }
            .nexScreen("Cuenta NEX")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .onChange(of: mode) { _, _ in errorMessage = nil }
        }
    }

    @ViewBuilder private var passwordField: some View {
        #if DEBUG
        // El simulador no deja escribir en campos seguros desde las pruebas de interfaz.
        if UserDefaults.standard.bool(forKey: "nexPlainPasswordField") {
            field("Contraseña", text: $password).textInputAutocapitalization(.never).autocorrectionDisabled()
        } else {
            secureField
        }
        #else
        secureField
        #endif
    }

    private var secureField: some View {
        NEXField {
            SecureField("Contraseña", text: $password, prompt: Text("Contraseña").foregroundStyle(NEXColor.textDim))
                .textContentType(mode == .register ? .newPassword : .password)
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        NEXField {
            TextField(title, text: text, prompt: Text(title).foregroundStyle(NEXColor.textDim))
        }
    }

    private func submit() {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                switch mode {
                case .signIn:
                    try await model.signIn(email: email, password: password)
                case .register:
                    try await model.register(email: email, password: password, displayName: displayName)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
