import Foundation
import Network
import UIKit

/// HTTP server using Apple's Network framework
@MainActor
final class HTTPServer: Sendable {
    
    let port: Int
    private let listener: NWListener
    private var connections: [HTTPConnection] = []
    private var connectionTasks: [Task<Void, Never>] = []
    private let router: Router
    private var isRunning = false
    
    init(port: Int) throws {
        self.port = port
        
        // Create listener with TCP on specified port
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        guard let listener = try? NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port))) else {
            throw HTTPServerError.failedToCreateListener
        }
        
        self.listener = listener
        self.router = Router()
        
        setupRoutes()
    }
    
    deinit {
        // Cancel all tasks on deallocation
        for task in connectionTasks {
            task.cancel()
        }
    }
    
    /// Start the HTTP server
    func start() async throws {
        guard !isRunning else {
            throw HTTPServerError.alreadyRunning
        }
        
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleStateChange(state)
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }
        
        listener.start(queue: .main)
        isRunning = true
    }
    
    /// Stop the HTTP server
    func stop() async {
        guard isRunning else { return }
        
        // Cancel all connection tasks first
        for task in connectionTasks {
            task.cancel()
        }
        connectionTasks.removeAll()
        
        // Cancel the listener
        listener.cancel()
        
        // Close all active connections
        for connection in connections {
            await connection.close()
        }
        connections.removeAll()
        
        isRunning = false
    }
    
    // MARK: - Private Methods
    
    private func handleStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("📡 Server listening on port \(port)")
        case .failed(let error):
            print("❌ Server failed: \(error.localizedDescription)")
        case .cancelled:
            print("⚠️ Server cancelled")
        default:
            break
        }
    }
    
    private func handleNewConnection(_ nwConnection: NWConnection) {
        let connection = HTTPConnection(connection: nwConnection, router: router)
        connections.append(connection)
        
        // Track the task so we can cancel it on shutdown
        let task = Task {
            await connection.start()            
        }
        connectionTasks.append(task)
    }
    
    // MARK: - Helper Methods
    
    /// Safely execute a block on the main thread, avoiding deadlock
    /// If already on main thread, executes directly. Otherwise dispatches to main.
