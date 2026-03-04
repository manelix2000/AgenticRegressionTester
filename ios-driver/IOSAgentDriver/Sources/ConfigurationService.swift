import Foundation

/// Service for managing runtime configuration
final class ConfigurationService: @unchecked Sendable {
    
    /// Shared instance
    static let shared = ConfigurationService()
    
    /// Current configuration (protected by lock)
    private var _config: RunnerConfig
    private let lock = NSLock()
    
    private init() {
        // Initialize with defaults
        self._config = RunnerConfig(
            defaultTimeout: 5.0,
            errorVerbosity: .simple,
            maxConcurrentRequests: 10
        )
    }
    
    /// Get current configuration
    func getConfiguration() -> RunnerConfig {
        lock.lock()
        defer { lock.unlock() }
        return _config
    }
    
    /// Update configuration
    /// - Parameter updates: Configuration updates to apply
    /// - Returns: Updated configuration
    func updateConfiguration(_ updates: ConfigurationUpdate) -> RunnerConfig {
        lock.lock()
        defer { lock.unlock() }
        
        // Apply updates if provided
        if let timeout = updates.defaultTimeout {
            _config.defaultTimeout = timeout
        }
        
        if let verbosity = updates.errorVerbosity {
            _config.errorVerbosity = verbosity
        }
        
        if let maxRequests = updates.maxConcurrentRequests {
            _config.maxConcurrentRequests = maxRequests
        }
        
        return _config
    }
    
    /// Reset configuration to defaults
    func resetConfiguration() -> RunnerConfig {
        lock.lock()
        defer { lock.unlock() }
        
        _config = RunnerConfig(
            defaultTimeout: 5.0,
            errorVerbosity: .simple,
            maxConcurrentRequests: 10
        )
        return _config
    }
    
    /// Get default timeout for operations
    func getDefaultTimeout() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return _config.defaultTimeout
    }
    
    /// Get error verbosity setting
    func getErrorVerbosity() -> ErrorVerbosity {
        lock.lock()
        defer { lock.unlock() }
        return _config.errorVerbosity
    }
    
    /// Check if verbose errors are enabled
    func isVerboseErrorsEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _config.errorVerbosity == .verbose
    }
}

// MARK: - Data Models

/// Runtime configuration
struct RunnerConfig: Codable, Sendable {
    var defaultTimeout: TimeInterval      // Default timeout for operations (seconds)
    var errorVerbosity: ErrorVerbosity    // Error detail level
    var maxConcurrentRequests: Int        // Maximum concurrent requests
}

/// Configuration update request (all fields optional)
struct ConfigurationUpdate: Codable, Sendable {
    let defaultTimeout: TimeInterval?
    let errorVerbosity: ErrorVerbosity?
    let maxConcurrentRequests: Int?
}

/// Error verbosity level
enum ErrorVerbosity: String, Codable, Sendable {
    case simple     // User-friendly messages only
    case verbose    // Includes stack traces and detailed info
}

/// Configuration response
struct ConfigurationResponse: Codable, Sendable {
    let config: RunnerConfig
    let timestamp: String
}

/// Configuration update response
struct ConfigurationUpdateResponse: Codable, Sendable {
    let config: RunnerConfig
    let updated: [String]      // List of fields that were updated
    let timestamp: String
}

// MARK: - Error Builder

/// Verbose error response (includes stack trace and additional debug info)
struct VerboseErrorResponse: Codable, Sendable {
    let error: String
    let message: String
    let timestamp: String
    let suggestion: String?
    let details: String?
    let errorType: String?
    let localizedDescription: String?
    let stackTrace: String?
}

/// Helper for building errors with configurable verbosity
struct ErrorBuilder {
    
    /// Build an error response with appropriate verbosity
    /// - Parameters:
    ///   - statusCode: HTTP status code
    ///   - message: Error message
    ///   - details: Optional detailed information (only included if verbose)
    ///   - suggestion: Optional suggestion for fixing the error
    ///   - error: Optional underlying error (for stack trace in verbose mode)
    /// - Returns: Response with error information
    static func buildError(
        statusCode: HTTPStatusCode,
        message: String,
        details: String? = nil,
        suggestion: String? = nil,
        error: Error? = nil
    ) -> Response {
        let verbosity = ConfigurationService.shared.getErrorVerbosity()
        
        if verbosity == .verbose {
            // Verbose mode - include all details
            var errorType: String?
            var localizedDesc: String?
            var stackTrace: String?
            
            if let error = error {
                errorType = String(describing: type(of: error))
                localizedDesc = error.localizedDescription
                
                // Add stack trace if available
                #if DEBUG
                stackTrace = Thread.callStackSymbols.joined(separator: "\n")
                #endif
            }
            
            let verboseResponse = VerboseErrorResponse(
                error: "\(statusCode.rawValue)",
                message: message,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                suggestion: suggestion,
                details: details,
                errorType: errorType,
                localizedDescription: localizedDesc,
                stackTrace: stackTrace
            )
            
            return Response(statusCode: statusCode, body: verboseResponse)
        } else {
            // Simple mode - minimal error info
            let simpleResponse = ErrorResponse(
                error: "\(statusCode.rawValue)",
                message: message,
                details: nil,  // No details in simple mode
                timestamp: ISO8601DateFormatter().string(from: Date()),
                suggestion: suggestion
            )
            
            return Response(statusCode: statusCode, body: simpleResponse)
        }
    }
}

/// Simple error response (used by Response.error)
struct ErrorResponse: Codable, Sendable {
    let error: String
    let message: String
    let details: String?
    let timestamp: String
    let suggestion: String?
}
