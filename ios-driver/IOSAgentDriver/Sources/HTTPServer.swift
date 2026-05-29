import Foundation
import Swifter
import UIKit

/// HTTP server backed by Swifter.
/// Bridges Swifter's request/response types to our internal `HTTPRequest` / `Response` types,
/// delegating all routing to the existing `Router`.
final class HTTPServer {
    
    let port: Int
    private let server: HttpServer
    private let router: Router
    private var isRunning = false
    
    init(port: Int) throws {
        self.port = port
        self.server = HttpServer()
        var configuredRouter = Router()
        HTTPServer.setupRoutes(&configuredRouter)
        self.router = configuredRouter
    }
    
    /// Start the HTTP server on the configured port.
    func start() throws {
        guard !isRunning else {
            throw HTTPServerError.alreadyRunning
        }
        
        // Use middleware to intercept every request and delegate to our Router.
        // Returning a non-nil HttpResponse short-circuits Swifter's own routing.
        let router = self.router
        server.middleware.append { [weak self] swifterRequest in
            guard self != nil else { return .internalServerError }
            let httpRequest = HTTPServer.convertRequest(swifterRequest)
            let response = router.handle(httpRequest)
            return HTTPServer.convertResponse(response)
        }
        
        try server.start(UInt16(port), forceIPv4: true, priority: .userInitiated)
        isRunning = true
        DriverLog.log("📡 Server listening on port \(port)")
    }
    
    /// Stop the HTTP server.
    func stop() {
        guard isRunning else { return }
        server.stop()
        isRunning = false
        DriverLog.log("⚠️ Server stopped")
    }
    
    // MARK: - Type Bridging
    
    /// Converts a Swifter `HttpRequest` into our internal `HTTPRequest`.
    private static func convertRequest(_ swifterRequest: HttpRequest) -> HTTPRequest {
        let method = HTTPMethod(rawValue: swifterRequest.method) ?? .GET
        
        // Swifter's path already strips the query string
        let path = swifterRequest.path
        
        // Convert query params from [(String, String)] to [String: String]
        var queryParameters: [String: String] = [:]
        for (key, value) in swifterRequest.queryParams {
            queryParameters[key] = value
        }
        
        // Body: Swifter delivers body as [UInt8]
        let bodyData: Data? = swifterRequest.body.isEmpty ? nil : Data(swifterRequest.body)
        
        return HTTPRequest(
            method: method,
            path: path,
            queryParameters: queryParameters,
            headers: swifterRequest.headers,
            body: bodyData,
            pathParams: [:]
        )
    }
    
