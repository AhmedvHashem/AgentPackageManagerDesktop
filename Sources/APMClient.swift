import Foundation
import Observation

public struct APMMCPServer: Identifiable, Equatable, Hashable {
    public var id: String { name }
    public var name: String
    public var transport: String

    public init(name: String, transport: String = "http") {
        self.name = name
        self.transport = transport
    }
}

public struct APMManifest: Equatable {
    public var name: String
    public var version: String
    public var description: String
    public var targets: [String]
    public var apmDependencies: [String]
    public var mcpDependencies: [APMMCPServer]

    public init(
        name: String = "my-agent-workspace",
        version: String = "1.0.0",
        description: String = "AI agent configurations and skills",
        targets: [String] = ["copilot", "claude", "cursor"],
        apmDependencies: [String] = [],
        mcpDependencies: [APMMCPServer] = []
    ) {
        self.name = name
        self.version = version
        self.description = description
        self.targets = targets
        self.apmDependencies = apmDependencies
        self.mcpDependencies = mcpDependencies
    }

    // ponytail: line-based apm.yml parser + raw TextEditor; add Yams only if complex nested YAML anchors are needed
    public static func parse(_ yaml: String) -> APMManifest {
        var manifest = APMManifest(name: "", version: "1.0.0", description: "", targets: [])
        enum Section { case root, targets, deps, depsAPM, depsMCP, other }
        var section: Section = .root
        var pendingMCPName: String?

        func flushMCP() {
            if let mcpName = pendingMCPName, !mcpName.isEmpty {
                manifest.mcpDependencies.append(APMMCPServer(name: mcpName, transport: "http"))
                pendingMCPName = nil
            }
        }

        for rawLine in yaml.components(separatedBy: .newlines) {
            let commentStripped: String
            if let hashRange = rawLine.range(of: " #") {
                commentStripped = String(rawLine[..<hashRange.lowerBound])
            } else {
                commentStripped = rawLine
            }
            let trimmed = commentStripped.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let indent = commentStripped.prefix(while: { $0 == " " }).count

            if indent == 0 {
                flushMCP()
                if trimmed.hasPrefix("name:") {
                    manifest.name = unquote(trimmed.dropFirst("name:".count))
                    section = .root
                } else if trimmed.hasPrefix("version:") {
                    manifest.version = unquote(trimmed.dropFirst("version:".count))
                    section = .root
                } else if trimmed.hasPrefix("description:") {
                    manifest.description = unquote(trimmed.dropFirst("description:".count))
                    section = .root
                } else if trimmed == "targets:" {
                    section = .targets
                } else if trimmed.hasPrefix("targets:") {
                    let inline = trimmed.dropFirst("targets:".count).trimmingCharacters(in: .whitespaces)
                    if inline.hasPrefix("[") && inline.hasSuffix("]") {
                        let inner = inline.dropFirst().dropLast()
                        manifest.targets = inner.split(separator: ",").map { unquote($0) }.filter { !$0.isEmpty }
                    }
                    section = .root
                } else if trimmed == "dependencies:" {
                    section = .deps
                } else {
                    section = .other
                }
                continue
            }

            switch section {
            case .targets:
                if trimmed.hasPrefix("- ") {
                    let val = unquote(trimmed.dropFirst(2))
                    if !val.isEmpty { manifest.targets.append(val) }
                }
            case .deps, .depsAPM, .depsMCP:
                if indent <= 2 && trimmed.hasPrefix("apm:") {
                    flushMCP()
                    section = .depsAPM
                } else if indent <= 2 && trimmed.hasPrefix("mcp:") {
                    flushMCP()
                    section = .depsMCP
                } else if indent <= 2 && trimmed.hasSuffix(":") {
                    flushMCP()
                    section = .other
                } else if section == .depsAPM && trimmed.hasPrefix("- ") {
                    let val = unquote(trimmed.dropFirst(2))
                    if !val.isEmpty { manifest.apmDependencies.append(val) }
                } else if section == .depsMCP {
                    if trimmed.hasPrefix("- name:") {
                        flushMCP()
                        pendingMCPName = unquote(trimmed.dropFirst("- name:".count))
                    } else if trimmed.hasPrefix("- ") {
                        flushMCP()
                        let val = unquote(trimmed.dropFirst(2))
                        if !val.isEmpty {
                            manifest.mcpDependencies.append(APMMCPServer(name: val, transport: "http"))
                        }
                    } else if trimmed.hasPrefix("transport:"), let mcpName = pendingMCPName {
                        let tr = unquote(trimmed.dropFirst("transport:".count))
                        manifest.mcpDependencies.append(APMMCPServer(name: mcpName, transport: tr.isEmpty ? "http" : tr))
                        pendingMCPName = nil
                    }
                }
            default:
                break
            }
        }
        flushMCP()
        return manifest
    }

