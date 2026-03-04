import Foundation

/// HTTP status code
enum HTTPStatusCode: Int, Sendable {
    case ok = 200
    case created = 201
    case noContent = 204
    case badRequest = 400
    case notFound = 404
    case requestTimeout = 408
    case conflict = 409
    case internalServerError = 500
    
    var reasonPhrase: String {
        switch self {
        case .ok: return "OK"
        case .created: return "Created"
        case .noContent: return "No Content"
        case .badRequest: return "Bad Request"
        case .notFound: return "Not Found"
        case .requestTimeout: return "Request Timeout"
        case .conflict: return "Conflict"
        case .internalServerError: return "Internal Server Error"
        }
    }
}

/// Represents an HTTP response
struct Response: Sendable {
    let statusCode: HTTPStatusCode
    let headers: [String: String]
    let body: Data?
    
    init(
        statusCode: HTTPStatusCode,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
    
    /// Initialize with JSON encodable body
    init<T: Encodable>(
        statusCode: HTTPStatusCode,
        headers: [String: String] = [:],
        body: T
    ) {
        var combinedHeaders = headers
        combinedHeaders["Content-Type"] = "application/json"
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let bodyData = try? encoder.encode(body)
        
        self.init(
            statusCode: statusCode,
            headers: combinedHeaders,
            body: bodyData
        )
    }
    
    /// Convert response to raw data for network transmission
    func toData() -> Data {
        var response = "HTTP/1.1 \(statusCode.rawValue) \(statusCode.reasonPhrase)\r\n"
        
        // Add headers
        var allHeaders = headers
        
        // Add CORS headers to allow Swagger UI and other web clients
        allHeaders["Access-Control-Allow-Origin"] = "*"
        allHeaders["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        allHeaders["Access-Control-Allow-Headers"] = "Content-Type, Accept, Authorization"
        allHeaders["Access-Control-Max-Age"] = "86400" // 24 hours
        
        if let body = body {
            allHeaders["Content-Length"] = "\(body.count)"
        }
        
        for (key, value) in allHeaders {
            response += "\(key): \(value)\r\n"
        }
        
        response += "\r\n"
        
        var responseData = response.data(using: .utf8) ?? Data()
        
        // Append body if present
        if let body = body {
            responseData.append(body)
        }
        
        return responseData
    }
}

// MARK: - Convenience Response Builders

extension Response {
    /// Create a success response with JSON body
    static func success<T: Encodable>(_ body: T) -> Response {
        return Response(statusCode: .ok, body: body)
    }
    
    /// Create an error response with configurable verbosity
    static func error(
        _ statusCode: HTTPStatusCode,
        message: String,
        details: String? = nil,
        suggestion: String? = nil,
        error: Error? = nil
    ) -> Response {
        return ErrorBuilder.buildError(
            statusCode: statusCode,
            message: message,
            details: details,
            suggestion: suggestion,
            error: error
        )
    }
}
