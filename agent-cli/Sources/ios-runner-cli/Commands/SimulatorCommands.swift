@preconcurrency import ArgumentParser
import Foundation

/// Simulator management commands
struct Simulator: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage iOS simulators",
        discussion: """
            Direct access to simctl functionality for simulator lifecycle management.
            Use these commands to create, delete, boot, shutdown, and snapshot simulators.
            
            \(ColorPrint.header("Examples:"))
            
              \(ColorPrint.comment("# List all simulators"))
              \(ColorPrint.code("agent-cli simulator list"))
            
              \(ColorPrint.comment("# Create a new simulator"))
              \(ColorPrint.code("agent-cli simulator create \"My iPhone\" --device \"iPhone 15\""))
            
              \(ColorPrint.comment("# Boot a simulator"))
              \(ColorPrint.code("agent-cli simulator boot <udid>"))
            
              \(ColorPrint.comment("# List installed apps"))
              \(ColorPrint.code("agent-cli simulator list-apps <udid>"))
            
              \(ColorPrint.comment("# Get simulator info"))
              \(ColorPrint.code("agent-cli simulator info <udid>"))
            """,
        subcommands: [
            List.self,
            ListApps.self,
            Create.self,
            Delete.self,
            Boot.self,
            Shutdown.self,
            Snapshot.self,
            Info.self,
            Cleanup.self,
        ]
    )
    
    // MARK: - List Simulators
    
    
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all simulators",
            discussion: """
                Lists available iOS simulators with their states and details.
                
                \(ColorPrint.header("Parameters:"))
                
                  \(ColorPrint.label("-b, --booted"))   Show only booted simulators
                  \(ColorPrint.label("-i, --ios"))      Filter by iOS version (e.g., 18 or 17.5)
                  \(ColorPrint.label("--json"))         Output raw JSON from simctl
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# List all simulators"))
                  \(ColorPrint.code("agent-cli simulator list"))
                
                  \(ColorPrint.comment("# Show only booted simulators"))
                  \(ColorPrint.code("agent-cli simulator list --booted"))
                  \(ColorPrint.code("agent-cli simulator list -b"))
                
                  \(ColorPrint.comment("# Filter by iOS version"))
                  \(ColorPrint.code("agent-cli simulator list --ios 18"))
                  \(ColorPrint.code("agent-cli simulator list --ios 17.5"))
                
                  \(ColorPrint.comment("# Combine filters"))
                  \(ColorPrint.code("agent-cli simulator list --booted --ios 18"))
                
                  \(ColorPrint.comment("# Get machine-readable JSON output"))
                  \(ColorPrint.code("agent-cli simulator list --json"))
                """
        )
        
        @Flag(name: .shortAndLong, help: "Show only booted simulators")
        var booted = false
        
        @Option(name: .shortAndLong, help: "Filter by iOS version")
        var ios: String?
        
        @Flag(name: .long, help: "Output raw JSON from simctl")
        var json = false
        
        mutating func run() throws {
            // If JSON flag, output raw simctl JSON
            if json {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = ["simctl", "list", "devices", "-j"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                guard process.terminationStatus == 0 else {
                    throw ValidationError(ColorPrint.error("Failed to get simulator list: \(output)"))
                }
                
                // Apply filters to JSON if needed
                if booted || ios != nil {
                    // Parse, filter, and re-encode
                    if let jsonData = output.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       var devices = parsed["devices"] as? [String: [[String: Any]]] {
                        
                        // Filter devices
                        for (runtime, sims) in devices {
                            var filtered = sims
                            
                            if booted {
                                filtered = filtered.filter { ($0["state"] as? String) == "Booted" }
                            }
                            
                            if let iOSFilter = ios {
                                // Only keep this runtime if it matches the iOS filter
                                if !runtime.contains(iOSFilter.replacingOccurrences(of: ".", with: "-")) {
                                    devices.removeValue(forKey: runtime)
                                    continue
                                }
                            }
                            
                            devices[runtime] = filtered
                        }
                        
                        let result: [String: Any] = ["devices": devices]
                        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            print(jsonString)
                            return
                        }
                    }
                }
                
                // Fallback: output unfiltered
                print(output)
                return
            }
            
            var simulators = try SimulatorManager.shared.listSimulators()
            
            if booted {
                simulators = simulators.filter { $0.state == "Booted" }
            }
            
            if let iOSFilter = ios {
                simulators = simulators.filter { $0.iOSVersion.contains(iOSFilter) }
            }
            
            // Sort by name for consistent output
            simulators.sort { $0.name < $1.name }
            
            if simulators.isEmpty {
                print(ColorPrint.info("No simulators found"))
                return
            }
            
            print(ColorPrint.header("📱 Simulators (\(simulators.count)):\n"))
            
            for sim in simulators {
                let stateIcon = sim.state == "Booted" ? "🟢" : "⚪️"
                let stateName = sim.state == "Booted" ? sim.name.colored(.green) : sim.name
                print("  \(stateIcon) \(stateName)")
                print("     \(ColorPrint.label("UDID:")) \(sim.udid.colored(.dim))")
                print("     \(ColorPrint.label("State:")) \(stateColor(sim.state))")
                print("     \(ColorPrint.label("Device:")) \(ColorPrint.value(sim.deviceModel))")
                print("     \(ColorPrint.label("iOS:")) \(ColorPrint.value(sim.iOSVersion))")
                print("")
            }
        }
        
        private func stateColor(_ state: String) -> String {
            switch state {
            case "Booted": return state.colored(.green)
            case "Shutdown": return state.colored(.brightBlack)
            case "Shutting Down": return state.colored(.yellow)
            default: return state
            }
        }
    }
    
    // MARK: - List Apps
    
    struct ListApps: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list-apps",
            abstract: "List apps installed on a simulator",
            discussion: """
                Shows all applications installed on the specified simulator,
                including both system apps and user-installed apps.
                
                \(ColorPrint.header("Parameters:"))
                
                  \(ColorPrint.label("udid"))          Simulator UDID (required)
                  \(ColorPrint.label("--user-only"))   Show only user-installed apps, exclude system apps
                  \(ColorPrint.label("--json"))        Output raw PropertyList XML format
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# List all apps on a simulator"))
                  \(ColorPrint.code("agent-cli simulator list-apps <udid>"))
                
                  \(ColorPrint.comment("# Show only user-installed apps"))
                  \(ColorPrint.code("agent-cli simulator list-apps <udid> --user-only"))
                
                  \(ColorPrint.comment("# Get machine-readable PropertyList output"))
                  \(ColorPrint.code("agent-cli simulator list-apps <udid> --json"))
                
                  \(ColorPrint.comment("# Combine filters for user apps as PropertyList"))
                  \(ColorPrint.code("agent-cli simulator list-apps <udid> --user-only --json"))
                """
        )
        
        @Argument(help: "Simulator UDID")
        var udid: String
        
        @Flag(name: .long, help: "Show only user-installed apps (exclude system apps)")
        var userOnly = false
        
        @Flag(name: .long, help: "Output raw JSON from simctl")
        var json = false
        
        mutating func run() throws {
            // Verify simulator exists
            guard let simulator = try SimulatorManager.shared.getSimulator(udid: udid) else {
                throw ValidationError(ColorPrint.error("Simulator not found: \(udid)"))
            }
            
            print(ColorPrint.loading("Listing apps on \(simulator.name)..."))
            
            // Execute simctl listapps
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "listapps", udid]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            guard process.terminationStatus == 0 else {
                throw ValidationError(ColorPrint.error("Failed to list apps: \(output)"))
            }
            
            // Parse the output (it's in plist format)
            guard let plistData = output.data(using: .utf8) else {
                throw ValidationError(ColorPrint.error("Failed to parse app list"))
            }
            
            // Parse as PropertyList
            guard let apps = try? PropertyListSerialization.propertyList(
                from: plistData,
                format: nil
            ) as? [String: [String: Any]] else {
                throw ValidationError(ColorPrint.error("Failed to parse app list"))
            }
            
            // Filter if user-only requested
            var filteredApps = apps
            if userOnly {
                filteredApps = apps.filter { (bundleId, info) in
                    let appType = info["ApplicationType"] as? String ?? "Unknown"
                    return appType != "System"
                }
            }
            
            // If JSON flag, output filtered plist and exit
            if json {
                // Convert back to PropertyList format
                let jsonData = try PropertyListSerialization.data(
                    fromPropertyList: filteredApps,
                    format: .xml,
                    options: 0
                )
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print(jsonString)
                }
                return
            }
            
            // Build app list for formatted output
            var appList: [(bundleId: String, name: String, type: String)] = []
            
            for (bundleId, info) in filteredApps {
                let displayName = info["CFBundleDisplayName"] as? String
                    ?? info["CFBundleName"] as? String
                    ?? bundleId
                let appType = info["ApplicationType"] as? String ?? "Unknown"
                
                appList.append((bundleId: bundleId, name: displayName, type: appType))
            }
            
            // Sort by name
            appList.sort { $0.name.lowercased() < $1.name.lowercased() }
            
            // Display results
            print("")
            print(ColorPrint.success("Found \(appList.count) apps on \(simulator.name)"))
            print("")
            
            if appList.isEmpty {
                print(ColorPrint.info("No apps found"))
                return
            }
            
            // Calculate column widths
            let maxNameWidth = min(40, appList.map { $0.name.count }.max() ?? 20)
            let maxBundleWidth = min(50, appList.map { $0.bundleId.count }.max() ?? 30)
            
            // Print header
            let nameHeader = "NAME".padding(toLength: maxNameWidth, withPad: " ", startingAt: 0)
            let bundleHeader = "BUNDLE ID".padding(toLength: maxBundleWidth, withPad: " ", startingAt: 0)
            let typeHeader = "TYPE"
            
            print("  \(ColorPrint.header(nameHeader))  \(ColorPrint.header(bundleHeader))  \(ColorPrint.header(typeHeader))")
            print("  \(String(repeating: "-", count: maxNameWidth))  \(String(repeating: "-", count: maxBundleWidth))  --------")
            
            // Print apps
            for app in appList {
                let name = app.name.count > maxNameWidth
                    ? String(app.name.prefix(maxNameWidth - 3)) + "..."
                    : app.name.padding(toLength: maxNameWidth, withPad: " ", startingAt: 0)
                
                let bundleId = app.bundleId.count > maxBundleWidth
                    ? String(app.bundleId.prefix(maxBundleWidth - 3)) + "..."
                    : app.bundleId.padding(toLength: maxBundleWidth, withPad: " ", startingAt: 0)
                
                let typeColor: ANSIColor = app.type == "System" ? .dim : .cyan
                let type = app.type.padding(toLength: 8, withPad: " ", startingAt: 0)
                
                print("  \(name.colored(.white))  \(bundleId.colored(.dim))  \(type.colored(typeColor))")
            }
            
            print("")
            print(ColorPrint.info("💡 Tip: Use --user-only to hide system apps"))
        }
    }
    
    // MARK: - Create Simulator
    
    
    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new simulator",
            discussion: """
                Creates a new iOS simulator with the specified device type and runtime.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Create with defaults (iPhone 15, iOS 17.0)"))
                  \(ColorPrint.code("agent-cli simulator create \"My Test Phone\""))
                
                  \(ColorPrint.comment("# Specify device type"))
                  \(ColorPrint.code("agent-cli simulator create \"iPad Test\" --device \"iPad Pro\""))
                
                  \(ColorPrint.comment("# Specify runtime version"))
                  \(ColorPrint.code("agent-cli simulator create \"Test Phone\" --runtime \"iOS 18.6\""))
                
                  \(ColorPrint.comment("# Full specification"))
                  \(ColorPrint.code("agent-cli simulator create \"Test\" --device \"iPhone 14\" --runtime \"iOS 17.5\""))
                """
        )
        
        @Argument(help: "Simulator name")
        var name: String
        
        @Option(name: .shortAndLong, help: "Device type (e.g., 'iPhone 15')")
        var device: String = "iPhone 15"
        
        @Option(name: .shortAndLong, help: "Runtime (e.g., 'iOS 17.0')")
        var runtime: String = "iOS 17.0"
        
        @Flag(name: .long, help: "Output in JSON format")
        var json = false
        
        mutating func run() throws {
            if !json {
                print(ColorPrint.loading("Creating simulator '\(name)'..."))
                print("   \(ColorPrint.label("Device:")) \(ColorPrint.value(device))")
                print("   \(ColorPrint.label("Runtime:")) \(ColorPrint.value(runtime))")
            }
            
            // Convert friendly names to identifiers
            let deviceType = "com.apple.CoreSimulator.SimDeviceType.\(device.replacingOccurrences(of: " ", with: "-"))"
            
            // Runtime: Convert "iOS 17.5" or "17.5" to "com.apple.CoreSimulator.SimRuntime.iOS-17-5"
            let normalizedRuntime = runtime.hasPrefix("iOS") ? runtime : "iOS \(runtime)"
            let runtimeId = "com.apple.CoreSimulator.SimRuntime.\(normalizedRuntime.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ".", with: "-"))"
            
            let udid = try SimulatorManager.shared.createSimulator(
                name: name,
                deviceType: deviceType,
                runtime: runtimeId
            )
            
            if json {
                struct CreateResult: Codable {
                    let name: String
                    let udid: String
                    let device: String
                    let runtime: String
                }
                JSONOutput.success(CreateResult(name: name, udid: udid, device: device, runtime: runtime))
            } else {
                print("")
                print(ColorPrint.info("💡 Use this UDID for session creation:"))
                print("   \(ColorPrint.code("agent-cli session create --simulator \(udid)"))")
            }
        }
    }
    
    // MARK: - Delete Simulator
    
    
    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a simulator",
            discussion: """
                Permanently deletes a simulator from the system.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Delete with confirmation prompt"))
                  \(ColorPrint.code("agent-cli simulator delete <udid>"))
                
                  \(ColorPrint.comment("# Force delete without confirmation"))
                  \(ColorPrint.code("agent-cli simulator delete <udid> --force"))
                  \(ColorPrint.code("agent-cli simulator delete <udid> -f"))
                """
        )
        
        @Argument(help: "Simulator UDID")
        var udid: String
        
        @Flag(name: .shortAndLong, help: "Delete without confirmation")
        var force = false
        
        @Flag(name: .long, help: "Output in JSON format")
        var json = false
        
        mutating func run() throws {
            guard let sim = try SimulatorManager.shared.getSimulator(udid: udid) else {
                if json {
                    JSONOutput.error(code: "SIMULATOR_NOT_FOUND", message: "Simulator not found: \(udid)")
                    throw ExitCode(1)
                }
                throw ValidationError(ColorPrint.error("Simulator not found: \(udid)"))
            }
            
            if !force && !json {
                print(ColorPrint.warning("Delete simulator '\(sim.name)' (\(udid))?"))
                print("   Type '\(ColorPrint.highlight("yes"))' to confirm: ", terminator: "")
                
                guard let response = readLine(), response.lowercased() == "yes" else {
                    print(ColorPrint.error("Cancelled"))
                    return
                }
            }
            
            try SimulatorManager.shared.deleteSimulator(udid: udid)
            
            if json {
                struct DeleteResult: Codable {
                    let udid: String
                    let name: String
                }
                JSONOutput.success(DeleteResult(udid: udid, name: sim.name))
            }
        }
    }
    
    // MARK: - Boot Simulator
    
    
    struct Boot: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Boot a simulator",
            discussion: """
                Boots (starts) a simulator. The simulator must be in shutdown state.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Boot a simulator"))
                  \(ColorPrint.code("agent-cli simulator boot <udid>"))
                  \(ColorPrint.code("agent-cli simulator boot A4FBE4AD-B8FD-4B11-82DF-FC133F535983"))
                """
        )
        
        @Argument(help: "Simulator UDID")
        var udid: String
        
        @Flag(name: .long, help: "Output in JSON format")
        var json = false
        
        mutating func run() throws {
            try SimulatorManager.shared.bootSimulator(udid: udid)
            
            if json {
                struct BootResult: Codable {
                    let udid: String
                    let status: String
                }
                JSONOutput.success(BootResult(udid: udid, status: "booted"))
            }
        }
    }
    
    // MARK: - Shutdown Simulator
    
    
    struct Shutdown: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Shutdown a simulator",
            discussion: """
                Shuts down (stops) a running simulator.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Shutdown a simulator"))
                  \(ColorPrint.code("agent-cli simulator shutdown <udid>"))
                  \(ColorPrint.code("agent-cli simulator shutdown A4FBE4AD-B8FD-4B11-82DF-FC133F535983"))
                """
        )
        
        @Argument(help: "Simulator UDID")
        var udid: String
        
        @Flag(name: .long, help: "Output in JSON format")
        var json = false
        
        mutating func run() throws {
            try SimulatorManager.shared.shutdownSimulator(udid: udid)
            
            if json {
                struct ShutdownResult: Codable {
                    let udid: String
                    let status: String
                }
                JSONOutput.success(ShutdownResult(udid: udid, status: "shutdown"))
            }
        }
    }
    
    // MARK: - Create Snapshot
    
    
    struct Snapshot: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a snapshot of simulator state",
            discussion: """
                Creates a clone of a simulator, preserving its current state.
                The simulator is shutdown, cloned, and a new UDID is generated.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Create a snapshot with a descriptive name"))
                  \(ColorPrint.code("agent-cli simulator snapshot <udid> \"Clean State\""))
                  \(ColorPrint.code("agent-cli simulator snapshot <udid> \"After Login\""))
                
                  \(ColorPrint.comment("# Full example"))
                  \(ColorPrint.code("agent-cli simulator snapshot A4FBE4AD-B8FD-... \"Production Ready\""))
                """
        )
        
        @Argument(help: "Simulator UDID to snapshot")
        var udid: String
        
        @Argument(help: "Snapshot name")
        var name: String
        
        @Flag(name: .long, help: "Output in JSON format")
        var json = false
        
        mutating func run() throws {
            if !json {
                print(ColorPrint.loading("Creating snapshot '\(name)' from \(udid.prefix(8))..."))
            }
            let newUdid = try SimulatorManager.shared.createSnapshot(udid: udid, name: name)
            
            if json {
                struct SnapshotResult: Codable {
                    let sourceUdid: String
                    let snapshotName: String
                    let snapshotUdid: String
                }
                JSONOutput.success(SnapshotResult(sourceUdid: udid, snapshotName: name, snapshotUdid: newUdid))
            }
        }
    }
    
    // MARK: - Simulator Info
    
    
    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Get simulator information",
            discussion: """
                Displays detailed information about a specific simulator.
                
                \(ColorPrint.header("Parameters:"))
                
                  \(ColorPrint.label("udid"))      Simulator UDID (required)
                  \(ColorPrint.label("--json"))    Output raw JSON from simctl
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Get simulator details"))
                  \(ColorPrint.code("agent-cli simulator info <udid>"))
                  \(ColorPrint.code("agent-cli simulator info A4FBE4AD-B8FD-4B11-82DF-FC133F535983"))
                
                  \(ColorPrint.comment("# Get machine-readable JSON output"))
                  \(ColorPrint.code("agent-cli simulator info <udid> --json"))
                """
        )
        
        @Argument(help: "Simulator UDID")
        var udid: String
        
        @Flag(name: .long, help: "Output raw JSON from simctl")
        var json = false
        
        mutating func run() throws {
            // If JSON flag, output raw simctl JSON
            if json {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = ["simctl", "list", "devices", "-j", udid]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                guard process.terminationStatus == 0 else {
                    throw ValidationError(ColorPrint.error("Failed to get simulator info: \(output)"))
                }
                
                print(output)
                return
            }
            
            guard let sim = try SimulatorManager.shared.getSimulator(udid: udid) else {
                throw ValidationError(ColorPrint.error("Simulator not found: \(udid)"))
            }
            
            let stateIcon = sim.state == "Booted" ? "🟢" : "⚪️"
            
            print(ColorPrint.header("📱 Simulator: \(sim.name)\n"))
            print("  \(stateIcon) \(ColorPrint.label("State:")) \(stateColor(sim.state))")
            print("  \(ColorPrint.label("UDID:")) \(sim.udid.colored(.dim))")
            print("  \(ColorPrint.label("Device:")) \(ColorPrint.value(sim.deviceModel))")
            print("  \(ColorPrint.label("iOS Version:")) \(ColorPrint.value(sim.iOSVersion))")
            print("  \(ColorPrint.label("Device Type ID:")) \(sim.deviceTypeIdentifier.colored(.dim))")
            print("  \(ColorPrint.label("Runtime ID:")) \(sim.runtimeIdentifier.colored(.dim))")
        }
        
        private func stateColor(_ state: String) -> String {
            switch state {
            case "Booted": return state.colored(.green)
            case "Shutdown": return state.colored(.brightBlack)
            case "Shutting Down": return state.colored(.yellow)
            default: return state
            }
        }
    }
    
    // MARK: - Cleanup IOSAgentDriver Simulators
    
    struct Cleanup: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete all IOSAgentDriver-related simulators",
            discussion: """
                Finds and deletes all simulators created by IOSAgentDriver CLI.
                This includes simulators with names starting with "IOSAgentDriver-".
                
                \(ColorPrint.warning("⚠️  This is destructive and cannot be undone!"))
                
                \(ColorPrint.header("Parameters:"))
                
                  \(ColorPrint.label("--force"))   Skip confirmation prompt
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Delete all IOSAgentDriver simulators (with confirmation)"))
                  \(ColorPrint.code("agent-cli simulator cleanup"))
                
                  \(ColorPrint.comment("# Force delete without confirmation"))
                  \(ColorPrint.code("agent-cli simulator cleanup --force"))
                
                \(ColorPrint.header("What gets deleted:"))
                
                  • Simulators with names matching "IOSAgentDriver-*"
                  • Both booted and shutdown simulators
                  • Both pool and session simulators
                
                \(ColorPrint.info("💡 Use 'simulator list' to see what will be deleted first"))
                """
        )
        
        @Flag(name: .long, help: "Skip confirmation prompt")
        var force = false
        
        @Flag(name: .long, help: "Output in JSON format")
        var json = false
        
        mutating func run() throws {
            // Get all simulators
            let allSims = try SimulatorManager.shared.listSimulators()
            
            // Filter IOSAgentDriver simulators
            let iosAgentDriverSims = allSims.filter { sim in
                sim.name.starts(with: "IOSAgentDriver-")
            }
            
            guard !iosAgentDriverSims.isEmpty else {
                if json {
                    struct CleanupResult: Codable {
                        let found: Int
                        let deleted: Int
                        let failed: Int
                    }
                    JSONOutput.success(CleanupResult(found: 0, deleted: 0, failed: 0))
                } else {
                    print(ColorPrint.info("✓ No IOSAgentDriver simulators found"))
                }
                return
            }
            
            // Show what will be deleted
            if !json {
                print(ColorPrint.header("Found \(iosAgentDriverSims.count) IOSAgentDriver simulator(s):"))
                print("")
                
                for sim in iosAgentDriverSims {
                    let stateIcon = sim.state == "Booted" ? "🟢" : "⚪️"
                    print("  \(stateIcon) \(sim.name)")
                    print("     \(ColorPrint.label("UDID:")) \(sim.udid.colored(.dim))")
                    print("     \(ColorPrint.label("State:")) \(sim.state)")
                    print("")
                }
            }
            
            // Confirm unless --force
            if !force && !json {
                print(ColorPrint.warning("⚠️  This will permanently delete \(iosAgentDriverSims.count) simulator(s)"))
                print("Type 'yes' to confirm: ", terminator: "")
                
                guard let response = readLine()?.lowercased(),
                      response == "yes" else {
                    print(ColorPrint.info("Cancelled"))
                    return
                }
                print("")
            }
            
            // Delete simulators
            if !json {
                print(ColorPrint.loading("Deleting \(iosAgentDriverSims.count) simulator(s)..."))
            }
            
            var deleted = 0
            var errors: [String] = []
            
            for sim in iosAgentDriverSims {
                do {
                    // Shutdown if booted
                    if sim.state == "Booted" {
                        try? SimulatorManager.shared.shutdownSimulator(udid: sim.udid)
                        // Give it a moment to shutdown
                        Thread.sleep(forTimeInterval: 0.5)
                    }
                    
                    // Delete
                    try SimulatorManager.shared.deleteSimulator(udid: sim.udid)
                    deleted += 1
                    if !json {
                        print("  ✓ Deleted \(sim.name)")
                    }
                } catch {
                    errors.append("\(sim.name): \(error.localizedDescription)")
                    if !json {
                        print("  ✗ Failed to delete \(sim.name): \(error.localizedDescription)")
                    }
                }
            }
            
            if json {
                struct CleanupResult: Codable {
                    let found: Int
                    let deleted: Int
                    let failed: Int
                }
                JSONOutput.success(CleanupResult(found: iosAgentDriverSims.count, deleted: deleted, failed: errors.count))
            } else {
                print("")
                
                // Summary
                if deleted == iosAgentDriverSims.count {
                    print(ColorPrint.success("✅ Successfully deleted all \(deleted) simulator(s)"))
                } else {
                    print(ColorPrint.warning("⚠️  Deleted \(deleted) of \(iosAgentDriverSims.count) simulator(s)"))
                    if !errors.isEmpty {
                        print("")
                        print(ColorPrint.error("Errors:"))
                        for error in errors {
                            print("  • \(error)")
                        }
                    }
                }
            }
        }
    }
}