    public func toYAML() -> String {
        var lines: [String] = []
        lines.append("name: \(name.isEmpty ? "my-agent-workspace" : name)")
        lines.append("version: \(version.isEmpty ? "1.0.0" : version)")
        if !description.isEmpty {
            lines.append("description: \"\(description.replacingOccurrences(of: "\"", with: "\\\""))\"")
        }
        if !targets.isEmpty {
            lines.append("targets:")
            for t in targets {
                lines.append("  - \(t)")
            }
        }
        if !apmDependencies.isEmpty || !mcpDependencies.isEmpty {
            lines.append("")
            lines.append("dependencies:")
            if !apmDependencies.isEmpty {
                lines.append("  apm:")
                for dep in apmDependencies {
                    lines.append("    - \(dep)")
                }
            }
            if !mcpDependencies.isEmpty {
                lines.append("  mcp:")
                for mcp in mcpDependencies {
                    lines.append("    - name: \(mcp.name)")
                    lines.append("      transport: \(mcp.transport)")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func unquote<S: StringProtocol>(_ str: S) -> String {
        var s = str.trimmingCharacters(in: .whitespaces)
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            if s.count >= 2 { s = String(s.dropFirst().dropLast()) }
        }
        return s
    }
}

public struct APMTargetInfo: Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var detected: Bool
    public var outputDir: String

    public static let defaultTargets: [APMTargetInfo] = [
        APMTargetInfo(name: "copilot", detected: false, outputDir: ".github/"),
        APMTargetInfo(name: "claude", detected: false, outputDir: ".claude/"),
        APMTargetInfo(name: "cursor", detected: false, outputDir: ".cursor/"),
        APMTargetInfo(name: "gemini", detected: false, outputDir: ".gemini/"),
        APMTargetInfo(name: "windsurf", detected: false, outputDir: ".windsurf/"),
        APMTargetInfo(name: "codex", detected: false, outputDir: ".codex/"),
        APMTargetInfo(name: "opencode", detected: false, outputDir: ".opencode/"),
        APMTargetInfo(name: "vscode", detected: false, outputDir: ".vscode/")
    ]

    public static func parseTargetsJSON(_ data: Data) -> [APMTargetInfo]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let dicts: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            dicts = arr
        } else if let obj = raw as? [String: Any], let arr = obj["targets"] as? [[String: Any]] {
            dicts = arr
        } else {
            return nil
        }

        var parsed: [APMTargetInfo] = []
        for item in dicts {
            guard let name = (item["name"] ?? item["target"] ?? item["id"]) as? String else { continue }
            let detected = (item["detected"] as? Bool) ?? (item["active"] as? Bool) ?? false
            let outDir = (item["output_dir"] ?? item["outputDir"] ?? item["path"]) as? String ?? ".\(name)/"
            parsed.append(APMTargetInfo(name: name, detected: detected, outputDir: outDir))
        }
        return parsed.isEmpty ? nil : parsed
    }
}

public struct APMSearchResult: Identifiable, Equatable {
    public var id: String { package }
    public var package: String
    public var description: String

