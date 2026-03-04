import Foundation

/// Manages IOSAgentDriver lifecycle and health checks
final class RunnerManager: @unchecked Sendable {
    static let shared = RunnerManager()
    
    private init() {}
    
    enum RunnerError: LocalizedError {
        case iosAgentDriverDirNotSet
        case iosAgentDriverDirInvalid(String)
        case scriptNotFound(String)
        case scriptFailed(Int, String)
        case healthCheckFailed(lastError: Error?)
        case installCheckFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .iosAgentDriverDirNotSet:
                return "IOS_AGENT_DRIVER_DIR environment variable is not set"
            case .iosAgentDriverDirInvalid(let path):
                return "IOS_AGENT_DRIVER_DIR is invalid or does not exist: \(path)"
            case .scriptNotFound(let script):
                return "Script not found: \(script)"
            case .scriptFailed(let code, let message):
                return "Script failed with exit code \(code): \(message)"
            case .healthCheckFailed(let error):
                if let error = error {
                    return "Health check failed: \(error.localizedDescription)"
                }
                return "Health check failed after maximum retries"
            case .installCheckFailed(let error):
                return "Failed to check if app is installed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - IOS_AGENT_DRIVER_DIR Management
    
    /// Get and validate IOS_AGENT_DRIVER_DIR environment variable
    func getIOSAgentDriverDir() throws -> String {
        guard let iosAgentDriverDir = ProcessInfo.processInfo.environment["IOS_AGENT_DRIVER_DIR"] else {
            print(ColorPrint.error("IOS_AGENT_DRIVER_DIR environment variable is not set"))
            print("")
            print("Please set it in your shell configuration:")
            print("  \(ColorPrint.code("export IOS_AGENT_DRIVER_DIR=\"/path/to/AgenticRegressionTester/ios-driver\""))")
            print("")
            print("Then reload your shell:")
            print("  \(ColorPrint.code("source ~/.zshrc"))")
            throw RunnerError.iosAgentDriverDirNotSet
        }
        
        // Validate path exists
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        if !fileManager.fileExists(atPath: iosAgentDriverDir, isDirectory: &isDirectory) || !isDirectory.boolValue {
            print(ColorPrint.error("IOS_AGENT_DRIVER_DIR does not exist or is not a directory: \(iosAgentDriverDir)"))
            throw RunnerError.iosAgentDriverDirInvalid(iosAgentDriverDir)
        }
        
        // Validate it contains Project.swift
        let projectPath = (iosAgentDriverDir as NSString).appendingPathComponent("Project.swift")
        if !fileManager.fileExists(atPath: projectPath) {
            print(ColorPrint.error("IOS_AGENT_DRIVER_DIR does not contain Project.swift"))
            print("Expected: \(projectPath)")
            throw RunnerError.iosAgentDriverDirInvalid(iosAgentDriverDir)
        }
        
        return iosAgentDriverDir
    }
    
    // MARK: - App Installation Check
    
    /// Check if an app is installed on a simulator
    func isAppInstalled(udid: String, bundleId: String) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "get_app_container", udid, bundleId]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // If exit code is 0, app is installed
            return process.terminationStatus == 0
        } catch {
            throw RunnerError.installCheckFailed(error)
        }
    }
    
    // MARK: - Runner Lifecycle
    
    /// Start IOSAgentDriver on a simulator
    func startRunner(udid: String, port: Int, forceReinstall: Bool = false) throws {
        let iosAgentDriverDir = try getIOSAgentDriverDir()
        let scriptsDir = (iosAgentDriverDir as NSString).appendingPathComponent("scripts")
        let scriptPath = (scriptsDir as NSString).appendingPathComponent("start_driver.sh")
        
        // Verify script exists
        if !FileManager.default.fileExists(atPath: scriptPath) {
            throw RunnerError.scriptNotFound(scriptPath)
        }
        
        print(ColorPrint.loading("Starting IOSAgentDriver via script..."))
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: scriptPath)
        process.arguments = [udid, String(port)]
        
        // Set IOS_AGENT_DRIVER_DIR for the script
        var environment = ProcessInfo.processInfo.environment
        environment["IOS_AGENT_DRIVER_DIR"] = iosAgentDriverDir
        process.environment = environment
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        // Capture output
        let outputHandle = pipe.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                print(output, terminator: "")
            }
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            
            outputHandle.readabilityHandler = nil
            
            if process.terminationStatus != 0 {
                let errorData = try pipe.fileHandleForReading.readToEnd() ?? Data()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw RunnerError.scriptFailed(Int(process.terminationStatus), errorMessage)
            }
            
            print(ColorPrint.success("IOSAgentDriver started successfully"))
        } catch let error as RunnerError {
            throw error
        } catch {
            throw RunnerError.scriptFailed(-1, error.localizedDescription)
        }
    }
    
    /// Stop IOSAgentDriver on a simulator
    func stopRunner(udid: String, port: Int) throws {
        let iosAgentDriverDir = try getIOSAgentDriverDir()
        let scriptsDir = (iosAgentDriverDir as NSString).appendingPathComponent("scripts")
        let scriptPath = (scriptsDir as NSString).appendingPathComponent("stop_driver.sh")
        
        // Verify script exists
        if !FileManager.default.fileExists(atPath: scriptPath) {
            throw RunnerError.scriptNotFound(scriptPath)
        }
        
        print(ColorPrint.loading("Stopping IOSAgentDriver via script..."))
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: scriptPath)
        process.arguments = [udid, String(port)]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        // Capture output
        let outputHandle = pipe.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                print(output, terminator: "")
            }
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            
            outputHandle.readabilityHandler = nil
            
            if process.terminationStatus != 0 {
                let errorData = try pipe.fileHandleForReading.readToEnd() ?? Data()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw RunnerError.scriptFailed(Int(process.terminationStatus), errorMessage)
            }
            
            print(ColorPrint.success("IOSAgentDriver stopped successfully"))
        } catch let error as RunnerError {
            throw error
        } catch {
            throw RunnerError.scriptFailed(-1, error.localizedDescription)
        }
    }
    
    // MARK: - Health Checks
    
    /// Wait for IOSAgentDriver to be healthy with exponential backoff
    func waitForHealth(url: URL, maxRetries: Int = 10) async throws {
        print(ColorPrint.loading("Performing health check at \(url)..."))
        
        var attempt = 0
        var lastError: Error?
        let baseDelay: TimeInterval = 1.0
        
        while attempt < maxRetries {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print(ColorPrint.success("Health check passed"))
                        return
                    } else {
                        lastError = NSError(
                            domain: "HealthCheck",
                            code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "Unexpected status code: \(httpResponse.statusCode)"]
                        )
                    }
                }
            } catch {
                lastError = error
            }
            
            // Calculate exponential backoff delay (max 16 seconds)
            let delay = min(baseDelay * pow(2.0, Double(attempt)), 16.0)
            
            print(ColorPrint.info("Retry \(attempt + 1)/\(maxRetries) in \(String(format: "%.1f", delay))s..."))
            
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            attempt += 1
        }
        
        // All retries failed
        print(ColorPrint.error("Health check failed after \(maxRetries) attempts"))
        throw RunnerError.healthCheckFailed(lastError: lastError)
    }
}
