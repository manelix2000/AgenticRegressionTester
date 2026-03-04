import ArgumentParser
import Foundation

struct Skill: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skill",
        abstract: "Manage QA testing skill templates for LLM agents",
        subcommands: [Generate.self],
        defaultSubcommand: Generate.self
    )
}

extension Skill {
    struct Generate: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate and install a project-specific QA testing skill",
            discussion: """
            Creates a customized QA testing skill for LLM agents (Claude, GitHub Copilot, etc.).
            The skill includes:
            - Professional QA agent persona and workflow
            - Complete CLI command reference
            - Project-specific test scenarios template
            
            The generated skill can be used with:
            - GitHub Copilot CLI (automatically detected in ~/.copilot/skills/)
            - Claude Desktop (via MCP configuration)
            - Any LLM API/SDK (by loading the SKILL.md prompt)
            
            Examples:
              # Interactive mode (prompts for all values)
              agent-cli skill generate
              
              # Non-interactive mode
              agent-cli skill generate \\
                --project-name "MyApp" \\
                --bundle-id "com.example.myapp" \\
                --output ~/.copilot/skills/myapp-qa-skill
              
              # Generate to custom location
              agent-cli skill generate \\
                --project-name "MyApp" \\
                --bundle-id "com.example.myapp" \\
                --output ./skills/myapp-qa
            """
        )
        
        @Option(name: .shortAndLong, help: "Project name (e.g., 'MyApp')")
        var projectName: String?
        
        @Option(name: .shortAndLong, help: "iOS app bundle ID (e.g., 'com.example.myapp')")
        var bundleId: String?
        
        @Option(name: .shortAndLong, help: "Output directory for generated skill")
        var output: String?
        
        @Flag(name: .long, help: "Output in JSON format")
        var json: Bool = false
        
        func run() throws {
            // Get project name (prompt if not provided)
            let projectName = try getProjectName()
            
            // Get bundle ID (prompt if not provided)
            let bundleId = try getBundleId()
            
            // Determine output directory
            let outputDir = try getOutputDirectory(projectName: projectName)
            
            // Show summary
            if !json {
                print("📦 Generating QA Skill")
                print("   Project: \(projectName)")
                print("   Bundle ID: \(bundleId)")
                print("   Output: \(outputDir)")
                print()
            }
            
            // Create skill
            try createSkill(
                projectName: projectName,
                bundleId: bundleId,
                outputDir: outputDir
            )
            
            // Output results
            if json {
                let response = SkillGenerateResponse(
                    projectName: projectName,
                    bundleId: bundleId,
                    outputDirectory: outputDir,
                    files: [
                        "\(outputDir)/SKILL.md",
                        "\(outputDir)/references/SCENARIOS.md",
                        "\(outputDir)/references/CLI-COMMANDS.md"
                    ]
                )
                JSONOutput.success(response)
            } else {
                printSuccessMessage(projectName: projectName, outputDir: outputDir)
            }
        }
        
        // MARK: - Input Helpers
        
        private func getProjectName() throws -> String {
            if let name = projectName {
                return name
            }
            
            if json {
                throw ValidationError("--project-name is required in JSON mode")
            }
            
            print("Enter project name (e.g., 'MyApp'): ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces),
                  !input.isEmpty else {
                throw ValidationError("Project name cannot be empty")
            }
            return input
        }
        
        private func getBundleId() throws -> String {
            if let id = bundleId {
                return id
            }
            
            if json {
                throw ValidationError("--bundle-id is required in JSON mode")
            }
            
            print("Enter app bundle ID (e.g., 'com.example.myapp'): ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces),
                  !input.isEmpty else {
                throw ValidationError("Bundle ID cannot be empty")
            }
            return input
        }
        
        private func getOutputDirectory(projectName: String) throws -> String {
            if let dir = output {
                return NSString(string: dir).expandingTildeInPath
            }
            
            // Default: ~/.copilot/skills/{project-name}-qa-skill
            let skillName = projectName.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
            
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let defaultDir = "\(homeDir)/.copilot/skills/\(skillName)-qa-skill"
            
            if json {
                return defaultDir
            }
            
            print("Output directory [\(defaultDir)]: ", terminator: "")
            let input = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
            
            if input.isEmpty {
                return defaultDir
            }
            
            return NSString(string: input).expandingTildeInPath
        }
        
        // MARK: - Skill Creation
        
        private func createSkill(projectName: String, bundleId: String, outputDir: String) throws {
            let fileManager = FileManager.default
            
            // Calculate skill name (lowercase, hyphenated)
            let skillName = projectName.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
            let fullSkillName = "\(skillName)-qa-skill"
            
            // Find skill template directory
            guard let templateDir = findSkillTemplateDirectory() else {
                throw ValidationError("Could not locate skill template directory. Ensure agent-cli is properly installed.")
            }
            
            if !json {
                print("🔍 Found skill template: \(templateDir)")
            }
            
            // Create output directory
            try fileManager.createDirectory(
                atPath: outputDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            // Create references subdirectory
            let referencesDir = "\(outputDir)/references"
            try fileManager.createDirectory(
                atPath: referencesDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            if !json {
                print("📁 Created directory: \(outputDir)")
            }
            
            // Get IOS_AGENT_DRIVER_DIR from environment
            let iosAgentDriverDir = ProcessInfo.processInfo.environment["IOS_AGENT_DRIVER_DIR"] ?? "[IOS_AGENT_DRIVER_DIR not set]"
            
            // Copy and process files
            try copyAndProcessFile(
                from: "\(templateDir)/SKILL.md",
                to: "\(outputDir)/SKILL.md",
                replacements: [
                    "{{SKILL_NAME}}": fullSkillName,
                    "{{PROJECT_NAME}}": projectName,
                    "{{APP_BUNDLE_ID}}": bundleId,
                    "{{IOS_AGENT_DRIVER_DIR}}": iosAgentDriverDir
                ]
            )
            
            // Copy CLI-COMMANDS.md unchanged
            try fileManager.copyItem(
                atPath: "\(templateDir)/references/SCENARIOS.md",
                toPath: "\(referencesDir)/SCENARIOS.md"
            )
            
            // Copy CLI-COMMANDS.md unchanged
            try fileManager.copyItem(
                atPath: "\(templateDir)/references/CLI-COMMANDS.md",
                toPath: "\(referencesDir)/CLI-COMMANDS.md"
            )
            
            if !json {
                print("✅ Created SKILL.md (customized)")
                print("✅ Created references/SCENARIOS.md (unchanged)")
                print("✅ Created references/CLI-COMMANDS.md (unchanged)")
            }
        }
        
        private func findSkillTemplateDirectory() -> String? {
            let fileManager = FileManager.default
            
            // Strategy 1: Relative to executable (development mode)
            let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            let devPath = executableURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("skill")
                .path
            
            if fileManager.fileExists(atPath: devPath) {
                return devPath
            }
            
            // Strategy 2: Check IOS_AGENT_DRIVER_DIR environment variable
            if let iosAgentDriverDir = ProcessInfo.processInfo.environment["IOS_AGENT_DRIVER_DIR"] {
                let envPath = "\(iosAgentDriverDir)/agent-cli/skill"
                if fileManager.fileExists(atPath: envPath) {
                    return envPath
                }
            }
            
            // Strategy 3: Relative to current working directory
            let cwdPath = fileManager.currentDirectoryPath + "/skill"
            if fileManager.fileExists(atPath: cwdPath) {
                return cwdPath
            }
            
            // Strategy 4: Check common installation paths
            let commonPaths = [
                "/usr/local/share/agent-cli/skill",
                NSString(string: "~/.agent-cli/skill").expandingTildeInPath,
                fileManager.currentDirectoryPath + "/agent-cli/skill"
            ]
            
            for path in commonPaths {
                if fileManager.fileExists(atPath: path) {
                    return path
                }
            }
            
            return nil
        }
        
        private func copyAndProcessFile(
            from sourcePath: String,
            to destPath: String,
            replacements: [String: String]
        ) throws {
            // Read source file
            guard var content = try? String(contentsOfFile: sourcePath, encoding: .utf8) else {
                throw ValidationError("Could not read file: \(sourcePath)")
            }
            
            // Apply replacements
            for (placeholder, value) in replacements {
                content = content.replacingOccurrences(of: placeholder, with: value)
            }
            
            // Write to destination
            try content.write(toFile: destPath, atomically: true, encoding: .utf8)
        }
        
        // MARK: - Output
        
        private func printSuccessMessage(projectName: String, outputDir: String) {
            print()
            print("✅ Skill generated successfully!")
            print()
            print("📁 Location: \(outputDir)")
            print()
            print("📋 Next Steps:")
            print()
            print("1. Customize SCENARIOS.md with your test cases:")
            print("   \(outputDir)/references/SCENARIOS.md")
            print()
            print("2. Use with your LLM agent:")
            print()
            print("   GitHub Copilot CLI:")
            print("   $ gh copilot \"using \(projectName.lowercased())-qa-skill, test the login flow\"")
            print()
            print("   Claude Desktop (add to claude_desktop_config.json):")
            print("   {")
            print("     \"mcpServers\": {")
            print("       \"\(projectName.lowercased())-qa\": {")
            print("         \"command\": \"agent-cli\",")
            print("         \"args\": [\"skill\", \"serve\", \"\(outputDir)\"]")
            print("       }")
            print("     }")
            print("   }")
            print()
            print("   Or load SKILL.md as system prompt in any LLM API")
            print()
        }
    }
}

// MARK: - Response Models

struct SkillGenerateResponse: Codable {
    let projectName: String
    let bundleId: String
    let outputDirectory: String
    let files: [String]
}
