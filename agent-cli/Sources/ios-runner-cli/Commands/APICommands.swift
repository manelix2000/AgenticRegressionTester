import Foundation
import ArgumentParser

struct APICommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "api",
        abstract: "Interact with IOSAgentDriver API",
        discussion: """
            Execute IOSAgentDriver API commands on active sessions.
            
            All commands require a session ID and support --json output for machine-readable results.
            
            \(ColorPrint.header("Command Groups:"))
            
              \(ColorPrint.label("App Management:")) launch-app, terminate-app, app-state, install-app
              \(ColorPrint.label("UI Discovery:")) get-ui-tree, find-elements, get-element
              \(ColorPrint.label("Interactions:")) tap, type-text, swipe
              \(ColorPrint.label("Screenshots:")) screenshot
              \(ColorPrint.label("Validation:")) wait-for-element, assert
              \(ColorPrint.label("Configuration:")) get-config, set-timeout
              \(ColorPrint.label("Alerts:")) detect-alert, dismiss-alert
            
            \(ColorPrint.header("Examples:"))
            
              \(ColorPrint.comment("# Check runner health"))
              \(ColorPrint.code("agent-cli api health <session-id>"))
            
              \(ColorPrint.comment("# Launch an app"))
              \(ColorPrint.code("agent-cli api launch-app <session-id> com.apple.mobilesafari"))
            
              \(ColorPrint.comment("# Tap an element"))
              \(ColorPrint.code("agent-cli api tap <session-id> loginButton"))
            
              \(ColorPrint.comment("# Get JSON output"))
              \(ColorPrint.code("agent-cli api health <session-id> --json"))
            """,
        subcommands: [
            // Foundation
            Health.self,
            
            // App Management
            LaunchApp.self,
            TerminateApp.self,
            AppState.self,
            InstallApp.self,
            
            // UI Discovery
            GetUITree.self,
            FindElements.self,
            FindElement.self,
            GetElement.self,
            
            // Interactions
            Tap.self,
            TypeText.self,
            Swipe.self,
            
            // Screenshots
            Screenshot.self,
            
            // Validation
            WaitForElement.self,
            
            // Configuration
            GetConfig.self,
            SetTimeout.self,
            
            // Alerts
            DetectAlert.self,
            DismissAlert.self,
        ]
    )
}

// MARK: - Health Command

extension APICommands {
    struct Health: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "health",
            abstract: "Check IOSAgentDriver health status",
            discussion: """
                Queries the /health endpoint to verify IOSAgentDriver is responding.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Check health"))
                  \(ColorPrint.code("agent-cli api health abc123"))
                
                  \(ColorPrint.comment("# Get JSON output"))
                  \(ColorPrint.code("agent-cli api health abc123 --json"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            do {
                let response: HealthResponse = try await APIClient.shared.get("/health", sessionId: sessionId)
                
                if json {
                    let jsonResponse = APIResponse(
                        success: true,
                        data: response,
                        error: nil,
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("✅ IOSAgentDriver is healthy"))
                    print("   \(ColorPrint.label("Status:")) \(ColorPrint.value(response.status))")
                    if let version = response.version {
                        print("   \(ColorPrint.label("Version:")) \(ColorPrint.value(version))")
                    }
                    if let uptime = response.uptime {
                        print("   \(ColorPrint.label("Uptime:")) \(ColorPrint.value(String(format: "%.1fs", uptime)))")
                    }
                }
            } catch let error as APIClient.APIError {
                if json {
                    let jsonResponse = APIResponse<HealthResponse>(
                        success: false,
                        data: nil,
                        error: APIErrorDetail(
                            code: "api_error",
                            message: error.localizedDescription,
                            suggestion: nil
                        ),
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.error("❌ Health check failed"))
                    print("   \(error.localizedDescription)")
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Launch App Command

extension APICommands {
    struct LaunchApp: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "launch-app",
            abstract: "Launch an application",
            discussion: """
                Launches an app by bundle identifier on the simulator.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Launch Safari"))
                  \(ColorPrint.code("agent-cli api launch-app abc123 com.apple.mobilesafari"))
                
                  \(ColorPrint.comment("# Launch with arguments"))
                  \(ColorPrint.code("agent-cli api launch-app abc123 com.example.app --arguments arg1 arg2"))
                
