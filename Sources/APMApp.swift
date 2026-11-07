import AppKit
import SwiftUI

public enum NavigationTab: String, CaseIterable, Identifiable {
    case manifest = "Manifest & Packages"
    case marketplace = "Marketplace & Search"
    case targets = "Targets & Compiler"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .manifest: return "shippingbox"
        case .marketplace: return "magnifyingglass.circle"
        case .targets: return "slider.horizontal.3"
        }
    }
}

@main
struct APMApp: App {
    @State private var client = APMClient()
    @State private var selectedTab: NavigationTab = .manifest

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Agent Package Manager") {
            MainSplitView(client: client, selectedTab: $selectedTab)
                .frame(minWidth: 880, minHeight: 580)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Project Folder…") {
                    pickProjectFolder(client: client)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

@MainActor
func pickProjectFolder(client: APMClient) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open APM Workspace"
    if panel.runModal() == .OK, let url = panel.url {
        client.addProjectFolder(url.path)
    }
}
