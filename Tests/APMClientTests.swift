import XCTest
@testable import AgentPackageManagerDesktop

final class APMClientTests: XCTestCase {
    func testManifestRoundTrip() {
        let sampleYAML = """
        name: demo-workspace
        version: 1.2.0
        description: "Team agent config"
        targets:
          - copilot
          - claude
          - gemini

        dependencies:
          apm:
            - anthropics/skills/skills/frontend-design
            - microsoft/apm-sample-package#v1.0.0
          mcp:
            - name: io.github.github/github-mcp-server
              transport: http
        """

        let parsed = APMManifest.parse(sampleYAML)
        XCTAssertEqual(parsed.name, "demo-workspace")
        XCTAssertEqual(parsed.version, "1.2.0")
        XCTAssertEqual(parsed.description, "Team agent config")
        XCTAssertEqual(parsed.targets, ["copilot", "claude", "gemini"])
        XCTAssertEqual(parsed.apmDependencies, [
            "anthropics/skills/skills/frontend-design",
            "microsoft/apm-sample-package#v1.0.0"
        ])
        XCTAssertEqual(parsed.mcpDependencies, [
            APMMCPServer(name: "io.github.github/github-mcp-server", transport: "http")
        ])

        let reserialized = APMManifest.parse(parsed.toYAML())
        XCTAssertEqual(reserialized, parsed)
    }

    func testTargetsJSONParsing() throws {
        let json = """
        [
          {"name": "claude", "detected": true, "output_dir": ".claude/"},
          {"name": "cursor", "detected": false, "output_dir": ".cursor/"}
        ]
        """.data(using: .utf8)!

        let targets = APMTargetInfo.parseTargetsJSON(json)
        XCTAssertEqual(targets?.count, 2)
        XCTAssertEqual(targets?.first?.name, "claude")
        XCTAssertEqual(targets?.first?.detected, true)
        XCTAssertEqual(targets?.first?.outputDir, ".claude/")
    }
}
