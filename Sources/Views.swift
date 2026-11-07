import AppKit
import SwiftUI

struct MainSplitView: View {
    @Bindable var client: APMClient
    @Binding var selectedTab: NavigationTab
    @State private var showConsole = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Views") {
                    ForEach(NavigationTab.allCases) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.rawValue, systemImage: tab.icon)
                        }
                    }
                }

                Section("Workspaces") {
                    WorkspaceRow(
                        title: WorkspaceScope.global.displayName,
                        icon: "globe",
                        isSelected: client.scope == .global
                    ) {
                        client.selectScope(.global)
                    }

                    ForEach(client.savedProjects, id: \.self) { path in
                        let projScope = WorkspaceScope.project(path)
                        WorkspaceRow(
                            title: projScope.displayName,
                            subtitle: path,
                            icon: "folder",
                            isSelected: client.scope == projScope
                        ) {
                            client.selectScope(projScope)
                        }
                        .contextMenu {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                            }
                            Button("Remove from List", role: .destructive) {
                                client.removeProjectFolder(path)
                            }
                        }
                    }

                    Button {
                        pickProjectFolder(client: client)
                    } label: {
                        Label("Add Project Folder…", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                CLIStatusFooter(client: client)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                WorkspaceHeaderBar(client: client)
                Divider()

                Group {
                    switch selectedTab {
                    case .manifest:
                        ManifestView(client: client)
                    case .marketplace:
                        MarketplaceView(client: client)
                    case .targets:
                        TargetsView(client: client)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                ConsoleDrawer(client: client, isExpanded: $showConsole)
            }
        }
    }
}