                  \(ColorPrint.comment("# Get JSON output"))
                  \(ColorPrint.code("agent-cli api launch-app abc123 com.apple.mobilesafari --json"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Argument(help: "App bundle identifier")
        var bundleId: String
        
        @Option(name: .long, help: "Launch arguments")
        var arguments: [String] = []
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            let request = LaunchAppRequest(
                bundleId: bundleId,
                arguments: arguments.isEmpty ? nil : arguments,
                environment: nil
            )
            
            do {
                let response: LaunchAppResponse = try await APIClient.shared.post(
                    "/app/launch",
                    body: request,
                    sessionId: sessionId
                )
                
                if json {
                    let jsonResponse = APIResponse(
                        success: true,
                        data: response,
                        error: nil,
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("✅ App launched successfully"))
                    print("   \(ColorPrint.label("Bundle ID:")) \(ColorPrint.value(bundleId))")
                    if let pid = response.pid {
                        print("   \(ColorPrint.label("PID:")) \(ColorPrint.value(String(pid)))")
                    }
                }
            } catch let error as APIClient.APIError {
                if json {
                    let jsonResponse = APIResponse<LaunchAppResponse>(
                        success: false,
                        data: nil,
                        error: APIErrorDetail(
                            code: "launch_failed",
                            message: error.localizedDescription,
                            suggestion: "Verify the bundle ID is correct and the app is installed"
                        ),
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.error("❌ Failed to launch app"))
                    print("   \(error.localizedDescription)")
                    print("")
                    print(ColorPrint.info("💡 Suggestion: Verify the bundle ID is correct and the app is installed"))
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Terminate App Command

extension APICommands {
    struct TerminateApp: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "terminate-app",
            abstract: "Terminate a running application",
            discussion: """
                Terminates the currently running app. Bundle ID is optional.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Terminate the running app"))
                  \(ColorPrint.code("agent-cli api terminate-app abc123"))
                
                  \(ColorPrint.comment("# Terminate with bundle ID (optional)"))
                  \(ColorPrint.code("agent-cli api terminate-app abc123 com.apple.mobilesafari"))
                
                  \(ColorPrint.comment("# Get JSON output"))
                  \(ColorPrint.code("agent-cli api terminate-app abc123 --json"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Argument(help: "App bundle identifier (optional, ignored by server)")
        var bundleId: String?
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            let request = TerminateAppRequest(bundleId: bundleId ?? "")
            
            do {
                let response: TerminateAppResponse = try await APIClient.shared.post(
                    "/app/terminate",
                    body: request,
                    sessionId: sessionId
                )
                
                if json {
                    let jsonResponse = APIResponse(
                        success: true,
                        data: response,
                        error: nil,
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("✅ App terminated successfully"))
                    if let bundleId = bundleId {
                        print("   \(ColorPrint.label("Bundle ID:")) \(ColorPrint.value(bundleId))")
                    }
                }
            } catch let error as APIClient.APIError {
                if json {
                    let jsonResponse = APIResponse<TerminateAppResponse>(
                        success: false,
                        data: nil,
                        error: APIErrorDetail(
                            code: "terminate_failed",
                            message: error.localizedDescription,
                            suggestion: nil
                        ),
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.error("❌ Failed to terminate app"))
                    print("   \(error.localizedDescription)")
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - App State Command

extension APICommands {
    struct AppState: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "app-state",
            abstract: "Get application state",
            discussion: """
                Gets the current state of the application on the simulator.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Get app state"))
                  \(ColorPrint.code("agent-cli api app-state abc123"))
                
                  \(ColorPrint.comment("# Get JSON output"))
                  \(ColorPrint.code("agent-cli api app-state abc123 --json"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            do {
                let response: AppStateResponse = try await APIClient.shared.get("/app/state", sessionId: sessionId)
                
                if json {
                    let jsonResponse = APIResponse(
                        success: true,
                        data: response,
                        error: nil,
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("📱 App State"))
                    if let bundleId = response.bundleId {
                        print("   \(ColorPrint.label("Bundle ID:")) \(ColorPrint.value(bundleId))")
                    }
                    print("   \(ColorPrint.label("State:")) \(ColorPrint.value(response.state))")
                    if let pid = response.pid {
                        print("   \(ColorPrint.label("PID:")) \(ColorPrint.value(String(pid)))")
                    }
                }
            } catch let error as APIClient.APIError {
                if json {
                    let jsonResponse = APIResponse<AppStateResponse>(
                        success: false,
                        data: nil,
                        error: APIErrorDetail(
                            code: "state_failed",
                            message: error.localizedDescription,
                            suggestion: nil
                        ),
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.error("❌ Failed to get app state"))
                    print("   \(error.localizedDescription)")
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Install App Command

extension APICommands {
    struct InstallApp: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "install-app",
            abstract: "Install an app on the simulator",
            discussion: """
                Installs an .app bundle on the simulator associated with the session.
                Uses simctl to install the app directly on the simulator.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Install an app"))
                  \(ColorPrint.code("agent-cli api install-app abc123 /path/to/MyApp.app"))
                
                  \(ColorPrint.comment("# Install with absolute path"))
                  \(ColorPrint.code("agent-cli api install-app abc123 ~/Downloads/MyApp.app"))
                
                  \(ColorPrint.comment("# Get JSON output"))
                  \(ColorPrint.code("agent-cli api install-app abc123 /path/to/MyApp.app --json"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Argument(help: "Path to .app bundle")
        var appPath: String
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() throws {
            // Get session to find simulator UDID
            guard let session = SessionManager.shared.getSession(sessionId) else {
                if json {
                    let jsonResponse = APIResponse<[String: String]>(
                        success: false,
                        data: nil,
                        error: APIErrorDetail(
                            code: "session_not_found",
                            message: "Session not found: \(sessionId)",
                            suggestion: "Use 'agent-cli session list' to see available sessions"
                        ),
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.error("Session not found: \(sessionId)"))
                    print("")
                    print(ColorPrint.info("💡 Use '\(ColorPrint.code("agent-cli session list"))' to see available sessions"))
                }
                throw ExitCode.failure
            }
            
            // Expand tilde in path
            let expandedPath = NSString(string: appPath).expandingTildeInPath
            
            // Check if file exists
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: expandedPath) else {
                if json {
                    let jsonResponse = APIResponse<[String: String]>(
                        success: false,
                        data: nil,
                        error: APIErrorDetail(
                            code: "file_not_found",
                            message: "App bundle not found: \(expandedPath)",
                            suggestion: "Verify the path is correct and the file exists"
                        ),
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.error("App bundle not found: \(expandedPath)"))
                    print("")
                    print(ColorPrint.info("💡 Verify the path is correct and the file exists"))
                }
                throw ExitCode.failure
            }
            
            // Check if it's a .app bundle
            guard expandedPath.hasSuffix(".app") else {
                if json {
                    let jsonResponse = APIResponse<[String: String]>(
                        success: false,
                        data: nil,
                        error: APIErrorDetail(
                            code: "invalid_bundle",
                            message: "Path must point to a .app bundle: \(expandedPath)",
                            suggestion: "Provide a path ending in .app"
                        ),
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.error("Path must point to a .app bundle"))
                    print("   Got: \(expandedPath)")
                    print("")
                    print(ColorPrint.info("💡 Provide a path ending in .app"))
                }
                throw ExitCode.failure
            }
            
            // Install app using simctl
            if !json {
                print(ColorPrint.loading("Installing app on simulator..."))
                print("   \(ColorPrint.label("Session:")) \(ColorPrint.value(sessionId))")
                print("   \(ColorPrint.label("Simulator:")) \(session.simulatorUDID.colored(.dim))")
                print("   \(ColorPrint.label("App:")) \(ColorPrint.value(expandedPath))")
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "install", session.simulatorUDID, expandedPath]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                guard process.terminationStatus == 0 else {
                    if json {
                        let jsonResponse = APIResponse<[String: String]>(
                            success: false,
                            data: nil,
                            error: APIErrorDetail(
                                code: "install_failed",
                                message: "simctl install failed: \(output)",
                                suggestion: "Verify the simulator is booted and the app bundle is valid"
                            ),
                            executionTime: nil
                        )
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        let data = try encoder.encode(jsonResponse)
                        if let jsonString = String(data: data, encoding: .utf8) {
                            print(jsonString)
                        }
                    } else {
                        print(ColorPrint.error("Failed to install app"))
                        print("   \(output)")
                        print("")
                        print(ColorPrint.info("💡 Verify the simulator is booted and the app bundle is valid"))
                    }
                    throw ExitCode.failure
                }
                
                // Extract bundle ID from Info.plist
                let infoPlistPath = "\(expandedPath)/Info.plist"
                var bundleId: String?
                
                if fileManager.fileExists(atPath: infoPlistPath) {
                    let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath))
                    if let data = plistData,
                       let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                       let bid = plist["CFBundleIdentifier"] as? String {
                        bundleId = bid
                    }
                }
                
                if json {
                    let result: [String: String] = [
                        "simulator": session.simulatorUDID,
                        "appPath": expandedPath,
                        "bundleId": bundleId ?? "unknown"
                    ]
                    let jsonResponse = APIResponse(
                        success: true,
                        data: result,
                        error: nil,
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("✅ App installed successfully"))
                    if let bid = bundleId {
                        print("   \(ColorPrint.label("Bundle ID:")) \(ColorPrint.value(bid))")
                    }
                    print("")
                    print(ColorPrint.info("💡 Launch the app with:"))
                    if let bid = bundleId {
                        print("   \(ColorPrint.code("agent-cli api launch-app \(sessionId) \(bid)"))")
                    }
                }
            } catch {
                if json {
                    let jsonResponse = APIResponse<[String: String]>(
                        success: false,
                        data: nil,
                        error: APIErrorDetail(
                            code: "process_error",
                            message: "Failed to execute simctl: \(error.localizedDescription)",
                            suggestion: nil
                        ),
                        executionTime: nil
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.error("Failed to execute simctl"))
                    print("   \(error.localizedDescription)")
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - UI Discovery Commands

extension APICommands {
    struct GetUITree: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get-ui-tree",
            abstract: "Get the UI element tree",
            discussion: """
                Retrieves the accessibility tree of the current app up to a maximum depth.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Get UI tree (default depth: 20)"))
                  \(ColorPrint.code("agent-cli api get-ui-tree abc123"))
                
                  \(ColorPrint.comment("# Get UI tree with custom depth"))
                  \(ColorPrint.code("agent-cli api get-ui-tree abc123 --depth 10"))
                
                  \(ColorPrint.comment("# Get JSON output"))
                  \(ColorPrint.code("agent-cli api get-ui-tree abc123 --json"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Option(name: .long, help: "Maximum tree depth")
        var depth: Int = 20
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            do {
                let response: GetUITreeResponse = try await APIClient.shared.get(
                    "/ui/tree?maxDepth=\(depth)",
                    sessionId: sessionId
                )
                
                if json {
                    let jsonResponse = APIResponse(success: true, data: response, error: nil, executionTime: nil)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("📱 UI Tree"))
                    printUINode(response.root, indent: 0)
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "ui_tree_failed")
            }
        }
        
        private func printUINode(_ node: UINode, indent: Int) {
            let prefix = String(repeating: "  ", count: indent)
            print("\(prefix)• \(ColorPrint.value(node.type))")
            if !node.identifier.isEmpty {
                print("\(prefix)  \(ColorPrint.label("ID:")) \(node.identifier)")
            }
            if !node.label.isEmpty {
                print("\(prefix)  \(ColorPrint.label("Label:")) \(node.label)")
            }
            if !node.children.isEmpty {
                for child in node.children {
                    printUINode(child, indent: indent + 1)
                }
            }
        }
    }
    
    struct FindElements: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "find-elements",
            abstract: "Find UI elements by predicate",
            discussion: """
                Finds all elements matching the given predicate.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Find buttons"))
                  \(ColorPrint.code("agent-cli api find-elements abc123 'type == \"Button\"'"))
                
                  \(ColorPrint.comment("# Find by identifier"))
                  \(ColorPrint.code("agent-cli api find-elements abc123 'identifier == \"loginButton\"'"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Argument(help: "Predicate string")
        var predicate: String
        
        @Option(name: .long, help: "Timeout in seconds")
        var timeout: Double = 5.0
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            let request = FindElementsRequest(predicate: predicate, identifier: nil, timeout: timeout, waitStrategy: nil)
            
            do {
                let response: FindElementsResponse = try await APIClient.shared.post("/ui/find", body: request, sessionId: sessionId)
                
                if json {
                    let jsonResponse = APIResponse(success: true, data: response, error: nil, executionTime: nil)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("Found \(response.elements.count) element(s)"))
                    for (i, element) in response.elements.enumerated() {
                        print("\n\(i + 1). \(ColorPrint.value(element.type))")
                        if !element.identifier.isEmpty {
                            print("   \(ColorPrint.label("ID:")) \(element.identifier)")
                        }
                        if !element.label.isEmpty {
                            print("   \(ColorPrint.label("Label:")) \(element.label)")
                        }
                    }
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "find_failed")
            }
        }
    }
    
    struct FindElement: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "find-element",
            abstract: "Find first UI element by predicate",
            discussion: """
                Finds the first element matching the given predicate.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Find element"))
                  \(ColorPrint.code("agent-cli api find-element abc123 'identifier == \"loginButton\"'"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Argument(help: "Predicate string")
        var predicate: String
        
        @Option(name: .long, help: "Timeout in seconds")
        var timeout: Double = 5.0
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            let request = FindElementsRequest(predicate: predicate, identifier: nil, timeout: timeout, waitStrategy: nil)
            
            do {
                let response: FindElementsResponse = try await APIClient.shared.post("/ui/find", body: request, sessionId: sessionId)
                
                guard let element = response.elements.first else {
                    print(ColorPrint.error("No elements found matching predicate"))
                    throw ExitCode.failure
                }
                
                if json {
                    let jsonResponse = APIResponse(success: true, data: ["element": element], error: nil, executionTime: nil)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("Found element"))
                    print("   \(ColorPrint.label("Type:")) \(ColorPrint.value(element.type))")
                    if !element.identifier.isEmpty {
                        print("   \(ColorPrint.label("ID:")) \(element.identifier)")
                    }
                    if !element.label.isEmpty {
                        print("   \(ColorPrint.label("Label:")) \(element.label)")
                    }
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "element_not_found")
            }
        }
    }
    
    struct GetElement: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get-element",
            abstract: "Get UI element by identifier",
            discussion: """
                Gets element details by accessibility identifier.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.code("agent-cli api get-element abc123 loginButton"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Argument(help: "Element identifier")
        var identifier: String
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            // URL encode the identifier to handle special characters
            guard let encodedIdentifier = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                print(ColorPrint.error("Failed to encode identifier"))
                throw ExitCode.failure
            }
            
            do {
                let response: GetElementResponse = try await APIClient.shared.get("/ui/element/\(encodedIdentifier)", sessionId: sessionId)
                
                if json {
                    let jsonResponse = APIResponse(success: true, data: response, error: nil, executionTime: nil)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("Element details"))
                    print("   \(ColorPrint.label("Type:")) \(ColorPrint.value(response.element.type))")
                    print("   \(ColorPrint.label("ID:")) \(response.element.identifier)")
                    if !response.element.label.isEmpty {
                        print("   \(ColorPrint.label("Label:")) \(response.element.label)")
                    }
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "element_not_found")
            }
        }
    }
}

// MARK: - Interaction Commands

extension APICommands {
    struct Tap: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Tap a UI element",
            discussion: """
                Taps on the specified element using identifier, label, or predicate.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Tap by identifier (default)"))
                  \(ColorPrint.code("agent-cli api tap abc123 loginButton"))
                
                  \(ColorPrint.comment("# Tap by label"))
                  \(ColorPrint.code("agent-cli api tap abc123 \"Login\" --selector-type label"))
                
                  \(ColorPrint.comment("# Tap by predicate"))
                  \(ColorPrint.code("agent-cli api tap abc123 \"label == 'Login'\" --selector-type predicate"))
                
                  \(ColorPrint.comment("# Auto-detect (predicate if contains operators)"))
                  \(ColorPrint.code("agent-cli api tap abc123 \"label CONTAINS 'Log'\""))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Argument(help: "Element selector (identifier, label, or predicate)")
        var selector: String
        
        @Option(name: .long, help: "Selector type: id, label, or predicate (default: auto-detect)")
        var selectorType: String?
        
        @Option(name: .long, help: "Timeout in seconds")
        var timeout: Double?
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            let (identifier, label, predicate) = parseSelector(selector, type: selectorType)
            let request = TapRequest(identifier: identifier, label: label, predicate: predicate, timeout: timeout, waitStrategy: nil)
            
            do {
                let response: TapResponse = try await APIClient.shared.post("/ui/tap", body: request, sessionId: sessionId)
                
                if json {
                    let jsonResponse = APIResponse(success: true, data: response, error: nil, executionTime: nil)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("✅ Tapped element"))
                    if let id = identifier {
                        print("   \(ColorPrint.label("ID:")) \(id)")
                    } else if let lbl = label {
                        print("   \(ColorPrint.label("Label:")) \(lbl)")
                    } else if let pred = predicate {
                        print("   \(ColorPrint.label("Predicate:")) \(pred)")
                    }
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "tap_failed")
            }
        }
        
        private func parseSelector(_ selector: String, type: String?) -> (String?, String?, String?) {
            if let type = type {
                switch type.lowercased() {
                case "id", "identifier":
                    return (selector, nil, nil)
                case "label":
                    return (nil, selector, nil)
                case "predicate", "pred":
                    return (nil, nil, selector)
                default:
                    // Auto-detect
                    break
                }
            }
            
            // Auto-detect: if contains operators, it's likely a predicate
            if selector.contains("==") || selector.contains("CONTAINS") || selector.contains("MATCHES") || selector.contains("BEGINSWITH") {
                return (nil, nil, selector)
            }
            
            // Default to identifier
            return (selector, nil, nil)
        }
    }

    
    struct TypeText: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "type-text",
            abstract: "Type text into a UI element",
            discussion: """
                Types the specified text into an element using identifier, label, or predicate.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Type by identifier (default)"))
                  \(ColorPrint.code("agent-cli api type-text abc123 usernameField 'user@example.com'"))
                
                  \(ColorPrint.comment("# Type by label"))
                  \(ColorPrint.code("agent-cli api type-text abc123 \"Username\" 'user@example.com' --selector-type label"))
                
                  \(ColorPrint.comment("# Clear field before typing"))
                  \(ColorPrint.code("agent-cli api type-text abc123 emailField 'new@email.com' --clear"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Argument(help: "Element selector (identifier, label, or predicate)")
        var selector: String
        
        @Argument(help: "Text to type")
        var text: String
        
        @Option(name: .long, help: "Selector type: id, label, or predicate (default: auto-detect)")
        var selectorType: String?
        
        @Flag(name: .long, help: "Clear field before typing")
        var clear = false
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            let (identifier, label, predicate) = parseSelector(selector, type: selectorType)
            let request = TypeTextRequest(identifier: identifier, label: label, predicate: predicate, text: text, clearFirst: clear, timeout: nil, waitStrategy: nil)
            
            do {
                let response: TypeTextResponse = try await APIClient.shared.post("/ui/type", body: request, sessionId: sessionId)
                
                if json {
                    let jsonResponse = APIResponse(success: true, data: response, error: nil, executionTime: nil)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("✅ Typed text"))
                    if let id = identifier {
                        print("   \(ColorPrint.label("ID:")) \(id)")
                    } else if let lbl = label {
                        print("   \(ColorPrint.label("Label:")) \(lbl)")
                    } else if let pred = predicate {
                        print("   \(ColorPrint.label("Predicate:")) \(pred)")
                    }
                    print("   \(ColorPrint.label("Text:")) \(text)")
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "type_failed")
            }
        }
        
        private func parseSelector(_ selector: String, type: String?) -> (String?, String?, String?) {
            if let type = type {
                switch type.lowercased() {
                case "id", "identifier":
                    return (selector, nil, nil)
                case "label":
                    return (nil, selector, nil)
                case "predicate", "pred":
                    return (nil, nil, selector)
                default:
                    break
                }
            }
            
            // Auto-detect: if contains operators, it's likely a predicate
            if selector.contains("==") || selector.contains("CONTAINS") || selector.contains("MATCHES") || selector.contains("BEGINSWITH") {
                return (nil, nil, selector)
            }
            
            // Default to identifier
            return (selector, nil, nil)
        }
    }
    
    
    struct Swipe: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Swipe on a UI element",
            discussion: """
                Performs a swipe gesture on the specified element using identifier, label, or predicate.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Swipe by identifier (default)"))
                  \(ColorPrint.code("agent-cli api swipe abc123 scrollView up"))
                  \(ColorPrint.code("agent-cli api swipe abc123 tableView down"))
                
                  \(ColorPrint.comment("# Swipe by label"))
                  \(ColorPrint.code("agent-cli api swipe abc123 \"Main Content\" left --selector-type label"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Argument(help: "Element selector (identifier, label, or predicate)")
        var selector: String
        
        @Argument(help: "Direction (up, down, left, right)")
        var direction: String
        
        @Option(name: .long, help: "Selector type: id, label, or predicate (default: auto-detect)")
        var selectorType: String?
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            let (identifier, label, predicate) = parseSelector(selector, type: selectorType)
            let request = SwipeRequest(identifier: identifier, label: label, predicate: predicate, direction: direction, velocity: nil)
            
            do {
                let response: SwipeResponse = try await APIClient.shared.post("/ui/swipe", body: request, sessionId: sessionId)
                
                if json {
                    let jsonResponse = APIResponse(success: true, data: response, error: nil, executionTime: nil)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("✅ Swiped \(direction)"))
                    if let id = identifier {
                        print("   \(ColorPrint.label("ID:")) \(id)")
                    } else if let lbl = label {
                        print("   \(ColorPrint.label("Label:")) \(lbl)")
                    } else if let pred = predicate {
                        print("   \(ColorPrint.label("Predicate:")) \(pred)")
                    }
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "swipe_failed")
            }
        }
        
        private func parseSelector(_ selector: String, type: String?) -> (String?, String?, String?) {
            if let type = type {
                switch type.lowercased() {
                case "id", "identifier":
                    return (selector, nil, nil)
                case "label":
                    return (nil, selector, nil)
                case "predicate", "pred":
                    return (nil, nil, selector)
                default:
                    break
                }
            }
            
            // Auto-detect: if contains operators, it's likely a predicate
            if selector.contains("==") || selector.contains("CONTAINS") || selector.contains("MATCHES") || selector.contains("BEGINSWITH") {
                return (nil, nil, selector)
            }
            
            // Default to identifier
            return (selector, nil, nil)
        }
    }
}

// MARK: - Screenshot Commands

extension APICommands {
    struct Screenshot: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Take a screenshot",
            discussion: """
                Captures a screenshot of the simulator.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.code("agent-cli api screenshot abc123"))
                  \(ColorPrint.code("agent-cli api screenshot abc123 --json"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Option(name: .long, help: "Output path")
        var output: String?
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            do {
                let response: ScreenshotResponse = try await APIClient.shared.get("/screenshot", sessionId: sessionId)
                
                if let outputPath = output {
                    // Decode base64 and save to file
                    if let imageData = Data(base64Encoded: response.image) {
                        let url = URL(fileURLWithPath: NSString(string: outputPath).expandingTildeInPath)
                        try imageData.write(to: url)
                        
                        if json {
                            let result = ["path": outputPath, "width": String(response.width), "height": String(response.height)]
                            let jsonResponse = APIResponse(success: true, data: result, error: nil, executionTime: nil)
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                            let data = try encoder.encode(jsonResponse)
                            if let jsonString = String(data: data, encoding: .utf8) {
                                print(jsonString)
                            }
                        } else {
                            print(ColorPrint.success("✅ Screenshot saved"))
                            print("   \(ColorPrint.label("Path:")) \(outputPath)")
                            print("   \(ColorPrint.label("Size:")) \(response.width)x\(response.height)")
                        }
                    }
                } else {
                    if json {
                        let jsonResponse = APIResponse(success: true, data: response, error: nil, executionTime: nil)
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        let data = try encoder.encode(jsonResponse)
                        if let jsonString = String(data: data, encoding: .utf8) {
                            print(jsonString)
                        }
                    } else {
                        print(ColorPrint.success("✅ Screenshot captured"))
                        print("   \(ColorPrint.label("Size:")) \(response.width)x\(response.height)")
                        print("   \(ColorPrint.info("💡 Use --output to save to file"))")
                    }
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "screenshot_failed")
            }
        }
    }
}

// MARK: - Validation Commands

extension APICommands {
    struct WaitForElement: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "wait-for-element",
            abstract: "Wait for element condition",
            discussion: """
                Wait for an element to meet a specific condition using XCTest native waiting.
                
                \(ColorPrint.header("Supported Conditions:"))
                
                  • exists, notExists - Element presence
                  • isEnabled, isDisabled - Enabled state
                  • isHittable, isNotHittable - Hittable state
                  • hasFocus - Keyboard focus
                  • isSelected, isNotSelected - Selection state
                  • labelContains, labelEquals - Label text matching
                  • valueContains, valueEquals - Value matching
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Wait for element to exist"))
                  \(ColorPrint.code("agent-cli api wait-for-element abc123 loginButton"))
                
                  \(ColorPrint.comment("# Wait for button to be enabled"))
                  \(ColorPrint.code("agent-cli api wait-for-element abc123 submitButton --condition isEnabled"))
                
                  \(ColorPrint.comment("# Wait with soft validation (no exception)"))
                  \(ColorPrint.code("agent-cli api wait-for-element abc123 optionalBanner --soft-validation"))
                
                  \(ColorPrint.comment("# Wait for label to contain text"))
                  \(ColorPrint.code("agent-cli api wait-for-element abc123 statusLabel --condition labelContains --value Success"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Argument(help: "Element accessibility identifier or predicate")
        var identifier: String
        
        @Option(name: .long, help: "Wait condition (exists, isEnabled, isHittable, etc.)")
        var condition: String = "exists"
        
        @Option(name: .long, help: "Expected value for text/value conditions")
        var value: String?
        
        @Option(name: .long, help: "Timeout in seconds")
        var timeout: Double = 10.0
        
        @Flag(name: .long, help: "Soft validation (no exception on failure)")
        var softValidation = false
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            // Determine if identifier is a predicate (contains operators)
            let isPredicate = identifier.contains("==") || identifier.contains("CONTAINS") || identifier.contains("MATCHES")
            
            let request = WaitRequest(
                condition: condition,
                identifier: isPredicate ? nil : identifier,
                label: nil,
                predicate: isPredicate ? identifier : nil,
                value: value,
                timeout: timeout,
                softValidation: softValidation ? true : nil
            )
            
            do {
                let response: WaitResponse = try await APIClient.shared.post("/ui/wait", body: request, sessionId: sessionId)
                
                if json {
                    let jsonResponse = APIResponse(success: response.conditionMet, data: response, error: nil, executionTime: response.waitedTime)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    if response.conditionMet {
                        print(ColorPrint.success("✅ Condition met: \(response.condition)"))
                        print("   \(ColorPrint.label("Waited:")) \(String(format: "%.2f", response.waitedTime))s")
                        if let element = response.element {
                            print("   \(ColorPrint.label("Type:")) \(element.type)")
                            if !element.identifier.isEmpty {
                                print("   \(ColorPrint.label("ID:")) \(element.identifier)")
                            }
                            if !element.label.isEmpty {
                                print("   \(ColorPrint.label("Label:")) \(element.label)")
                            }
                        }
                    } else {
                        // Soft validation failure
                        print(ColorPrint.warning("⚠️  Condition not met: \(response.condition)"))
                        print("   \(ColorPrint.label("Waited:")) \(String(format: "%.2f", response.waitedTime))s")
                        if softValidation {
                            print("   \(ColorPrint.comment("(Soft validation - no exception thrown)"))")
                        }
                    }
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "wait_timeout")
            }
        }
    }
}

// MARK: - Configuration Commands

extension APICommands {
    struct GetConfig: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get-config",
            abstract: "Get runner configuration",
            discussion: """
                Retrieves the current IOSAgentDriver configuration.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.code("agent-cli api get-config abc123"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            do {
                let response: ConfigResponse = try await APIClient.shared.get("/config", sessionId: sessionId)
                
                if json {
                    let jsonResponse = APIResponse(success: true, data: response, error: nil, executionTime: nil)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("⚙️  Configuration"))
                    print("   \(ColorPrint.label("Timeout:")) \(response.config.defaultTimeout)s")
                    print("   \(ColorPrint.label("Verbosity:")) \(response.config.errorVerbosity)")
                    print("   \(ColorPrint.label("Max Requests:")) \(response.config.maxConcurrentRequests)")
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "config_failed")
            }
        }
    }
    
    struct SetTimeout: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-timeout",
            abstract: "Set default timeout",
            discussion: """
                Sets the default timeout for operations.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.code("agent-cli api set-timeout abc123 10"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Argument(help: "Timeout in seconds")
        var timeout: Double
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            let request = UpdateConfigRequest(defaultTimeout: timeout, errorVerbosity: nil)
            
            do {
                let response: UpdateConfigResponse = try await APIClient.shared.post("/config", body: request, sessionId: sessionId)
                
                if json {
                    let jsonResponse = APIResponse(success: true, data: response, error: nil, executionTime: nil)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("✅ Timeout updated to \(timeout)s"))
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "timeout_failed")
            }
        }
    }
}

// MARK: - Alert Commands

extension APICommands {
    struct DetectAlert: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "detect-alert",
            abstract: "Detect system alerts",
            discussion: """
                Detects any system alerts currently displayed.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.code("agent-cli api detect-alert abc123"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            do {
                let response: AlertsResponse = try await APIClient.shared.get("/ui/alerts", sessionId: sessionId)
                
                if json {
                    let jsonResponse = APIResponse(success: true, data: response, error: nil, executionTime: nil)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    if response.alerts.isEmpty {
                        print(ColorPrint.info("No alerts detected"))
                    } else {
                        print(ColorPrint.success("Found \(response.alerts.count) alert(s)"))
                        for (i, alert) in response.alerts.enumerated() {
                            print("\n\(i + 1). \(ColorPrint.value(alert.title ?? "Alert"))")
                            if let message = alert.message {
                                print("   \(ColorPrint.label("Message:")) \(message)")
                            }
                            print("   \(ColorPrint.label("Buttons:")) \(alert.buttons.joined(separator: ", "))")
                        }
                    }
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "alert_detection_failed")
            }
        }
    }
    
    struct DismissAlert: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "dismiss-alert",
            abstract: "Dismiss system alert",
            discussion: """
                Dismisses a system alert by tapping a button.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.code("agent-cli api dismiss-alert abc123 OK"))
                  \(ColorPrint.code("agent-cli api dismiss-alert abc123 Allow"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Argument(help: "Button label")
        var buttonLabel: String
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() async throws {
            let request = DismissAlertRequest(buttonLabel: buttonLabel)
            
            do {
                try await APIClient.shared.postNoResponse("/ui/alert/dismiss", body: request, sessionId: sessionId)
                
                if json {
                    let result = ["dismissed": "true", "button": buttonLabel]
                    let jsonResponse = APIResponse(success: true, data: result, error: nil, executionTime: nil)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(jsonResponse)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(jsonString)
                    }
                } else {
                    print(ColorPrint.success("✅ Alert dismissed with button: \(buttonLabel)"))
                }
            } catch let error as APIClient.APIError {
                try handleAPIError(error, json: json, errorCode: "dismiss_failed")
            }
        }
    }
}

// MARK: - Helper Functions

extension APICommands {
    static func handleAPIError(_ error: APIClient.APIError, json: Bool, errorCode: String) throws {
        if json {
            let jsonResponse = APIResponse<[String: String]>(
                success: false,
                data: nil,
                error: APIErrorDetail(
                    code: errorCode,
                    message: error.localizedDescription,
                    suggestion: nil
                ),
                executionTime: nil
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(jsonResponse)
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            print(ColorPrint.error(error.localizedDescription))
        }
        throw ExitCode.failure
    }
}
