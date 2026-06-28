import SwiftUI
import CurveFanCore

struct AppWindowView: View {
    @ObservedObject var state: AppState
    @State private var selectedSection: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            SidebarList(
                selectedSection: $selectedSection,
                isConnected: isConnected
            )
        } detail: {
            detailView
                .navigationTitle(selectedSection?.title ?? "FanFlow")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            Task { await state.checkDaemon() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh helper connection")

                        HelperStatusBadge(isConnected: isConnected)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection ?? .overview {
        case .overview:
            OverviewView(state: state)
        case .fans, .sensors, .presets, .settings:
            PlaceholderSection(section: selectedSection ?? .overview)
        }
    }

    private var isConnected: Bool {
        if case .connected = state.connectionStatus { return true }
        return false
    }

}

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case fans
    case sensors
    case presets
    case settings

    var id: String { rawValue }

    static let monitoring: [AppSection] = [.overview, .fans, .sensors]
    static let configuration: [AppSection] = [.presets, .settings]

    var title: String {
        switch self {
        case .overview: return "FanFlow"
        case .fans: return "Fans"
        case .sensors: return "Sensors"
        case .presets: return "Presets"
        case .settings: return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Apple Silicon thermal and fan control"
        case .fans: return "Fan control and hardware status"
        case .sensors: return "Active macOS SMC readings"
        case .presets: return "Fan curve preset management"
        case .settings: return "FanFlow system behavior"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .fans: return "fan"
        case .sensors: return "thermometer"
        case .presets: return "slider.horizontal.3"
        case .settings: return "gearshape"
        }
    }
}

struct SidebarList: View {
    @Binding var selectedSection: AppSection?
    let isConnected: Bool

    var body: some View {
        List(selection: $selectedSection) {
            Section("Monitor") {
                ForEach(AppSection.monitoring) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(Optional(section))
                }
            }

            Section("Configure") {
                ForEach(AppSection.configuration) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(Optional(section))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("FanFlow")
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        .safeAreaInset(edge: .bottom) {
            SidebarStatus(isConnected: isConnected)
        }
    }
}

struct SidebarStatus: View {
    let isConnected: Bool

    var body: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(isConnected ? "Helper connected" : "Helper offline")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(.bar)
    }
}

struct PlaceholderSection: View {
    let section: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.subtitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            ContentUnavailableView(
                section.title,
                systemImage: section.icon,
                description: Text("This section will use the same native macOS layout system as Overview.")
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
