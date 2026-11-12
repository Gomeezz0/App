import ActivityKit
import NEXCore
import SwiftUI
import WidgetKit

@main
struct NEXWidgetBundle: WidgetBundle {
    var body: some Widget {
        SearchWidget()
        NavigationLiveActivity()
    }
}

// MARK: - Widget de inicio: acceso directo al buscador

private struct SearchEntry: TimelineEntry {
    let date: Date
}

private struct SearchProvider: TimelineProvider {
    func placeholder(in context: Context) -> SearchEntry { SearchEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (SearchEntry) -> Void) {
        completion(SearchEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SearchEntry>) -> Void) {
        // Contenido fijo: no hace falta refrescarlo, así que no consume batería.
        completion(Timeline(entries: [SearchEntry(date: Date())], policy: .never))
    }
}

struct SearchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.nex.search", provider: SearchProvider()) { _ in
            VStack(alignment: .leading, spacing: 8) {
                Text("NEX")
                    .font(.system(size: 22, weight: .heavy))
                    .kerning(2)
                    .foregroundStyle(NEXBrand.text)
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(NEXBrand.red)
                    Text("¿A dónde vamos?").foregroundStyle(NEXBrand.textDim)
                }
                .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(NEXBrand.black, for: .widget)
            .widgetURL(URL(string: "nex://search"))
        }
        .configurationDisplayName("Buscar destino")
        .description("Abre NEX directamente en el buscador.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Live Activity de navegación

private extension NavigationActivityAttributes.ContentState {
    var symbol: String {
        switch phase {
        case .navigating: return "arrow.turn.up.right"
        case .rerouting: return "arrow.triangle.2.circlepath"
        case .arrived: return "flag.checkered"
        }
    }

    var headline: String {
        switch phase {
        case .navigating: return NEXFormat.distance(distanceToManeuver)
        case .rerouting: return "Recalculando"
        case .arrived: return "Has llegado"
        }
    }
}

struct NavigationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationActivityAttributes.self) { context in
            // Pantalla bloqueada.
            let state = context.state
            HStack(spacing: 14) {
                Image(systemName: state.symbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(NEXBrand.red)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.headline)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(NEXBrand.text)
                    Text(state.phase == .navigating ? state.instruction : context.attributes.destinationName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(NEXBrand.textDim)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if state.phase != .arrived {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(state.arrival, style: .time)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(NEXBrand.text)
                        Text(NEXFormat.distance(state.distanceRemaining))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NEXBrand.textDim)
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(NEXBrand.black)
            .activitySystemActionForegroundColor(NEXBrand.text)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.symbol)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(NEXBrand.red)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.headline).font(.system(size: 22, weight: .bold, design: .rounded))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.phase != .arrived {
                        Text(state.arrival, style: .time).font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(state.phase == .navigating ? state.instruction : context.attributes.destinationName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: state.symbol).foregroundStyle(NEXBrand.red)
            } compactTrailing: {
                Text(state.phase == .navigating ? NEXFormat.distance(state.distanceToManeuver) : "NEX")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            } minimal: {
                Image(systemName: state.symbol).foregroundStyle(NEXBrand.red)
            }
        }
    }
}
