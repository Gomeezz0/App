import NEXCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        let capabilities = model.routing.capabilities
        Form {
            Section("Voz") {
                Picker("Indicaciones", selection: $settings.verbosity) {
                    ForEach(VoiceVerbosity.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Mapa") {
                Picker("Aspecto", selection: $settings.mapAppearance) {
                    ForEach(MapAppearance.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Mostrar tráfico", isOn: $settings.showTraffic)
            }
            Section("Rutas") {
                Toggle("Evitar peajes", isOn: $settings.avoidTolls)
                Toggle("Evitar autopistas", isOn: $settings.avoidHighways)
            }
            Section {
                NavigationLink("Configuración de avisos") { AlertSettingsView() }
                NavigationLink("Mapas sin conexión") { OfflineMapsView() }
            }
            Section {
                Toggle("Ahorro de batería", isOn: $settings.batterySaver)
            } footer: {
                Text("Consulta los avisos con menos frecuencia y mueve la cámara sin animación. NEX también lo hace solo si el iPhone está en modo de bajo consumo o se calienta.")
            }
            Section {
                Toggle("Guardar historial de viajes", isOn: $settings.saveTrips)
            } footer: {
                Text("El historial y las estadísticas se guardan solo en este iPhone.")
            }
            Section("Proveedor de mapas") {
                capability("Proveedor", capabilities.name)
                capability("Tráfico en el tiempo estimado", capabilities.trafficAwareETA)
                capability("Previsión por hora de salida", capabilities.departureTimeETA)
                capability("Mapas sin conexión", capabilities.offlineMaps)
                capability("Límites de velocidad", capabilities.speedLimits)
                capability("Guiado de carril", capabilities.laneGuidance)
            }
            Section {
                capability("Versión", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            } footer: {
                Text("El uso de esta aplicación de guía en tiempo real es bajo tu responsabilidad. Respeta siempre las señales y las normas de tráfico; no manipules el teléfono mientras conduces.")
            }
        }
        .nexFormStyle()
        .nexScreen("Ajustes")
    }

    private func capability(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func capability(_ title: String, _ available: Bool) -> some View {
        LabeledContent(title) {
            Text(available ? "Sí" : "No disponible").foregroundStyle(available ? NEXColor.green : NEXColor.textDim)
        }
    }
}

/// Qué hacer con cada tipo de aviso: mapa y voz, solo mapa, u ocultarlo.
struct AlertSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(AlertType.allCases) { type in
                    Picker(selection: binding(for: type)) {
                        ForEach(AlertPreference.allCases) { Text($0.title).tag($0) }
                    } label: {
                        HStack(spacing: 12) {
                            AlertBadge(type: type, size: 30)
                            Text(type.title)
                        }
                    }
                }
            } footer: {
                Text("Los avisos sin verificar nunca se anuncian por voz, sea cual sea esta configuración. Los avisos de control se muestran según la normativa de cada país.")
            }
        }
        .nexFormStyle()
        .nexScreen("Avisos")
    }

    private func binding(for type: AlertType) -> Binding<AlertPreference> {
        Binding(
            get: { model.settings.preference(for: type) },
            set: { model.settings.alertPreferences[type] = $0 })
    }
}

/// Gestión de mapas sin conexión. Con el proveedor actual no existe: se explica, no se simula.
struct OfflineMapsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if model.routing.capabilities.offlineMaps {
                NEXNotice(
                    systemImage: "arrow.down.circle", title: "Descargas",
                    message: "La gestión de descargas se habilitará con el proveedor configurado.")
            } else {
                NEXNotice(
                    systemImage: "icloud.slash", title: "No disponible todavía",
                    message: "\(model.routing.capabilities.name) no permite a las apps descargar mapas. Esta función llegará cuando NEX integre un proveedor que lo admita.")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Qué funciona sin cobertura").font(.nexHeadline).foregroundStyle(NEXColor.text)
                    bullet("La guía giro a giro y la voz de una ruta ya calculada.")
                    bullet("Los avisos descargados antes de perder la conexión, hasta que caducan.")
                    Text("Qué necesita conexión").font(.nexHeadline).foregroundStyle(NEXColor.text).padding(.top, 8)
                    bullet("Buscar destinos y calcular o recalcular rutas.")
                    bullet("Cargar zonas del mapa que no se hayan visto recientemente.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .nexCard()
                .padding(.horizontal, 16)
            }
        }
        .nexScreen("Mapas sin conexión")
    }

    private func bullet(_ text: String) -> some View {
        Label(text, systemImage: "circle.fill")
            .labelStyle(BulletLabelStyle())
            .font(.nexBody)
            .foregroundStyle(NEXColor.textDim)
    }
}

extension View {
    /// Formularios con filas antracita, separadores discretos y controles en rojo.
    func nexFormStyle() -> some View {
        self.listRowBackground(NEXColor.surface)
            .listRowSeparatorTint(NEXColor.mid)
            .foregroundStyle(NEXColor.text)
            .tint(NEXColor.red)
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(NEXColor.red)
            configuration.title
        }
    }
}
