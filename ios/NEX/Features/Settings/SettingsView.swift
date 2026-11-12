import NEXCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        let capabilities = model.routing.capabilities
        Form {
            Section {
                Picker(selection: $settings.verbosity) {
                    ForEach(VoiceVerbosity.allCases) { Text($0.title).tag($0) }
                } label: {
                    row("Indicaciones por voz", "speaker.wave.2.fill")
                }
            } header: {
                NEXSectionLabel("Navegación")
            }

            Section {
                Picker(selection: $settings.mapAppearance) {
                    ForEach(MapAppearance.allCases) { Text($0.title).tag($0) }
                } label: {
                    row("Aspecto del mapa", "moon.fill")
                }
                Toggle(isOn: $settings.showTraffic) { row("Mostrar tráfico", "car.2.fill") }
            } header: {
                NEXSectionLabel("Mapa")
            }

            Section {
                Toggle(isOn: $settings.avoidTolls) { row("Evitar peajes", "eurosign") }
                Toggle(isOn: $settings.avoidHighways) { row("Evitar autopistas", "road.lanes") }
            } header: {
                NEXSectionLabel("Rutas")
            }

            Section {
                NavigationLink { AlertSettingsView() } label: { row("Configuración de avisos", "bell.badge.fill") }
                NavigationLink { OfflineMapsView() } label: { row("Mapas sin conexión", "arrow.down.circle.fill") }
            } header: {
                NEXSectionLabel("Avisos y mapas")
            }

            Section {
                Toggle(isOn: $settings.batterySaver) { row("Ahorro de batería", "bolt.fill") }
                Toggle(isOn: $settings.saveTrips) { row("Guardar historial de viajes", "clock.fill") }
            } header: {
                NEXSectionLabel("Batería y privacidad")
            } footer: {
                Text("El ahorro de batería consulta los avisos con menos frecuencia y mueve la cámara sin animación; NEX lo activa solo con el modo de bajo consumo o si el iPhone se calienta. El historial se guarda únicamente en este iPhone.")
                    .foregroundStyle(NEXColor.textDim)
            }

            Section {
                capability("Proveedor", capabilities.name)
                capability("Tráfico en el tiempo estimado", capabilities.trafficAwareETA)
                capability("Previsión por hora de salida", capabilities.departureTimeETA)
                capability("Mapas sin conexión", capabilities.offlineMaps)
                capability("Límites de velocidad", capabilities.speedLimits)
                capability("Guiado de carril", capabilities.laneGuidance)
            } header: {
                NEXSectionLabel("Proveedor de mapas")
            }

            Section {
                capability("Versión", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            } footer: {
                VStack(spacing: 14) {
                    Text("El uso de esta aplicación de guía en tiempo real es bajo tu responsabilidad. Respeta siempre las señales y las normas de tráfico; no manipules el teléfono mientras conduces.")
                        .foregroundStyle(NEXColor.textDim)
                    NEXLogo(size: 22).opacity(0.5).frame(maxWidth: .infinity)
                }
            }
        }
        .nexFormStyle()
        .nexScreen("Ajustes")
    }

    /// Fila con icono de NEX y texto.
    private func row(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            NEXIconTile(systemImage: symbol, tint: NEXColor.red, size: 32).accessibilityHidden(true)
            Text(title).font(.nexBody).foregroundStyle(NEXColor.text)
        }
    }

    private func capability(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value).foregroundStyle(NEXColor.textDim)
        } label: {
            Text(title).foregroundStyle(NEXColor.text)
        }
    }

    private func capability(_ title: String, _ available: Bool) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                Text(available ? "Sí" : "No disponible")
            }
            .font(.nexCaption)
            .foregroundStyle(available ? NEXColor.green : NEXColor.textDim)
        } label: {
            Text(title).foregroundStyle(NEXColor.text)
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
