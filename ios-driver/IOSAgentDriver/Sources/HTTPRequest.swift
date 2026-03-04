import Foundation

/// HTTP request method
enum HTTPMethod: String, Sendable {
    case GET
    case POST
    case PUT
    case DELETE
    case PATCH
    case OPTIONS
}

/// Represents an HTTP request
struct HTTPRequest: Sendable {
    let method: HTTPMethod
    let path: String
    let queryParameters: [String: String]
    let headers: [String: String]
    let body: Data?
    let pathParams: [String: String]  // For URL path parameters like /ui/element/:identifier
    
    // Computed property alias for backward compatibility
    var queryParams: [String: String] {
        queryParameters
    }
    
    /// Parse HTTP request from raw data
    static func parse(from data: Data) -> HTTPRequest? {
        // Find the end of headers (double CRLF: \r\n\r\n)
        let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
        guard let headerEndRange = data.range(of: headerSeparator) else {
            // Headers not complete yet
            return nil
        }
        
        // Extract headers portion
        let headersData = data.subdata(in: 0..<headerEndRange.lowerBound)
        guard let headersString = String(data: headersData, encoding: .utf8) else {
            return nil
        }
        
        let lines = headersString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }
        
        // Parse request line: "GET /path HTTP/1.1"
        let requestComponents = requestLine.components(separatedBy: " ")
        guard requestComponents.count >= 2,
              let method = HTTPMethod(rawValue: requestComponents[0]) else {
            return nil
        }
        
        let fullPath = requestComponents[1]
        
        // Split path and query string
        let pathComponents = fullPath.components(separatedBy: "?")
        let path = pathComponents[0]
        let queryString = pathComponents.count > 1 ? pathComponents[1] : ""
        
        // Parse query parameters
        let queryParameters = parseQueryString(queryString)
        
        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let headerComponents = line.components(separatedBy: ": ")
            if headerComponents.count == 2 {
                headers[headerComponents[0]] = headerComponents[1]
            }
        }
        
        // Extract body as binary data (everything after \r\n\r\n)
        var body: Data?
        let bodyStartIndex = headerEndRange.upperBound
        if bodyStartIndex < data.count {
            body = data.subdata(in: bodyStartIndex..<data.count)
        }
        
        return HTTPRequest(
            method: method,
            path: path,
            queryParameters: queryParameters,
            headers: headers,
            body: body,
            pathParams: [:]  // Path params will be extracted by Router
        )
    }
    
    /// Parse query string into dictionary
    private static func parseQueryString(_ queryString: String) -> [String: String] {
        var parameters: [String: String] = [:]
        
        let pairs = queryString.components(separatedBy: "&")
        for pair in pairs {
            let keyValue = pair.components(separatedBy: "=")
            if keyValue.count == 2 {
                let key = keyValue[0].removingPercentEncoding ?? keyValue[0]
                let value = keyValue[1].removingPercentEncoding ?? keyValue[1]
                parameters[key] = value
            }
        }
        
        return parameters
    }
    
    /// Decode JSON body to Decodable type
    func decodeBody<T: Decodable>(_ type: T.Type) throws -> T {
        guard let body = body else {
            throw HTTPRequestError.missingBody
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: body)
    }
    
    /// Get body as readable string for error messages
    var bodyString: String {
        guard let body = body, !body.isEmpty else {
            return "<no body>"
        }
        
        if let jsonString = String(data: body, encoding: .utf8) {
            return jsonString.isEmpty ? "<empty body>" : jsonString
        }
        
        return "<\(body.count) bytes, non-UTF8>"
    }
}

// MARK: - Errors

enum HTTPRequestError: Error, LocalizedError {
    case missingBody
    case invalidJSON
    
    var errorDescription: String? {
        switch self {
        case .missingBody:
            return "Request body is missing"
        case .invalidJSON:
            return "Invalid JSON in request body"
        }
    }
}
