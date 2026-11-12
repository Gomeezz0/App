import NEXCore
import SwiftUI

/// Menú de reporte: una pulsación sobre un botón grande envía el aviso en la posición actual.
struct ReportSheet: View {
    let onNeedsAccount: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var sending: AlertType?
    @State private var outcome: Outcome?

    private enum Outcome: Equatable {
        case sent(String)
        case failed(String)
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if !model.isSignedIn {
                    VStack(spacing: 16) {
                        NEXNotice(
                            systemImage: "person.crop.circle.badge.plus", title: "Hace falta una cuenta",
                            message: "Los avisos se firman con una cuenta para poder medir su fiabilidad y frenar los falsos.")
                        Button("Iniciar sesión o crear cuenta", action: onNeedsAccount)
                            .buttonStyle(NEXPrimaryButtonStyle())
                    }
                    .padding(20)
                } else if case .sent(let message) = outcome {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(NEXColor.redGradient, in: Circle())
                            .symbolEffect(.bounce, value: outcome)
                        Text("Gracias").font(.nexTitle).foregroundStyle(NEXColor.text)
                        Text(message).font(.nexBody).foregroundStyle(NEXColor.textDim).multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    ScrollView {
                        if case .failed(let message) = outcome {
                            Label(message, systemImage: "exclamationmark.circle.fill")
                                .font(.nexCaption)
                                .foregroundStyle(NEXColor.amber)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                        }
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(AlertType.allCases.enumerated()), id: \.element) { index, type in
                                button(for: type).nexAppear(delay: Double(index) * 0.025)
                            }
                        }
                        .padding(16)
                        Text("El aviso se sitúa en tu posición actual. Otros conductores podrán confirmarlo o indicar que ya no está.")
                            .font(.nexCaption)
                            .foregroundStyle(NEXColor.textDim)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .nexAnimation(value: outcome)
            .nexScreen("Avisar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
        }
    }

    private func button(for type: AlertType) -> some View {
        Button {
            send(type)
        } label: {
            VStack(spacing: 10) {
                if sending == type {
                    NEXLoader(size: 30).frame(height: 48)
                } else {
                    AlertBadge(type: type, size: 48)
                }
                Text(type.title).font(.nexHeadline).foregroundStyle(NEXColor.text)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .nexCard(padding: 0)
        }
        .buttonStyle(NEXRowButtonStyle())
        .disabled(sending != nil)
        .accessibilityLabel("Avisar de \(type.title.lowercased())")
    }

    private func send(_ type: AlertType) {
        sending = type
        Task {
            defer { sending = nil }
            do {
                let result = try await model.report(type)
                outcome = .sent(
                    result.merged
                        ? "Ya había un aviso aquí. Tu reporte cuenta como confirmación."
                        : "Aviso enviado. Será más visible cuando otros conductores lo confirmen.")
                try? await Task.sleep(for: .seconds(1.6))
                dismiss()
            } catch APIError.unauthorized {
                onNeedsAccount()
            } catch {
                outcome = .failed(error.localizedDescription)
            }
        }
    }
}
