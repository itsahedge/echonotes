import SwiftUI

struct SettingsSidebarView: View {
    @Environment(TranscriptionManager.self) private var tm
    @Environment(RecordingEngine.self) private var recorder

    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            SettingsSidebarNavigation(selection: $selectedSection)
                .frame(width: 220)
        } detail: {
            SettingsSectionView(section: selectedSection, tm: tm, recorder: recorder)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case aiProviders = "AI Providers"
    case customProviders = "Custom Providers"
    case about = "About"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .aiProviders: return "sparkles"
        case .customProviders: return "plus.circle"
        case .about: return "info.circle"
        }
    }
}

struct SettingsSidebarNavigation: View {
    @Binding var selection: SettingsSection
    
    var body: some View {
        List(selection: $selection) {
            NavigationLink(value: SettingsSection.general) {
                Label("General", systemImage: "gearshape")
            }
            NavigationLink(value: SettingsSection.aiProviders) {
                Label("AI Providers", systemImage: "sparkles")
            }
            NavigationLink(value: SettingsSection.customProviders) {
                Label("Custom Providers", systemImage: "plus.circle")
            }
            Spacer()
            NavigationLink(value: SettingsSection.about) {
                Label("About", systemImage: "info.circle")
            }
        }
        .listStyle(.sidebar)
    }
}

struct SettingsSectionView: View {
    let section: SettingsSection
    @Bindable var tm: TranscriptionManager
    @Bindable var recorder: RecordingEngine

    var body: some View {
        Group {
            switch section {
            case .general:
                GeneralSettingsView(tm: tm, recorder: recorder)
            case .aiProviders:
                AIProvidersSettingsView(tm: tm)
            case .customProviders:
                CustomProvidersSettingsView(tm: tm, recorder: recorder)
            case .about:
                AboutSettingsView()
            }
        }
        .padding()
    }
}