    public static func parseSearchOutput(_ output: String) -> [APMSearchResult] {
        var results: [APMSearchResult] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("─") || trimmed.hasPrefix("-") || trimmed.lowercased().hasPrefix("name") || trimmed.lowercased().hasPrefix("searching") {
                continue
            }
            let parts = trimmed.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count >= 2, parts[0].contains("/") || !parts[0].contains(" ") {
                results.append(APMSearchResult(package: parts[0], description: parts.dropFirst().joined(separator: " — ")))
            } else if trimmed.contains("/") && !trimmed.contains(" ") {
                results.append(APMSearchResult(package: trimmed, description: "APM Package"))
            }
        }
        return results
    }
}

public struct APMMarketplace: Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var repo: String

    public static func parseMarketplaceList(_ output: String) -> [APMMarketplace] {
        var items: [APMMarketplace] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("─") || trimmed.hasPrefix("-") || trimmed.lowercased().hasPrefix("name") || trimmed.lowercased().hasPrefix("no marketplaces") {
                continue
            }
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2 {
                items.append(APMMarketplace(name: parts[0], repo: parts[1]))
            } else if parts.count == 1 && parts[0].contains("/") {
                items.append(APMMarketplace(name: parts[0], repo: parts[0]))
            }
        }
        return items
    }
}

public enum WorkspaceScope: Hashable, Identifiable {
    case global
    case project(String)

    public var id: String {
        switch self {
        case .global: return "global"
        case .project(let path): return path
        }
    }

    public var displayName: String {
        switch self {
        case .global: return "Global (~/.apm)"
        case .project(let path): return URL(fileURLWithPath: path).lastPathComponent
        }
    }

    public var directoryURL: URL {
        switch self {
        case .global:
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".apm")
        case .project(let path):
            return URL(fileURLWithPath: path)
        }
    }
}

@Observable
@MainActor
public final class APMClient {
    public var binaryPath: String?
    public var cliVersion: String?
    public var scope: WorkspaceScope = .global
    public var savedProjects: [String] = []
    public var manifest: APMManifest = APMManifest()
    public var rawYAML: String = ""
    public var hasManifestFile: Bool = false
    public var lockfilePackages: [String] = []
    public var searchResults: [APMSearchResult] = []
    public var marketplaces: [APMMarketplace] = []
    public var detectedTargets: [APMTargetInfo] = APMTargetInfo.defaultTargets
    public var isRunning: Bool = false
    public var lastCommand: String = "Ready"
    public var consoleLog: String = ""

    private let projectsKey = "APMDesktop.savedProjects"

    public init() {
        self.savedProjects = UserDefaults.standard.stringArray(forKey: projectsKey) ?? []
        if let first = savedProjects.first {
            self.scope = .project(first)
        }
        loadWorkspace()
        Task {
            await detectBinary()
        }
    }

    public var manifestURL: URL {
        scope.directoryURL.appendingPathComponent("apm.yml")
    }

    public var lockfileURL: URL {
        scope.directoryURL.appendingPathComponent("apm.lock.yaml")
    }

