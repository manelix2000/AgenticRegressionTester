import Foundation

/// Manages iOS simulators using xcrun simctl
final class SimulatorManager: @unchecked Sendable {
    static let shared = SimulatorManager()
    
    private init() {}
    
    // MARK: - Simulator Information
    
    struct SimulatorInfo: Codable {
        let udid: String
        let name: String
        let state: String
        let deviceTypeIdentifier: String
        var runtimeIdentifier: String = "" // Will be set manually
        
        enum CodingKeys: String, CodingKey {
            case udid
            case name
            case state
            case deviceTypeIdentifier
        }
        
        var deviceModel: String {
            deviceTypeIdentifier.components(separatedBy: ".").last?.replacingOccurrences(of: "-", with: " ") ?? "Unknown"
        }
        
        var iOSVersion: String {
            // Extract version from "com.apple.CoreSimulator.SimRuntime.iOS-17-5" or "watchOS-11-5"
            // Strategy: Find the last occurrence of "iOS-" or "watchOS-" and extract everything after it
            if let range = runtimeIdentifier.range(of: "iOS-", options: .backwards) {
                let versionPart = String(runtimeIdentifier[range.upperBound...])
                return versionPart.replacingOccurrences(of: "-", with: ".")
            } else if let range = runtimeIdentifier.range(of: "watchOS-", options: .backwards) {
                let versionPart = String(runtimeIdentifier[range.upperBound...])
                return "watchOS " + versionPart.replacingOccurrences(of: "-", with: ".")
            } else if let range = runtimeIdentifier.range(of: "tvOS-", options: .backwards) {
                let versionPart = String(runtimeIdentifier[range.upperBound...])
                return "tvOS " + versionPart.replacingOccurrences(of: "-", with: ".")
            }
            return "Unknown"
        }
    }
    
    struct SimctlDevices: Codable {
        let devices: [String: [SimulatorInfo]]
    }
    
    /// List all available simulators
    func listSimulators() throws -> [SimulatorInfo] {
        let output = try runSimctl(["list", "devices", "-j"])
        let data = output.data(using: .utf8) ?? Data()
        let result = try JSONDecoder().decode(SimctlDevices.self, from: data)
        
        // Flatten and add runtime identifiers
        var allSimulators: [SimulatorInfo] = []
        for (runtimeId, sims) in result.devices {
            for var sim in sims {
                sim.runtimeIdentifier = runtimeId
                allSimulators.append(sim)
            }
        }
        
        return allSimulators
    }
    
    /// Get simulator by UDID
    func getSimulator(udid: String) throws -> SimulatorInfo? {
        let simulators = try listSimulators()
        return simulators.first { $0.udid == udid }
    }
    
    
    /// Find available runtime for device model
    func findRuntime(device: String, iOSVersion: String) throws -> String? {
        _ = try runSimctl(["list", "runtimes", "-j"])
        // Parse and find matching runtime
        // For now, return nil and implement on-demand
        return nil
    }
    
    // MARK: - Simulator Lifecycle
    
    /// Create a new simulator
    func createSimulator(name: String, deviceType: String, runtime: String) throws -> String {
        let output = try runSimctl(["create", name, deviceType, runtime])
        let udid = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print(ColorPrint.success("Created simulator: \(name)"))
        print("   \(ColorPrint.label("UDID:")) \(ColorPrint.value(udid))")
        
        return udid
    }
    
    /// Boot a simulator
    func bootSimulator(udid: String) throws {
        let info = try getSimulator(udid: udid)
        
        if info?.state == "Booted" {
            print(ColorPrint.info("Simulator \(udid) already booted"))
            return
        }
        
        try runSimctl(["boot", udid])
        print(ColorPrint.success("Booted simulator \(udid)"))
        
        // Wait for boot to complete
        try waitForBoot(udid: udid)
    }
    
    /// Shutdown a simulator
    func shutdownSimulator(udid: String) throws {
        let info = try getSimulator(udid: udid)
        
        if info?.state == "Shutdown" {
            print(ColorPrint.info("Simulator \(udid) already shutdown"))
            return
        }
        
        try runSimctl(["shutdown", udid])
        print(ColorPrint.success("Shutdown simulator \(udid)"))
    }
    
    /// Delete a simulator
    func deleteSimulator(udid: String) throws {
        try runSimctl(["delete", udid])
        print(ColorPrint.success("Deleted simulator \(udid)"))
    }
    
    /// Install app on simulator
    func installApp(udid: String, appPath: String) throws {
        try runSimctl(["install", udid, appPath])
        print(ColorPrint.success("Installed app on simulator \(udid)"))
    }
    
    /// Launch app on simulator
    func launchApp(udid: String, bundleId: String) throws {
        try runSimctl(["launch", udid, bundleId])
        print(ColorPrint.success("Launched app \(bundleId) on simulator \(udid)"))
    }
    
    /// Terminate app on simulator
    func terminateApp(udid: String, bundleId: String) throws {
        try runSimctl(["terminate", udid, bundleId])
        print(ColorPrint.success("Terminated app \(bundleId) on simulator \(udid)"))
    }
    
    // MARK: - Snapshots
    
    /// Create a snapshot of simulator state
    func createSnapshot(udid: String, name: String) throws -> String {
        // Shutdown simulator first
        try shutdownSimulator(udid: udid)
        
        // Clone the simulator
        let newUDID = try cloneSimulator(udid: udid, name: name)
        
        print(ColorPrint.success("Created snapshot: \(name)"))
        print("   \(ColorPrint.label("New UDID:")) \(ColorPrint.value(newUDID))")
        
        return newUDID
    }
    
    /// Clone a simulator
    func cloneSimulator(udid: String, name: String) throws -> String {
        let output = try runSimctl(["clone", udid, name])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Helper Methods
    
    private func waitForBoot(udid: String, timeout: Int = 60) throws {
        let start = Date()
        
        while Date().timeIntervalSince(start) < Double(timeout) {
            let info = try getSimulator(udid: udid)
            if info?.state == "Booted" {
                return
            }
            Thread.sleep(forTimeInterval: 1)
        }
        
        throw SimulatorError.bootTimeout(udid: udid)
    }
    
    @discardableResult
    private func runSimctl(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            throw SimulatorError.simctlFailed(
                command: arguments.joined(separator: " "),
                output: output
            )
        }
        
        return output
    }
}

// MARK: - Errors

enum SimulatorError: LocalizedError {
    case simctlFailed(command: String, output: String)
    case bootTimeout(udid: String)
    case simulatorNotFound(udid: String)
    
    var errorDescription: String? {
        switch self {
        case .simctlFailed(let command, let output):
            return "simctl command failed: \(command)\n\(output)"
        case .bootTimeout(let udid):
            return "Simulator \(udid) failed to boot within timeout"
        case .simulatorNotFound(let udid):
            return "Simulator not found: \(udid)"
        }
    }
}