private struct WorkspaceRow: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .imageScale(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CLIStatusFooter: View {
    @Bindable var client: APMClient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(client.binaryPath != nil ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(client.binaryPath != nil ? "APM CLI Ready" : "APM CLI Missing")
                        .font(.caption.weight(.medium))
                    Text(client.cliVersion ?? client.binaryPath ?? "Not found in PATH")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if client.binaryPath == nil {
                    Button("Install") {
                        Task { await client.installCLI() }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(client.isRunning)
                } else {
                    Button {
                        Task { await client.detectBinary() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Re-check APM CLI")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }
}

private struct WorkspaceHeaderBar: View {
    @Bindable var client: APMClient

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: client.scope == .global ? "globe" : "folder.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(client.scope.displayName)
                        .font(.headline)
                    if client.hasManifestFile {
                        Text("apm.yml")
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    } else {
                        Text("No apm.yml")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(client.scope.directoryURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !client.hasManifestFile {
                Button {
                    Task { await client.initManifest() }
                } label: {
                    Label("Initialize apm.yml", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(client.isRunning)
            } else {
                Button {
                    Task { await client.installAll() }
                } label: {
                    Label("Install", systemImage: "arrow.down.circle")
                }
                .disabled(client.isRunning)

                Button {
                    Task { await client.updateAll() }
                } label: {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(client.isRunning)
            }

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: client.scope.directoryURL.path)
            } label: {
                Image(systemName: "folder.badge.gearshape")
            }
            .help("Open in Finder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
    }
}

struct ManifestView: View {
    @Bindable var client: APMClient
    @State private var editorMode: Int = 0
    @State private var newPackageInput: String = ""
    @State private var isMCPPackage: Bool = false
    @State private var mcpTransport: String = "http"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Mode", selection: $editorMode) {
                    Text("Packages & MCP").tag(0)
                    Text("Raw apm.yml").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Spacer()

                if editorMode == 0 {
                    HStack(spacing: 8) {
                        Picker("", selection: $isMCPPackage) {
                            Text("APM Package").tag(false)
                            Text("MCP Server").tag(true)
                        }
                        .frame(width: 130)

                        TextField(
                            isMCPPackage ? "io.github.github/github-mcp-server" : "owner/repo or skill path…",
                            text: $newPackageInput
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220, maxWidth: 320)
                        .onSubmit { addDependency() }

                        if isMCPPackage {
                            Picker("", selection: $mcpTransport) {
                                Text("http").tag("http")
                                Text("stdio").tag("stdio")
                                Text("sse").tag("sse")
                            }
                            .frame(width: 80)
                        }

                        Button("Add & Install") {
                            addDependency()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newPackageInput.trimmingCharacters(in: .whitespaces).isEmpty || client.isRunning)
                    }
                } else {
                    Button("Save apm.yml") {
                        client.saveRawYAML()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)

            Divider()

            if editorMode == 0 {
                List {
                    Section("APM Packages (\(client.manifest.apmDependencies.count))") {
                        if client.manifest.apmDependencies.isEmpty {
                            Text("No APM packages declared in apm.yml.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(client.manifest.apmDependencies, id: \.self) { dep in
                                HStack {
                                    Image(systemName: "cube.box")
                                        .foregroundStyle(Color.accentColor)
                                    Text(dep)
                                        .font(.body.monospaced())
                                    Spacer()
                                    Button(role: .destructive) {
                                        Task { await client.uninstallPackage(dep, isMCP: false) }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Uninstall \(dep)")
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    Section("MCP Servers (\(client.manifest.mcpDependencies.count))") {
                        if client.manifest.mcpDependencies.isEmpty {
                            Text("No MCP servers declared in apm.yml.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(client.manifest.mcpDependencies) { mcp in
                                HStack {
                                    Image(systemName: "server.rack")
                                        .foregroundStyle(.purple)
                                    Text(mcp.name)
                                        .font(.body.monospaced())
                                    Text(mcp.transport)
                                        .font(.caption.monospaced())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.15), in: Capsule())
                                    Spacer()
                                    Button(role: .destructive) {
                                        Task { await client.uninstallPackage(mcp.name, isMCP: true) }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove \(mcp.name)")
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    if !client.lockfilePackages.isEmpty {
                        Section("Lockfile Entries (apm.lock.yaml)") {
                            ForEach(client.lockfilePackages, id: \.self) { line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                TextEditor(text: $client.rawYAML)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
            }
        }
    }

    private func addDependency() {
        let pkg = newPackageInput
        newPackageInput = ""
        Task {
            await client.installPackage(pkg, isMCP: isMCPPackage, transport: mcpTransport)
        }
    }
}

struct MarketplaceView: View {
    @Bindable var client: APMClient
    @State private var query: String = ""
    @State private var newMarketplaceRepo: String = ""

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search APM marketplaces (e.g. frontend, copilot, mcp)…", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task { await client.search(query) }
                        }
                    Button("Search") {
                        Task { await client.search(query) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || client.isRunning)
                }
                .padding(12)

                Divider()

                List {
                    if client.searchResults.isEmpty {
                        Section("Suggested Starter Packages") {
                            SuggestedPackageRow(
                                package: "anthropics/skills/skills/frontend-design",
                                summary: "Frontend design skill for coding agents",
                                client: client
                            )
                            SuggestedPackageRow(
                                package: "github/awesome-copilot/agents/api-architect.agent.md",
                                summary: "API Architect agent specification",
                                client: client
                            )
                            SuggestedPackageRow(
                                package: "microsoft/apm-sample-package",
                                summary: "Official Microsoft APM sample package",
                                client: client
                            )
                        }
                    } else {
                        Section("Search Results (\(client.searchResults.count))") {
                            ForEach(client.searchResults) { item in
                                SuggestedPackageRow(
                                    package: item.package,
                                    summary: item.description,
                                    client: client
                                )
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 380)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Registered Marketplaces")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await client.updateMarketplaces() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Update marketplace caches")
                    .disabled(client.isRunning)
                }
                .padding(12)

                Divider()

                List {
                    if client.marketplaces.isEmpty {
                        Text("No custom marketplaces registered yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(client.marketplaces) { mp in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mp.name)
                                        .font(.body.weight(.medium))
                                    Text(mp.repo)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    Task { await client.removeMarketplace(mp.name) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    TextField("owner/repo (e.g. github/awesome-copilot)", text: $newMarketplaceRepo)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addMarketplace() }
                    Button("Add") {
                        addMarketplace()
                    }
                    .disabled(newMarketplaceRepo.trimmingCharacters(in: .whitespaces).isEmpty || client.isRunning)
                }
                .padding(10)
            }
            .frame(minWidth: 260, maxWidth: 340)
        }
    }

    private func addMarketplace() {
        let repo = newMarketplaceRepo
        newMarketplaceRepo = ""
        Task { await client.addMarketplace(repo) }
    }
}

private struct SuggestedPackageRow: View {
    let package: String
    let summary: String
    @Bindable var client: APMClient

    var isInstalled: Bool {
        client.manifest.apmDependencies.contains(package)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(package)
                    .font(.body.monospaced().weight(.medium))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isInstalled {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Install") {
                    Task { await client.installPackage(package) }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(client.isRunning)
            }
        }
        .padding(.vertical, 3)
    }
}

struct TargetsView: View {
    @Bindable var client: APMClient

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Agent Harnesses")
                        .font(.headline)
                    Text("Select which AI coding assistants receive compiled instructions, skills, and MCP configs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await client.refreshTargets() }
                } label: {
                    Label("Detect Targets", systemImage: "sensor.tag.radiowaves.forward")
                }
                .disabled(client.isRunning)

                Button {
                    Task { await client.compileTargets() }
                } label: {
                    Label("Compile Context (apm compile)", systemImage: "hammer.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(client.isRunning)
            }
            .padding(14)

            Divider()

            List {
                ForEach(client.detectedTargets) { target in
                    let isEnabled = client.manifest.targets.contains(target.name)
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { isEnabled },
                            set: { _ in client.toggleTarget(target.name) }
                        ))
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(target.name)
                                    .font(.body.weight(.semibold))
                                if target.detected {
                                    Text("Detected on disk")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.blue)
                                }
                            }
                            Text("Output directory: \(target.outputDir)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isEnabled {
                            Text("Active in apm.yml")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct ConsoleDrawer: View {
    @Bindable var client: APMClient
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.bold))
                        Image(systemName: "terminal")
                        Text(client.lastCommand)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                if client.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                if isExpanded && !client.consoleLog.isEmpty {
                    Button("Clear") {
                        client.consoleLog = ""
                    }
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            if isExpanded {
                Divider()
                ScrollView {
                    Text(client.consoleLog.isEmpty ? "No CLI output yet." : client.consoleLog)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(height: 150)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
}
