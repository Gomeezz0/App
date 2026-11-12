import NEXCore
import SwiftUI

/// Historial de viajes y estadísticas de conducción. Todo se calcula y se guarda en el dispositivo.
struct TripHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        let trips = model.trips.trips
        List {
            if trips.isEmpty {
                NEXNotice(
                    systemImage: "road.lanes", title: "Aún no hay viajes",
                    message: model.settings.saveTrips
                        ? "Tus viajes aparecerán aquí al terminar una navegación."
                        : "El guardado de viajes está desactivado en Ajustes.")
                    .listRowBackground(Color.clear)
            } else {
                Section("Últimos 7 días") {
                    stats(TripStats.since(Date().addingTimeInterval(-7 * 86_400), in: trips))
                }
                Section("Total") { stats(TripStats(trips: trips)) }
                Section("Viajes") {
                    ForEach(trips) { trip in
                        Button {
                            model.pendingDestination = trip.destination
                            dismiss()
                        } label: {
                            row(trip)
                        }
                        .listRowBackground(NEXColor.surface)
                        .accessibilityHint("Abre la ruta a este destino")
                    }
                    .onDelete { offsets in
                        for index in offsets { model.trips.remove(trips[index]) }
                    }
                }
            }
        }
        .nexScreen("Historial")
        .toolbar {
            if !trips.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Borrar todo", role: .destructive) { confirmClear = true }
                }
            }
        }
        .confirmationDialog("¿Borrar todo el historial?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { model.trips.removeAll() }
        }
    }

    private func stats(_ stats: TripStats) -> some View {
        HStack {
            stat("\(stats.count)", "viajes")
            stat(NEXFormat.distance(stats.distance), "recorridos")
            stat(stats.count == 0 ? "–" : NEXFormat.duration(stats.duration), "al volante")
            stat("\(NEXFormat.kmh(stats.averageSpeed))", "km/h media")
        }
        .listRowBackground(NEXColor.surface)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.nexNumber(20)).foregroundStyle(NEXColor.text).minimumScaleFactor(0.7).lineLimit(1)
                .contentTransition(.numericText())
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(NEXColor.textDim)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func row(_ trip: Trip) -> some View {
        HStack(spacing: 12) {
            NEXIconTile(
                systemImage: trip.completed ? "flag.checkered" : "arrow.uturn.left",
                tint: trip.completed ? NEXColor.red : NEXColor.textDim)
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.destination.name).font(.nexHeadline).foregroundStyle(NEXColor.text).lineLimit(1)
                Text(trip.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.nexCaption).foregroundStyle(NEXColor.textDim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(NEXFormat.distance(trip.distance)).font(.nexNumber(16)).foregroundStyle(NEXColor.text)
                Text(NEXFormat.duration(trip.duration)).font(.nexCaption).foregroundStyle(NEXColor.textDim)
            }
        }
        .frame(minHeight: 48)
    }
}