    public func detectBinary() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/apm",
            "/usr/local/bin/apm",
            "\(home)/.local/bin/apm",
            "\(home)/.apm/bin/apm"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            binaryPath = path
            let (_, out) = await runProcess(executable: path, args: ["--version"], logToConsole: false)
            cliVersion = out.trimmingCharacters(in: .whitespacesAndNewlines)
            await refreshTargets()
            await refreshMarketplaces()
            return
        }

        let (code, whichOut) = await runProcess(executable: "/usr/bin/env", args: ["which", "apm"], logToConsole: false)
        let resolved = whichOut.trimmingCharacters(in: .whitespacesAndNewlines)
        if code == 0, !resolved.isEmpty, FileManager.default.isExecutableFile(atPath: resolved) {
            binaryPath = resolved
            let (_, verOut) = await runProcess(executable: resolved, args: ["--version"], logToConsole: false)
            cliVersion = verOut.trimmingCharacters(in: .whitespacesAndNewlines)
            await refreshTargets()
            await refreshMarketplaces()
        } else {
            binaryPath = nil
            cliVersion = nil
        }
    }

    public func installCLI() async {
        let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        if let brew = brewPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            _ = await runProcess(executable: brew, args: ["install", "apm"], logToConsole: true)
        } else {
            _ = await runProcess(executable: "/bin/sh", args: ["-c", "curl -sSL https://aka.ms/apm-unix | sh"], logToConsole: true)
        }
        await detectBinary()
    }

    public func selectScope(_ newScope: WorkspaceScope) {
        scope = newScope
        loadWorkspace()
        Task {
            await refreshTargets()
        }
    }

    public func addProjectFolder(_ path: String) {
        if !savedProjects.contains(path) {
            savedProjects.append(path)
            UserDefaults.standard.set(savedProjects, forKey: projectsKey)
        }
        selectScope(.project(path))
    }

    public func removeProjectFolder(_ path: String) {
        savedProjects.removeAll { $0 == path }
        UserDefaults.standard.set(savedProjects, forKey: projectsKey)
        if scope == .project(path) {
            selectScope(savedProjects.first.map { .project($0) } ?? .global)
        }
    }

    public func loadWorkspace() {
        let dir = scope.directoryURL
        if let yaml = try? String(contentsOf: manifestURL, encoding: .utf8) {
            hasManifestFile = true
            rawYAML = yaml
            manifest = APMManifest.parse(yaml)
        } else {
            hasManifestFile = false
            manifest = APMManifest(name: dir.lastPathComponent)
            rawYAML = manifest.toYAML()
        }

        if let lockText = try? String(contentsOf: lockfileURL, encoding: .utf8) {
            lockfilePackages = lockText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("name:") || $0.hasPrefix("- name:") || $0.hasPrefix("resolved:") }
        } else {
            lockfilePackages = []
        }

        // Fallback local directory auto-detection for targets
        var targets = APMTargetInfo.defaultTargets
        for i in targets.indices {
            let folderPath = dir.appendingPathComponent(targets[i].outputDir).path
            targets[i].detected = FileManager.default.fileExists(atPath: folderPath)
        }
        detectedTargets = targets
    }

    public func saveRawYAML() {
        do {
            try FileManager.default.createDirectory(at: scope.directoryURL, withIntermediateDirectories: true)
            try rawYAML.write(to: manifestURL, atomically: true, encoding: .utf8)
            hasManifestFile = true
            manifest = APMManifest.parse(rawYAML)
            appendLog("Saved \(manifestURL.path)")
        } catch {
            appendLog("Error saving apm.yml: \(error.localizedDescription)")
        }
    }

    public func syncManifestToYAML() {
        rawYAML = manifest.toYAML()
        saveRawYAML()
    }

    public func initManifest() async {
        try? FileManager.default.createDirectory(at: scope.directoryURL, withIntermediateDirectories: true)
        if binaryPath != nil {
            var args = ["init", "--yes"]
            if scope == .global { args.append("-g") }
            _ = await runAPM(args)
        }
        if !FileManager.default.fileExists(atPath: manifestURL.path) {
            manifest = APMManifest(name: scope.directoryURL.lastPathComponent)
            syncManifestToYAML()
        } else {
            loadWorkspace()
        }
    }

    public func installAll() async {
        var args = ["install"]
        if scope == .global { args.append("-g") }
        _ = await runAPM(args)
        loadWorkspace()
    }

    public func updateAll() async {
        var args = ["update"]
        if scope == .global { args.append("-g") }
        _ = await runAPM(args)
        loadWorkspace()
    }

    public func installPackage(_ pkg: String, isMCP: Bool = false, transport: String = "http") async {
        let trimmed = pkg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if isMCP {
            if !manifest.mcpDependencies.contains(where: { $0.name == trimmed }) {
                manifest.mcpDependencies.append(APMMCPServer(name: trimmed, transport: transport))
                syncManifestToYAML()
            }
            if binaryPath != nil {
                var args = ["install", "--mcp", trimmed, "--transport", transport]
                if scope == .global { args.append("-g") }
                _ = await runAPM(args)
            }
        } else {
            if !manifest.apmDependencies.contains(trimmed) {
                manifest.apmDependencies.append(trimmed)
                syncManifestToYAML()
            }
            if binaryPath != nil {
                var args = ["install", trimmed]
                if scope == .global { args.append("-g") }
                _ = await runAPM(args)
            }
        }
        loadWorkspace()
    }

    public func uninstallPackage(_ pkg: String, isMCP: Bool = false) async {
        if isMCP {
            manifest.mcpDependencies.removeAll { $0.name == pkg }
        } else {
            manifest.apmDependencies.removeAll { $0 == pkg }
        }
        syncManifestToYAML()
        if binaryPath != nil {
            var args = ["uninstall", pkg]
            if scope == .global { args.append("-g") }
            _ = await runAPM(args)
        }
        loadWorkspace()
    }

    public func toggleTarget(_ target: String) {
        if let idx = manifest.targets.firstIndex(of: target) {
            manifest.targets.remove(at: idx)
        } else {
            manifest.targets.append(target)
        }
        syncManifestToYAML()
    }

    public func compileTargets() async {
        var args = ["compile"]
        if !manifest.targets.isEmpty {
            args.append(contentsOf: ["-t", manifest.targets.joined(separator: ",")])
        } else {
            args.append("--all")
        }
        _ = await runAPM(args)
        await refreshTargets()
    }

    public func refreshTargets() async {
        guard binaryPath != nil else { return }
        let (code, out) = await runAPM(["targets", "--json"], logToConsole: false)
        if code == 0, let data = out.data(using: .utf8), let parsed = APMTargetInfo.parseTargetsJSON(data) {
            detectedTargets = parsed
        }
    }

    public func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let (_, out) = await runAPM(["search", trimmed])
        searchResults = APMSearchResult.parseSearchOutput(out)
    }

    public func refreshMarketplaces() async {
        guard binaryPath != nil else { return }
        let (_, out) = await runAPM(["marketplace", "list"], logToConsole: false)
        marketplaces = APMMarketplace.parseMarketplaceList(out)
    }

    public func addMarketplace(_ repo: String) async {
        let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = await runAPM(["marketplace", "add", trimmed])
        await refreshMarketplaces()
    }

    public func updateMarketplaces() async {
        _ = await runAPM(["marketplace", "update"])
        await refreshMarketplaces()
    }

    public func removeMarketplace(_ name: String) async {
        _ = await runAPM(["marketplace", "remove", name])
        await refreshMarketplaces()
    }

    @discardableResult
    public func runAPM(_ args: [String], logToConsole: Bool = true) async -> (Int32, String) {
        guard let bin = binaryPath else {
            let msg = "apm CLI is not installed. Click 'Install APM CLI' in the sidebar or run `brew install apm`."
            if logToConsole { appendLog(msg) }
            return (127, msg)
        }
        return await runProcess(executable: bin, args: args, workingDirectory: scope.directoryURL, logToConsole: logToConsole)
    }

    private func runProcess(
        executable: String,
        args: [String],
        workingDirectory: URL? = nil,
        logToConsole: Bool
    ) async -> (Int32, String) {
        let cmdDisplay = ([URL(fileURLWithPath: executable).lastPathComponent] + args).joined(separator: " ")
        if logToConsole {
            isRunning = true
            lastCommand = cmdDisplay
            appendLog("$ \(cmdDisplay)")
        }
        defer {
            if logToConsole { isRunning = false }
        }

        let workDir = workingDirectory
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args

                var env = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let extraPaths = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:\(home)/.apm/bin"
                env["PATH"] = "\(extraPaths):\(env["PATH"] ?? "/usr/bin:/bin")"
                process.environment = env

                if let dir = workDir {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    process.currentDirectoryURL = dir
                }

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    Task { @MainActor in
                        if logToConsole && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.appendLog(output.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        continuation.resume(returning: (process.terminationStatus, output))
                    }
                } catch {
                    let errText = "Failed to run \(cmdDisplay): \(error.localizedDescription)"
                    Task { @MainActor in
                        if logToConsole { self.appendLog(errText) }
                        continuation.resume(returning: (-1, errText))
                    }
                }
            }
        }
    }

    private func appendLog(_ text: String) {
        if consoleLog.isEmpty {
            consoleLog = text
        } else {
            consoleLog += "\n" + text
        }
    }
}