    /// Converts our internal `Response` into a Swifter `HttpResponse`.
    private static func convertResponse(_ response: Response) -> HttpResponse {
        // Build combined headers including CORS
        var allHeaders = response.headers
        allHeaders["Access-Control-Allow-Origin"] = "*"
        allHeaders["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        allHeaders["Access-Control-Allow-Headers"] = "Content-Type, Accept, Authorization"
        allHeaders["Access-Control-Max-Age"] = "86400"
        allHeaders["Connection"] = "close"
        
        if let body = response.body {
            allHeaders["Content-Length"] = "\(body.count)"
        }
        
        return .raw(
            response.statusCode.rawValue,
            response.statusCode.reasonPhrase,
            allHeaders
        ) { writer in
            if let body = response.body {
                try writer.write(body)
            }
        }
    }
    
    // MARK: - Route Setup
    
    private static func setupRoutes(_ router: inout Router) {
        // Health check endpoint
        router.get("/health") { request in
            DriverLog.log("➡️ GET /health")
            return Response(
                statusCode: .ok,
                body: ["status": "ok", "version": "1.0.0"]
            )
        }
        
        // MARK: - Configuration Endpoints
        
        // GET /config - Get current configuration
        router.get("/config") { request in
            DriverLog.log("➡️ GET /config")
            let config = ConfigurationService.shared.getConfiguration()
            
            let response = ConfigurationResponse(
                config: config,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
            
            return Response(statusCode: .ok, body: response)
        }
        
        // POST /config - Update configuration
        router.post("/config") { request in
            DriverLog.log("➡️ POST /config")
            guard let body = request.body,
                  let updates = try? JSONDecoder().decode(ConfigurationUpdate.self, from: body) else {
                return Response.error(
                    .badRequest,
                    message: "Invalid request body. Expected: { \"defaultTimeout\": 10, \"errorVerbosity\": \"verbose\", \"maxConcurrentRequests\": 20 }. Received: \(request.bodyString)",
                    suggestion: "All fields are optional. Provide only the fields you want to update."
                )
            }
            
            let updatedConfig = ConfigurationService.shared.updateConfiguration(updates)
            
            // Track which fields were updated
            var updatedFields: [String] = []
            if updates.defaultTimeout != nil {
                updatedFields.append("defaultTimeout")
            }
            if updates.errorVerbosity != nil {
                updatedFields.append("errorVerbosity")
            }
            if updates.maxConcurrentRequests != nil {
                updatedFields.append("maxConcurrentRequests")
            }
            
            let response = ConfigurationUpdateResponse(
                config: updatedConfig,
                updated: updatedFields,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
            
            return Response(statusCode: .ok, body: response)
        }
        
        // POST /config/reset - Reset configuration to defaults
        router.post("/config/reset") { request in
            DriverLog.log("➡️ POST /config/reset")
            let config = ConfigurationService.shared.resetConfiguration()
            
            let response = ConfigurationResponse(
                config: config,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
            
            return Response(statusCode: .ok, body: response)
        }
        
        // App list endpoint
        router.get("/app/list") { request in
            DriverLog.log("➡️ GET /app/list")
            // Get installed applications from ProcessInfo helper
            let bundleIds = ProcessInfo.processInfo.getInstalledApplications()
            
            let response = AppListResponse(
                applications: bundleIds,
                count: bundleIds.count,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
            
            return Response(statusCode: .ok, body: response)
        }
        
        // App lifecycle endpoints
        router.post("/app/launch") { request in
            do {
                guard let launchRequest = try? request.decodeBody(LaunchAppRequest.self) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid request body. Expected: { \"bundleId\": \"com.example.app\", \"arguments\": [], \"environment\": {} }. Received: \(request.bodyString)"
                    )
                }
                
                DriverLog.log("➡️ POST /app/launch | bundleId=\(launchRequest.bundleId)")
                DriverLog.log("POST /app/launch: dispatching to main queue")
                let pid = try DispatchQueue.main.sync {
                    try AppController.shared.launch(
                        bundleId: launchRequest.bundleId,
                        arguments: launchRequest.arguments ?? [],
                        environment: launchRequest.environment ?? [:]
                    )
                }
                
                DriverLog.log("✅ POST /app/launch completed | bundleId=\(launchRequest.bundleId) pid=\(pid)")
                
                let response = LaunchAppResponse(
                    success: true,
                    bundleId: launchRequest.bundleId,
                    pid: pid,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ POST /app/launch failed: \(error.localizedDescription)")
                return Response.error(
                    .internalServerError,
                    message: error.localizedDescription
                )
            }
        }
        
        router.post("/app/terminate") { _ in
            do {
                DriverLog.log("➡️ POST /app/terminate")
                DriverLog.log("POST /app/terminate: dispatching to main queue")
                try DispatchQueue.main.sync { try AppController.shared.terminate() }
                DriverLog.log("✅ POST /app/terminate completed")
                
                let response = TerminateAppResponse(
                    success: true,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ POST /app/terminate failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        router.get("/app/state") { _ in
            do {
                DriverLog.log("➡️ GET /app/state")
                DriverLog.log("GET /app/state: dispatching to main queue")
                let state = try DispatchQueue.main.sync { try AppController.shared.getState() }
                DriverLog.log("✅ GET /app/state completed")
                return Response(statusCode: .ok, body: state)
            } catch {
                DriverLog.log("❌ GET /app/state failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        router.post("/app/activate") { _ in
            do {
                DriverLog.log("➡️ POST /app/activate")
                DriverLog.log("POST /app/activate: dispatching to main queue")
                try DispatchQueue.main.sync { try AppController.shared.activate() }
                DriverLog.log("✅ POST /app/activate completed")
                return Response.success(["success": true])
            } catch {
                DriverLog.log("❌ POST /app/activate failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // UI tree and element query endpoints
        router.get("/ui/tree") { request in
            do {
                DriverLog.log("➡️ GET /ui/tree")
                // Parse maxDepth from query params (default: 20)
                let maxDepth: Int = request.queryParams["maxDepth"].flatMap { Int($0) } ?? 15
                
                DriverLog.log("GET /ui/tree: dispatching to main queue | maxDepth=\(maxDepth)")
                
                let root = try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        try ElementQuery.getUITree(from: app, maxDepth: maxDepth)
                    }
                }
                
                let response = UITreeResponse(
                    root: root,
                    timestamp: ISO8601DateFormatter().string(from: Date()),
                    depth: maxDepth
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ GET /ui/tree failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        router.post("/ui/find") { request in
            do {
                let defaultTimeout = ConfigurationService.shared.getDefaultTimeout()
                guard let findRequest = try? request.decodeBody(FindElementsRequest.self) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid request body. Expected: { \"identifier\": \"buttonId\" }, { \"label\": \"Submit\" }, or { \"predicate\": \"label CONTAINS 'text'\" }. Received: \(request.bodyString)"
                    )
                }
                
                DriverLog.log("➡️ POST /ui/find | identifier=\(findRequest.identifier ?? "-") label=\(findRequest.label ?? "-") predicate=\(findRequest.predicate ?? "-")")
                DriverLog.log("POST /ui/find: dispatching to main queue")
                let elements = try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        try ElementQuery.findElements(
                            in: app,
                            identifier: findRequest.identifier,
                            label: findRequest.label,
                            predicate: findRequest.predicate,
                            timeout: findRequest.timeout ?? defaultTimeout,
                            waitStrategy: findRequest.waitStrategy ?? .wait
                        )
                    }
                }
                
                let response = ElementsResponse(
                    elements: elements,
                    count: elements.count,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                DriverLog.log("✅ POST /ui/find completed | count=\(elements.count)")
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ POST /ui/find failed: \(error.localizedDescription)")
                return Response.error(
                    .notFound,
                    message: error.localizedDescription
                )
            }
        }
        
        router.get("/ui/element/:identifier") { request in
            do {
                DriverLog.log("➡️ GET /ui/element/:identifier")
                let defaultTimeout = ConfigurationService.shared.getDefaultTimeout()
                guard let identifier = request.pathParams["identifier"] else {
                    return Response.error(
                        .badRequest,
                        message: "Missing element identifier in path"
                    )
                }
                
                // Parse query params
                let timeout: TimeInterval = request.queryParams["timeout"]
                    .flatMap { Double($0) } ?? defaultTimeout
                let waitStrategyStr = request.queryParams["waitStrategy"] ?? "wait"
                let waitStrategy: FindElementsRequest.WaitStrategy = 
                    waitStrategyStr == "immediate" ? .immediate : .wait
                
                DriverLog.log("GET /ui/element: dispatching to main queue | identifier=\(identifier)")
                let element = try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        try ElementQuery.findElement(
                            in: app,
                            identifier: identifier,
                            timeout: timeout,
                            waitStrategy: waitStrategy
                        )
                    }
                }
                
                DriverLog.log("✅ GET /ui/element completed | identifier=\(identifier)")
                
                let response = ElementResponse(
                    element: element,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ GET /ui/element failed: \(error.localizedDescription)")
                return Response.error(
                    .notFound,
                    message: error.localizedDescription
                )
            }
        }
        
        router.post("/ui/tap") { request in
            do {
                let defaultTimeout = ConfigurationService.shared.getDefaultTimeout()
                guard let tapRequest = try? request.decodeBody(TapRequest.self) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid request body. Expected: { \"identifier\": \"elementId\" } or { \"label\": \"text\" } or { \"predicate\": \"label == 'Button'\" }. Received: \(request.bodyString)"
                    )
                }
                
                DriverLog.log("➡️ POST /ui/tap | identifier=\(tapRequest.identifier ?? "-") label=\(tapRequest.label ?? "-") predicate=\(tapRequest.predicate ?? "-")")
                DriverLog.log("POST /ui/tap: dispatching to main queue")
                
                try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        try ElementQuery.tap(
                            in: app,
                            identifier: tapRequest.identifier,
                            label: tapRequest.label,
                            predicate: tapRequest.predicate,
                            timeout: tapRequest.timeout ?? defaultTimeout,
                            waitStrategy: tapRequest.waitStrategy ?? .wait
                        )
                    }
                }
                
                let response = TapResponse(
                    success: true,
                    identifier: tapRequest.identifier,
                    label: tapRequest.label,
                    predicate: tapRequest.predicate,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                DriverLog.log("✅ POST /ui/tap completed")
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ POST /ui/tap failed: \(error.localizedDescription)")
                return Response.error(
                    .notFound,
                    message: error.localizedDescription
                )
            }
        }
        
        router.post("/ui/tap-coordinate") { request in
            do {
                guard let tapRequest = try? request.decodeBody(TapCoordinateRequest.self) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid request body. Expected: { \"x\": 100, \"y\": 200 }. Received: \(request.bodyString)"
                    )
                }

                DriverLog.log("➡️ POST /ui/tap-coordinate | x=%.1f y=%.1f")
                DriverLog.log("POST /ui/tap-coordinate: dispatching to main queue")
                try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        ElementQuery.tapAtCoordinate(in: app, x: tapRequest.x, y: tapRequest.y)
                    }
                }

                DriverLog.log("✅ POST /ui/tap-coordinate completed")
                let response = TapCoordinateResponse(
                    success: true,
                    x: tapRequest.x,
                    y: tapRequest.y,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )

                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ POST /ui/tap-coordinate failed: \(error.localizedDescription)")
                return Response.error(
                    .internalServerError,
                    message: error.localizedDescription
                )
            }
        }

        router.post("/ui/type") { request in
            do {
                let defaultTimeout = ConfigurationService.shared.getDefaultTimeout()
                guard let typeRequest = try? request.decodeBody(TypeTextRequest.self) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid request body. Expected: { \"text\": \"hello\", \"identifier\": \"searchField\" } or { \"text\": \"hello\", \"label\": \"Search\" }. Received: \(request.bodyString)"
                    )
                }
                
                guard !typeRequest.text.isEmpty else {
                    return Response.error(
                        .badRequest,
                        message: "Text cannot be empty"
                    )
                }
                
                DriverLog.log("➡️ POST /ui/type | identifier=\(typeRequest.identifier ?? "-") label=\(typeRequest.label ?? "-") predicate=\(typeRequest.predicate ?? "-") textLength=\(typeRequest.text.count) clearFirst=\(typeRequest.clearFirst ?? false)")
                DriverLog.log("POST /ui/type: dispatching to main queue")
                try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        try ElementQuery.typeText(
                            typeRequest.text,
                            in: app,
                            identifier: typeRequest.identifier,
                            label: typeRequest.label,
                            predicate: typeRequest.predicate,
                            timeout: typeRequest.timeout ?? defaultTimeout,
                            waitStrategy: typeRequest.waitStrategy ?? .wait,
                            clearFirst: typeRequest.clearFirst ?? false
                        )
                    }
                }
                
                DriverLog.log("✅ POST /ui/type completed")
                let response = TypeTextResponse(
                    success: true,
                    text: typeRequest.text,
                    identifier: typeRequest.identifier,
                    label: typeRequest.label,
                    predicate: typeRequest.predicate,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ POST /ui/type failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // MARK: - Swipe
        
        router.post("/ui/swipe") { request in
            do {
                let defaultTimeout = ConfigurationService.shared.getDefaultTimeout()
                guard let swipeRequest = try? request.decodeBody(SwipeRequest.self) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid request body. Expected: { \"direction\": \"up\", \"identifier\": \"scrollView\" } or { \"label\": \"ScrollView\" } or { \"predicate\": \"label == 'View'\" }. Received: \(request.bodyString)"
                    )
                }
                
                guard !swipeRequest.direction.isEmpty else {
                    return Response.error(
                        .badRequest,
                        message: "Direction cannot be empty. Must be 'up', 'down', 'left', or 'right'"
                    )
                }
                
                DriverLog.log("➡️ POST /ui/swipe | direction=\(swipeRequest.direction) identifier=\(swipeRequest.identifier ?? "-") label=\(swipeRequest.label ?? "-")")
                DriverLog.log("POST /ui/swipe: dispatching to main queue")
                try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        try ElementQuery.swipe(
                            in: app,
                            direction: swipeRequest.direction,
                            identifier: swipeRequest.identifier,
                            label: swipeRequest.label,
                            predicate: swipeRequest.predicate,
                            velocity: swipeRequest.velocity ?? "fast",
                            timeout: swipeRequest.timeout ?? defaultTimeout,
                            waitStrategy: swipeRequest.waitStrategy ?? .wait
                        )
                    }
                }
                
                DriverLog.log("✅ POST /ui/swipe completed")
                let response = SwipeResponse(
                    success: true,
                    direction: swipeRequest.direction,
                    identifier: swipeRequest.identifier,
                    label: swipeRequest.label,
                    predicate: swipeRequest.predicate,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ POST /ui/swipe failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // MARK: - Scroll
        
        router.post("/ui/scroll") { request in
            do {
                let defaultTimeout = ConfigurationService.shared.getDefaultTimeout()
                guard let scrollRequest = try? request.decodeBody(ScrollRequest.self) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid request body. Expected: { \"toElementIdentifier\": \"targetElement\" } or { \"toElementPredicate\": \"label == 'Target'\" }. Received: \(request.bodyString)"
                    )
                }
                
                guard scrollRequest.toElementIdentifier != nil || scrollRequest.toElementPredicate != nil else {
                    return Response.error(
                        .badRequest,
                        message: "Must provide either 'toElementIdentifier' or 'toElementPredicate'"
                    )
                }
                
                DriverLog.log("➡️ POST /ui/scroll | toId=\(scrollRequest.toElementIdentifier ?? "-") toPredicate=\(scrollRequest.toElementPredicate ?? "-")")
                DriverLog.log("POST /ui/scroll: dispatching to main queue")
                try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        try ElementQuery.scrollToElement(
                            in: app,
                            toElementIdentifier: scrollRequest.toElementIdentifier,
                            toElementPredicate: scrollRequest.toElementPredicate,
                            scrollContainerIdentifier: scrollRequest.scrollContainerIdentifier,
                            scrollContainerPredicate: scrollRequest.scrollContainerPredicate,
                            timeout: scrollRequest.timeout ?? (defaultTimeout * 2),
                            waitStrategy: scrollRequest.waitStrategy ?? .wait
                        )
                    }
                }
                
                DriverLog.log("✅ POST /ui/scroll completed")
                let response = ScrollResponse(
                    success: true,
                    toElementIdentifier: scrollRequest.toElementIdentifier,
                    toElementPredicate: scrollRequest.toElementPredicate,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ POST /ui/scroll failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // MARK: - Keyboard
        
        router.post("/ui/keyboard/type") { request in
            do {
                guard let keyboardRequest = try? request.decodeBody(KeyboardTypeRequest.self) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid request body. Expected: { \"text\": \"hello\" } or { \"keys\": [\"return\"] }. Received: \(request.bodyString)"
                    )
                }
                
                guard keyboardRequest.text != nil || keyboardRequest.keys != nil else {
                    return Response.error(
                        .badRequest,
                        message: "Must provide either 'text' or 'keys'"
                    )
                }
                
                DriverLog.log("➡️ POST /ui/keyboard/type | textLength=\(keyboardRequest.text?.count ?? 0) keysCount=\(keyboardRequest.keys?.count ?? 0)")
                DriverLog.log("POST /ui/keyboard/type: dispatching to main queue")
                try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        try ElementQuery.keyboardType(
                            in: app,
                            text: keyboardRequest.text,
                            keys: keyboardRequest.keys
                        )
                    }
                }
                
                DriverLog.log("✅ POST /ui/keyboard/type completed")
                let response = KeyboardTypeResponse(
                    success: true,
                    text: keyboardRequest.text,
                    keys: keyboardRequest.keys,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ POST /ui/keyboard/type failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // GET /screenshot - Capture full screen
        router.get("/screenshot") { request in
            DriverLog.log("➡️ GET /screenshot")
            DriverLog.log("GET /screenshot: dispatching to main queue")
            let pngData = DispatchQueue.main.sync { ScreenshotService.captureFullScreen() }
            let base64 = ScreenshotService.pngToBase64(pngData)
            
            // Get screen dimensions from the screenshot
            guard let image = UIImage(data: pngData),
                  let cgImage = image.cgImage else {
                return Response.error(
                    .internalServerError,
                    message: "Failed to process screenshot"
                )
            }
            
            let response = ScreenshotResponse(
                image: base64,
                width: cgImage.width,
                height: cgImage.height,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
                
            DriverLog.log("✅ GET /screenshot completed")
            return Response(statusCode: .ok, body: response)
        }
        
        // POST /screenshot/element - Capture element screenshot
        router.post("/screenshot/element") { request in
            DriverLog.log("➡️ POST /screenshot/element")
            guard let screenshotRequest = try? request.decodeBody(ElementScreenshotRequest.self) else {
                return Response.error(
                    .badRequest,
                    message: "Invalid request body. Expected: { \"identifier\": \"elementId\" } or { \"label\": \"text\" } or { \"predicate\": \"label CONTAINS 'text'\" }. Received: \(request.bodyString)"
                )
            }
            
            do {
                let defaultTimeout = ConfigurationService.shared.getDefaultTimeout()
                let timeout = screenshotRequest.timeout ?? defaultTimeout
                let waitStrategy = screenshotRequest.waitStrategy ?? .wait
                
                DriverLog.log("POST /screenshot/element: dispatching to main queue")
                let (pngData, node) = try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        try ScreenshotService.captureElement(
                            in: app,
                            identifier: screenshotRequest.identifier,
                            label: screenshotRequest.label,
                            predicate: screenshotRequest.predicate,
                            timeout: timeout,
                            waitStrategy: waitStrategy
                        )
                    }
                }
                
                let base64 = ScreenshotService.pngToBase64(pngData)
                
                let response = ElementScreenshotResponse(
                    image: base64,
                    element: node,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                DriverLog.log("✅ POST /screenshot/element completed")
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ POST /screenshot/element failed: \(error.localizedDescription)")
                return Response.error(
                    .notFound,
                    message: error.localizedDescription
                )
            }
        }
        
        // GET /ocr - Capture full screen and run OCR
        router.get("/ocr") { _ in
            do {
                DriverLog.log("➡️ GET /ocr")
                DriverLog.log("GET /ocr: dispatching to main queue")
                let document = try DispatchQueue.main.sync { try OcrService.recognize() }
                DriverLog.log("✅ GET /ocr completed")
                return Response(statusCode: .ok, body: document)
            } catch {
                DriverLog.log("❌ GET /ocr failed: \(error.localizedDescription)")
                return Response.error(
                    .internalServerError,
                    message: error.localizedDescription
                )
            }
        }
        
        // POST /screenshot/compare - Compare screenshots
        router.post("/screenshot/compare") { request in
            DriverLog.log("➡️ POST /screenshot/compare")
            guard let compareRequest = try? request.decodeBody(CompareScreenshotRequest.self) else {
                return Response.error(
                    .badRequest,
                    message: "Invalid request body. Expected: { \"referenceImage\": \"base64EncodedPNG\", \"threshold\": 0.95 }. Received: \(request.bodyString)"
                )
            }
            
            do {
                DriverLog.log("POST /screenshot/compare: dispatching to main queue")
                let currentPngData = DispatchQueue.main.sync { ScreenshotService.captureFullScreen() }
                let threshold = compareRequest.threshold ?? 0.95
                
                let result = try ScreenshotService.compareScreenshots(
                    referenceBase64: compareRequest.referenceImage,
                    currentPngData: currentPngData,
                    threshold: threshold
                )
                
                let response = CompareScreenshotResponse(
                    match: result.match,
                    similarity: result.similarity,
                    differenceCount: result.differenceCount,
                    totalPixels: result.totalPixels,
                    diffImage: result.diffImageBase64,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                DriverLog.log("✅ POST /screenshot/compare completed")
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ POST /screenshot/compare failed: \(error.localizedDescription)")
                return Response.error(
                    .badRequest,
                    message: error.localizedDescription
                )
            }
        }
        
        // POST /ui/validate - Soft validation
        router.post("/ui/validate") { request in
            DriverLog.log("➡️ POST /ui/validate")
            guard let validateRequest = try? request.decodeBody(ValidateRequest.self) else {
                return Response.error(
                    .badRequest,
                    message: "Invalid request body. Expected: { \"validations\": [{\"identifier\": \"id\", \"property\": \"isEnabled\", \"expectedValue\": \"true\"}] }. Received: \(request.bodyString)"
                )
            }
            
            do {
                DriverLog.log("POST /ui/validate: dispatching to main queue")
                let results = try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        ValidationService.validate(
                            in: app,
                            validations: validateRequest.validations
                        )
                    }
                }
                
                let passedCount = results.filter { $0.passed }.count
                let failedCount = results.count - passedCount
                
                let response = ValidateResponse(
                    results: results,
                    allPassed: failedCount == 0,
                    passedCount: passedCount,
                    failedCount: failedCount,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                DriverLog.log("✅ POST /ui/validate completed | passed=\(passedCount) failed=\(failedCount)")
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ POST /ui/validate failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // POST /ui/assert - Hard assertion
        router.post("/ui/assert") { request in
            DriverLog.log("➡️ POST /ui/assert")
            guard let assertRequest = try? request.decodeBody(AssertRequest.self) else {
                return Response.error(
                    .badRequest,
                    message: "Invalid request body. Expected: { \"identifier\": \"id\", \"property\": \"isEnabled\", \"expectedValue\": \"true\" }. Received: \(request.bodyString)"
                )
            }
            
            // Parse property enum
            guard let _ = ValidationProperty(rawValue: assertRequest.property) else {
                return Response.error(
                    .badRequest,
                    message: "Invalid property. Must be one of: exists, isEnabled, isVisible, label, value, count"
                )
            }
            
            do {
                let defaultTimeout = ConfigurationService.shared.getDefaultTimeout()
                
                let rule = ValidationRule(
                    identifier: assertRequest.identifier,
                    label: assertRequest.label,
                    predicate: assertRequest.predicate,
                    property: assertRequest.property,
                    expectedValue: assertRequest.expectedValue,
                    timeout: assertRequest.timeout ?? defaultTimeout
                )
                
                DriverLog.log("POST /ui/assert: dispatching to main queue | property=\(assertRequest.property)")
                try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        try ValidationService.assert(in: app, assertion: rule)
                    }
                }
                
                DriverLog.log("✅ POST /ui/assert completed")
                
                let response = AssertResponse(
                    success: true,
                    property: assertRequest.property,
                    expected: assertRequest.expectedValue,
                    actual: assertRequest.expectedValue,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch let error as ValidationError {
                DriverLog.log("❌ POST /ui/assert failed (validation): \(error.localizedDescription)")
                // Return 400 for assertion failures
                if case .assertionFailed(let result) = error {
                    return Response.error(
                        .badRequest,
                        message: result.message,
                        details: "Expected: \(result.expected), Actual: \(result.actual)"
                    )
                }
                return Response.error(
                    .badRequest,
                    message: error.localizedDescription
                )
            } catch {
                DriverLog.log("❌ POST /ui/assert failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // POST /ui/wait - Explicit wait for condition
        router.post("/ui/wait") { request in
            DriverLog.log("➡️ POST /ui/wait")
            guard let waitRequest = try? request.decodeBody(WaitRequest.self) else {
                return Response.error(
                    .badRequest,
                    message: "Invalid request body. Expected: { \"condition\": \"exists\", \"identifier\": \"elementId\", \"timeout\": 10 }. Received: \(request.bodyString)"
                )
            }
            
            let defaultTimeout = ConfigurationService.shared.getDefaultTimeout()
            
            // Parse wait condition
            guard let condition = WaitService.WaitCondition(rawValue: waitRequest.condition) else {
                return Response.error(
                    .badRequest,
                    message: "Invalid wait condition '\(waitRequest.condition)'",
                    details: "Valid conditions: exists, notExists, isEnabled, isDisabled, isHittable, isNotHittable, hasFocus, isSelected, isNotSelected, labelContains, labelEquals, valueContains, valueEquals"
                )
            }
            
            let timeout = waitRequest.timeout ?? defaultTimeout
            
            // Bridge HTTP to sync XCTest operation
            do {
                DriverLog.log("POST /ui/wait: condition=\(waitRequest.condition) timeout=\(waitRequest.timeout) | dispatching to main queue")
                let result = try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        try WaitService.wait(
                            in: app,
                            condition: condition,
                            identifier: waitRequest.identifier,
                            label: waitRequest.label,
                            predicate: waitRequest.predicate,
                            value: waitRequest.value,
                            timeout: timeout,
                            softValidation: false
                        )
                    }
                }
                
                let response = WaitResponse(
                    conditionMet: result.success,
                    condition: waitRequest.condition,
                    element: result.element,
                    waitedTime: result.actualTime,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                DriverLog.log("✅ POST /ui/wait completed | conditionMet=\(result.success ? 1 : 0)")
                return Response(statusCode: .ok, body: response)
            } catch let error as WaitService.WaitError {
                DriverLog.log("❌ POST /ui/wait timeout: \(error.localizedDescription)")
                return Response.error(
                    .requestTimeout,
                    message: error.localizedDescription,
                    details: "Condition '\(waitRequest.condition)' was not met within timeout"
                )
            } catch {
                DriverLog.log("❌ POST /ui/wait failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // MARK: - Alert Endpoints
        
        // GET /ui/alerts - List active alerts
        router.get("/ui/alerts") { request in
            do {
                DriverLog.log("➡️ GET /ui/alerts")
                DriverLog.log("GET /ui/alerts: dispatching to main queue")
                let alerts = try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        AlertService.detectAlerts(in: app)
                    }
                }
                
                let response = AlertsResponse(
                    alerts: alerts,
                    count: alerts.count,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                DriverLog.log("✅ GET /ui/alerts completed | count=\(alerts.count)")
                return Response(statusCode: .ok, body: response)
            } catch {
                DriverLog.log("❌ GET /ui/alerts failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // POST /ui/alert/dismiss - Dismiss alert by button label
        router.post("/ui/alert/dismiss") { request in
            do {
                DriverLog.log("➡️ POST /ui/alert/dismiss")
                let defaultTimeout = ConfigurationService.shared.getDefaultTimeout()
                guard let body = request.body,
                      let dismissRequest = try? JSONDecoder().decode(DismissAlertRequest.self, from: body) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid request body. Expected: { \"buttonLabel\": \"Allow\" }. Received: \(request.bodyString)",
                        suggestion: "Provide a buttonLabel field with the text of the button to tap"
                    )
                }
                
                DriverLog.log("POST /ui/alert/dismiss: buttonLabel=\(dismissRequest.buttonLabel) | dispatching to main queue")
                let dismissed = try DispatchQueue.main.sync {
                    try AppController.shared.withCurrentApp { app in
                        try AlertService.dismissAlert(
                            in: app,
                            buttonLabel: dismissRequest.buttonLabel,
                            timeout: dismissRequest.timeout ?? defaultTimeout
                        )
                    }
                }
                
                let response = DismissAlertResponse(
                    dismissed: dismissed,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                DriverLog.log("✅ POST /ui/alert/dismiss completed")
                return Response(statusCode: .ok, body: response)
            } catch let error as AlertError {
                DriverLog.log("❌ POST /ui/alert/dismiss failed: \(error.localizedDescription)")
                return Response.error(
                    .notFound,
                    message: error.localizedDescription,
                    suggestion: error.recoverySuggestion
                )
            } catch {
                DriverLog.log("❌ POST /ui/alert/dismiss failed: \(error.localizedDescription)")
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
    }
}

// MARK: - Errors

enum HTTPServerError: Error, LocalizedError {
    case alreadyRunning
    case notRunning
    
    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Server is already running"
        case .notRunning:
            return "Server is not running"
        }
    }
}
