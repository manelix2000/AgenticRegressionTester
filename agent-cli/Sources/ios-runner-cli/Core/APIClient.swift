import Foundation

/// HTTP client for communicating with IOSAgentDriver API
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()
    
    private let session: URLSession
    private let lock = NSLock()
    
    enum APIError: LocalizedError {
        case sessionNotFound(String)
        case sessionNotReady(String)
        case invalidURL(String)
        case networkError(Error)
        case invalidResponse
        case httpError(Int, String)
        case decodingError(Error)
        case encodingError(Error)
        
        var errorDescription: String? {
            switch self {
            case .sessionNotFound(let id):
                return "Session not found: \(id)"
            case .sessionNotReady(let id):
                return "Session not ready: \(id). Status must be 'ready' or 'running'"
            case .invalidURL(let url):
                return "Invalid URL: \(url)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from IOSAgentDriver"
            case .httpError(let code, let message):
                return "HTTP \(code): \(message)"
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            case .encodingError(let error):
                return "Failed to encode request: \(error.localizedDescription)"
            }
        }
    }
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Session Lookup
    
    /// Get the base URL for a session
    private func getBaseURL(for sessionId: String) throws -> URL {
        guard let session = SessionManager.shared.getSession(sessionId) else {
            throw APIError.sessionNotFound(sessionId)
        }
        
        // Check session is ready
        guard session.status == .ready || session.status == .running else {
            throw APIError.sessionNotReady(sessionId)
        }
        
        guard let url = URL(string: "http://localhost:\(session.port)") else {
            throw APIError.invalidURL("http://localhost:\(session.port)")
        }
        
        return url
    }
    
    // MARK: - HTTP Methods
    
    /// Perform GET request
    func get<T: Decodable>(_ path: String, sessionId: String) async throws -> T {
        let baseURL = try getBaseURL(for: sessionId)
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL("\(baseURL)\(path)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(httpResponse.statusCode, errorMessage)
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
    
    /// Perform POST request with response
    func post<T: Decodable, Body: Encodable>(_ path: String, body: Body, sessionId: String) async throws -> T {
        let baseURL = try getBaseURL(for: sessionId)
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL("\(baseURL)\(path)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
        } catch {
            throw APIError.encodingError(error)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(httpResponse.statusCode, errorMessage)
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
    
    /// Perform POST request without response body
    func postNoResponse<Body: Encodable>(_ path: String, body: Body, sessionId: String) async throws {
        let baseURL = try getBaseURL(for: sessionId)
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL("\(baseURL)\(path)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
        } catch {
            throw APIError.encodingError(error)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(httpResponse.statusCode, errorMessage)
        }
    }
    
    /// Perform GET request without decoding (for raw data like screenshots)
    func getRaw(_ path: String, sessionId: String) async throws -> Data {
        let baseURL = try getBaseURL(for: sessionId)
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL("\(baseURL)\(path)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(httpResponse.statusCode, errorMessage)
        }
        
        return data
    }
}