//    nonisolated private func ensureMainThread<T: Sendable>(_ block: @MainActor () throws -> T) rethrows -> T {
//        if Thread.isMainThread {
//            return try MainActor.assumeIsolated(block)
//        } else {
//            return try DispatchQueue.main.sync {
//                try MainActor.assumeIsolated(block)
//            }
//        }
//    }
    
    nonisolated private func ensureMainThread<T: Sendable>(_ block: @MainActor () throws -> T) async rethrows -> T {
        try await MainActor.run {
            try block()
        }
    }
    
    // MARK: - Route Setup
    
    private func setupRoutes() {
        // Health check endpoint
        router.get("/health") { request in
            return Response(
                statusCode: .ok,
                body: ["status": "ok", "version": "1.0.0"]
            )
        }
        
        // MARK: - Configuration Endpoints
        
        // GET /config - Get current configuration
        router.get("/config") { request in
            let config = ConfigurationService.shared.getConfiguration()
            
            let response = ConfigurationResponse(
                config: config,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
            
            return Response(statusCode: .ok, body: response)
        }
        
        // POST /config - Update configuration
        router.post("/config") { request in
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
            let config = ConfigurationService.shared.resetConfiguration()
            
            let response = ConfigurationResponse(
                config: config,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
            
            return Response(statusCode: .ok, body: response)
        }
        
        // App list endpoint
        router.get("/app/list") { request in
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
                
                let pid = try await AppController.shared.launch(
                    bundleId: launchRequest.bundleId,
                    arguments: launchRequest.arguments ?? [],
                    environment: launchRequest.environment ?? [:]
                )
                
                let response = LaunchAppResponse(
                    success: true,
                    bundleId: launchRequest.bundleId,
                    pid: pid,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                return Response.error(
                    .internalServerError,
                    message: error.localizedDescription
                )
            }
        }
        
        router.post("/app/terminate") { _ in
            do {
                try await AppController.shared.terminate()
                
                let response = TerminateAppResponse(
                    success: true,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        router.get("/app/state") { _ in
            do {
                let state = try await AppController.shared.getState()
                return Response(statusCode: .ok, body: state)
            } catch {
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        router.post("/app/activate") { _ in
            do {
                try await AppController.shared.activate()
                return Response.success(["success": true])
            } catch {
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // UI tree and element query endpoints
        router.get("/ui/tree") { request in
            do {
                let app = try await AppController.shared.getCurrentApp()
                
                // Parse maxDepth from query params (default: 20)
                let maxDepth: Int = request.queryParams["maxDepth"].flatMap { Int($0) } ?? 20
                
                let root = await self.ensureMainThread {
                    ElementQuery.getUITree(from: app, maxDepth: maxDepth)
                }
                
                let response = UITreeResponse(
                    root: root,
                    timestamp: ISO8601DateFormatter().string(from: Date()),
                    depth: maxDepth
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        router.post("/ui/find") { request in
            do {
                guard let findRequest = try? request.decodeBody(FindElementsRequest.self) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid request body. Expected: { \"identifier\": \"buttonId\" }, { \"label\": \"Submit\" }, or { \"predicate\": \"label CONTAINS 'text'\" }. Received: \(request.bodyString)"
                    )
                }
                
                let app = try await AppController.shared.getCurrentApp()
                
                // ElementQuery.findElements is synchronous (XCTest APIs are synchronous)
                // Use ensureMainThread to avoid deadlock
                let elements = try await self.ensureMainThread {
                    try ElementQuery.findElements(
                        in: app,
                        identifier: findRequest.identifier,
                        label: findRequest.label,
                        predicate: findRequest.predicate,
                        timeout: findRequest.timeout ?? ConfigurationService.shared.getDefaultTimeout(),
                        waitStrategy: findRequest.waitStrategy ?? .wait
                    )
                }
                
                let response = ElementsResponse(
                    elements: elements,
                    count: elements.count,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                return Response.error(
                    .notFound,
                    message: error.localizedDescription
                )
            }
        }
        
        router.get("/ui/element/:identifier") { request in
            do {
                guard let identifier = request.pathParams["identifier"] else {
                    return Response.error(
                        .badRequest,
                        message: "Missing element identifier in path"
                    )
                }
                
                let app = try await AppController.shared.getCurrentApp()
                
                // Parse query params
                let timeout: TimeInterval = request.queryParams["timeout"]
                    .flatMap { Double($0) } ?? ConfigurationService.shared.getDefaultTimeout()
                let waitStrategyStr = request.queryParams["waitStrategy"] ?? "wait"
                let waitStrategy: FindElementsRequest.WaitStrategy = 
                    waitStrategyStr == "immediate" ? .immediate : .wait
                
                let element = try await self.ensureMainThread {
                    try ElementQuery.findElement(
                        in: app,
                        identifier: identifier,
                        timeout: timeout,
                        waitStrategy: waitStrategy
                    )
                }
                
                let response = ElementResponse(
                    element: element,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                return Response.error(
                    .notFound,
                    message: error.localizedDescription
                )
            }
        }
        
        router.post("/ui/tap") { request in
            do {
                guard let tapRequest = try? request.decodeBody(TapRequest.self) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid request body. Expected: { \"identifier\": \"elementId\" } or { \"label\": \"text\" } or { \"predicate\": \"label == 'Button'\" }. Received: \(request.bodyString)"
                    )
                }
                
                let app = try await AppController.shared.getCurrentApp()
                
                let _ = try await self.ensureMainThread {
                    try ElementQuery.tap(
                        in: app,
                        identifier: tapRequest.identifier,
                        label: tapRequest.label,
                        predicate: tapRequest.predicate,
                        timeout: tapRequest.timeout ?? ConfigurationService.shared.getDefaultTimeout(),
                        waitStrategy: tapRequest.waitStrategy ?? .wait
                    )
                }
                
                let response = TapResponse(
                    success: true,
                    identifier: tapRequest.identifier,
                    label: tapRequest.label,
                    predicate: tapRequest.predicate,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                return Response.error(
                    .notFound,
                    message: error.localizedDescription
                )
            }
        }
        
        router.post("/ui/type") { request in
            do {
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
                
                let app = try await AppController.shared.getCurrentApp()
                
                let _ = try await self.ensureMainThread {
                    try ElementQuery.typeText(
                        typeRequest.text,
                        in: app,
                        identifier: typeRequest.identifier,
                        label: typeRequest.label,
                        predicate: typeRequest.predicate,
                        timeout: typeRequest.timeout ?? ConfigurationService.shared.getDefaultTimeout(),
                        waitStrategy: typeRequest.waitStrategy ?? .wait,
                        clearFirst: typeRequest.clearFirst ?? false
                    )
                }
                
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
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // MARK: - Swipe
        
        router.post("/ui/swipe") { request in
            do {
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
                
                let app = try await AppController.shared.getCurrentApp()
                
                let _ = try await self.ensureMainThread {
                    try ElementQuery.swipe(
                        in: app,
                        direction: swipeRequest.direction,
                        identifier: swipeRequest.identifier,
                        label: swipeRequest.label,
                        predicate: swipeRequest.predicate,
                        velocity: swipeRequest.velocity ?? "fast",
                        timeout: swipeRequest.timeout ?? ConfigurationService.shared.getDefaultTimeout(),
                        waitStrategy: swipeRequest.waitStrategy ?? .wait
                    )
                }
                
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
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // MARK: - Scroll
        
        router.post("/ui/scroll") { request in
            do {
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
                
                let app = try await AppController.shared.getCurrentApp()
                
                let _ = try await self.ensureMainThread {
                    try ElementQuery.scrollToElement(
                        in: app,
                        toElementIdentifier: scrollRequest.toElementIdentifier,
                        toElementPredicate: scrollRequest.toElementPredicate,
                        scrollContainerIdentifier: scrollRequest.scrollContainerIdentifier,
                        scrollContainerPredicate: scrollRequest.scrollContainerPredicate,
                        timeout: scrollRequest.timeout ?? (ConfigurationService.shared.getDefaultTimeout() * 2),
                        waitStrategy: scrollRequest.waitStrategy ?? .wait
                    )
                }
                
                let response = ScrollResponse(
                    success: true,
                    toElementIdentifier: scrollRequest.toElementIdentifier,
                    toElementPredicate: scrollRequest.toElementPredicate,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
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
                
                let app = try await AppController.shared.getCurrentApp()
                
                let _ = try await self.ensureMainThread {
                    try ElementQuery.keyboardType(
                        in: app,
                        text: keyboardRequest.text,
                        keys: keyboardRequest.keys
                    )
                }
                
                let response = KeyboardTypeResponse(
                    success: true,
                    text: keyboardRequest.text,
                    keys: keyboardRequest.keys,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // GET /screenshot - Capture full screen
        router.get("/screenshot") { request in
            let pngData = await ScreenshotService.captureFullScreen()
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
            
            return Response(statusCode: .ok, body: response)
        }
        
        // POST /screenshot/element - Capture element screenshot
        router.post("/screenshot/element") { request in
            guard let screenshotRequest = try? request.decodeBody(ElementScreenshotRequest.self) else {
                return Response.error(
                    .badRequest,
                    message: "Invalid request body. Expected: { \"identifier\": \"elementId\" } or { \"label\": \"text\" } or { \"predicate\": \"label CONTAINS 'text'\" }. Received: \(request.bodyString)"
                )
            }
            
            do {
                let app = try await AppController.shared.getCurrentApp()
                let timeout = screenshotRequest.timeout ?? ConfigurationService.shared.getDefaultTimeout()
                let waitStrategy = screenshotRequest.waitStrategy ?? .wait
                
                let (pngData, node) = try await ScreenshotService.captureElement(
                    in: app,
                    identifier: screenshotRequest.identifier,
                    label: screenshotRequest.label,
                    predicate: screenshotRequest.predicate,
                    timeout: timeout,
                    waitStrategy: waitStrategy
                )
                
                let base64 = ScreenshotService.pngToBase64(pngData)
                
                let response = ElementScreenshotResponse(
                    image: base64,
                    element: node,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                return Response.error(
                    .notFound,
                    message: error.localizedDescription
                )
            }
        }
        
        // POST /screenshot/compare - Compare screenshots
        router.post("/screenshot/compare") { request in
            guard let compareRequest = try? request.decodeBody(CompareScreenshotRequest.self) else {
                return Response.error(
                    .badRequest,
                    message: "Invalid request body. Expected: { \"referenceImage\": \"base64EncodedPNG\", \"threshold\": 0.95 }. Received: \(request.bodyString)"
                )
            }
            
            do {
                let currentPngData = await ScreenshotService.captureFullScreen()
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
                
                return Response(statusCode: .ok, body: response)
            } catch {
                return Response.error(
                    .badRequest,
                    message: error.localizedDescription
                )
            }
        }
        
        // POST /ui/validate - Soft validation
        router.post("/ui/validate") { request in
            guard let validateRequest = try? request.decodeBody(ValidateRequest.self) else {
                return Response.error(
                    .badRequest,
                    message: "Invalid request body. Expected: { \"validations\": [{\"identifier\": \"id\", \"property\": \"isEnabled\", \"expectedValue\": \"true\"}] }. Received: \(request.bodyString)"
                )
            }
            
            do {
                let app = try await AppController.shared.getCurrentApp()
                
                let results = await ValidationService.validate(
                    in: app,
                    validations: validateRequest.validations
                )
                
                let passedCount = results.filter { $0.passed }.count
                let failedCount = results.count - passedCount
                
                let response = ValidateResponse(
                    results: results,
                    allPassed: failedCount == 0,
                    passedCount: passedCount,
                    failedCount: failedCount,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // POST /ui/assert - Hard assertion
        router.post("/ui/assert") { request in
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
                let app = try await AppController.shared.getCurrentApp()
                
                let rule = ValidationRule(
                    identifier: assertRequest.identifier,
                    label: assertRequest.label,
                    predicate: assertRequest.predicate,
                    property: assertRequest.property,
                    expectedValue: assertRequest.expectedValue,
                    timeout: assertRequest.timeout ?? ConfigurationService.shared.getDefaultTimeout()
                )
                
                try await ValidationService.assert(in: app, assertion: rule)
                
                let response = AssertResponse(
                    success: true,
                    property: assertRequest.property,
                    expected: assertRequest.expectedValue,
                    actual: assertRequest.expectedValue,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch let error as ValidationError {
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
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // POST /ui/wait - Explicit wait for condition
        router.post("/ui/wait") { request in
            guard let waitRequest = try? request.decodeBody(WaitRequest.self) else {
                return Response.error(
                    .badRequest,
                    message: "Invalid request body. Expected: { \"condition\": \"exists\", \"identifier\": \"elementId\", \"timeout\": 10 }. Received: \(request.bodyString)"
                )
            }
            
            do {
                let app = try await AppController.shared.getCurrentApp()
                
                // Parse wait condition
                guard let condition = WaitService.WaitCondition(rawValue: waitRequest.condition) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid wait condition '\(waitRequest.condition)'",
                        details: "Valid conditions: exists, notExists, isEnabled, isDisabled, isHittable, isNotHittable, hasFocus, isSelected, isNotSelected, labelContains, labelEquals, valueContains, valueEquals"
                    )
                }
                
                let timeout = waitRequest.timeout ?? ConfigurationService.shared.getDefaultTimeout()
                
                // Bridge async HTTP to sync XCTest operation
                return await MainActor.run {
                    do {
                        // Call synchronous wait (no await!)
                        let result = try WaitService.wait(
                            in: app,
                            condition: condition,
                            identifier: waitRequest.identifier,
                            label: waitRequest.label,
                            predicate: waitRequest.predicate,
                            value: waitRequest.value,
                            timeout: timeout,
                            softValidation: false
                        )
                        
                        let response = WaitResponse(
                            conditionMet: result.success,
                            condition: waitRequest.condition,
                            element: result.element,
                            waitedTime: result.actualTime,
                            timestamp: ISO8601DateFormatter().string(from: Date())
                        )
                        
                        return Response(statusCode: .ok, body: response)
                    } catch let error as WaitService.WaitError {
                        return Response.error(
                            .requestTimeout,
                            message: error.localizedDescription,
                            details: "Condition '\(waitRequest.condition)' was not met within timeout"
                        )
                    } catch {
                        return Response.error(
                            .conflict,
                            message: error.localizedDescription
                        )
                    }
                }
            } catch {
                return Response.error(
                    .badRequest,
                    message: "Failed to get app: \(error.localizedDescription)"
                )
            }
        }
        
        // MARK: - Alert Endpoints
        
        // GET /ui/alerts - List active alerts
        router.get("/ui/alerts") { request in
            do {
                let app = try await AppController.shared.getCurrentApp()
                
                let alerts = await AlertService.detectAlerts(in: app)
                
                let response = AlertsResponse(
                    alerts: alerts,
                    count: alerts.count,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch {
                return Response.error(
                    .conflict,
                    message: error.localizedDescription
                )
            }
        }
        
        // POST /ui/alert/dismiss - Dismiss alert by button label
        router.post("/ui/alert/dismiss") { request in
            do {
                guard let body = request.body,
                      let dismissRequest = try? JSONDecoder().decode(DismissAlertRequest.self, from: body) else {
                    return Response.error(
                        .badRequest,
                        message: "Invalid request body. Expected: { \"buttonLabel\": \"Allow\" }. Received: \(request.bodyString)",
                        suggestion: "Provide a buttonLabel field with the text of the button to tap"
                    )
                }
                
                let app = try await AppController.shared.getCurrentApp()
                
                let dismissed = try await AlertService.dismissAlert(
                    in: app,
                    buttonLabel: dismissRequest.buttonLabel,
                    timeout: dismissRequest.timeout ?? ConfigurationService.shared.getDefaultTimeout()
                )
                
                let response = DismissAlertResponse(
                    dismissed: dismissed,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                
                return Response(statusCode: .ok, body: response)
            } catch let error as AlertError {
                return Response.error(
                    .notFound,
                    message: error.localizedDescription,
                    suggestion: error.recoverySuggestion
                )
            } catch {
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
    case failedToCreateListener
    case alreadyRunning
    case notRunning
    
    var errorDescription: String? {
        switch self {
        case .failedToCreateListener:
            return "Failed to create network listener"
        case .alreadyRunning:
            return "Server is already running"
        case .notRunning:
            return "Server is not running"
        }
    }
}
