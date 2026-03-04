import Foundation

/// Request handler type
typealias RouteHandler = @Sendable (HTTPRequest) async -> Response

/// Routes HTTP requests to handlers
@MainActor
final class Router: Sendable {
    
    private var routes: [Route] = []
    
    /// Register a GET route
    func get(_ path: String, handler: @escaping RouteHandler) {
        routes.append(Route(method: .GET, path: path, handler: handler))
    }
    
    /// Register a POST route
    func post(_ path: String, handler: @escaping RouteHandler) {
        routes.append(Route(method: .POST, path: path, handler: handler))
    }
    
    /// Register a PUT route
    func put(_ path: String, handler: @escaping RouteHandler) {
        routes.append(Route(method: .PUT, path: path, handler: handler))
    }
    
    /// Register a DELETE route
    func delete(_ path: String, handler: @escaping RouteHandler) {
        routes.append(Route(method: .DELETE, path: path, handler: handler))
    }
    
    /// Handle incoming request
    func handle(_ request: HTTPRequest) async -> Response {
        // Handle OPTIONS preflight requests for CORS
        if request.method == .OPTIONS {
            return Response(
                statusCode: .noContent,
                headers: [:]  // CORS headers will be added automatically in toData()
            )
        }
        
        // Find matching route and extract path parameters
        for route in routes {
            if let pathParams = route.matchesAndExtract(request) {
                // Create new request with path parameters
                var requestWithParams = request
                requestWithParams = HTTPRequest(
                    method: request.method,
                    path: request.path,
                    queryParameters: request.queryParameters,
                    headers: request.headers,
                    body: request.body,
                    pathParams: pathParams
                )
                
                return await route.handler(requestWithParams)
            }
        }
        
        // No matching route found
        return Response.error(
            .notFound,
            message: "Endpoint not found: \(request.method.rawValue) \(request.path)",
            suggestion: "Check the API documentation for available endpoints"
        )
    }
}

// MARK: - Route

private struct Route: Sendable {
    let method: HTTPMethod
    let path: String
    let handler: RouteHandler
    
    /// Check if request matches this route and extract path parameters
    /// - Parameter request: The HTTP request to match
    /// - Returns: Dictionary of path parameters if match, nil otherwise
    func matchesAndExtract(_ request: HTTPRequest) -> [String: String]? {
        guard request.method == method else { return nil }
        
        let routeComponents = path.split(separator: "/").map(String.init)
        let requestComponents = request.path.split(separator: "?")[0]
            .split(separator: "/").map(String.init)
        
        guard routeComponents.count == requestComponents.count else {
            return nil
        }
        
        var pathParams: [String: String] = [:]
        
        for (routePart, requestPart) in zip(routeComponents, requestComponents) {
            if routePart.hasPrefix(":") {
                // This is a path parameter
                let paramName = String(routePart.dropFirst())
                pathParams[paramName] = requestPart
            } else if routePart != requestPart {
                // Path doesn't match
                return nil
            }
        }
        
        return pathParams
    }
    
    func matches(_ request: HTTPRequest) -> Bool {
        return request.method == method && request.path == path
    }
}
