import Foundation
import Network

/// Handles individual HTTP connections
@MainActor
final class HTTPConnection: Sendable {
    
    private let connection: NWConnection
    private let router: Router
    private var buffer = Data()
    
    init(connection: NWConnection, router: Router) {
        self.connection = connection
        self.router = router
    }
    
    func start() async {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleStateChange(state)
            }
        }
        
        connection.start(queue: .main)
        await receiveRequest()
    }
    
    func close() async {
        connection.cancel()
    }
    
    // MARK: - Private Methods
    
    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            print("🔗 Connection established")
        case .failed(let error):
            print("❌ Connection failed: \(error.localizedDescription)")
        case .cancelled:
            print("⚠️ Connection cancelled")
        default:
            break
        }
    }
    
    private func receiveRequest() async {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Receive error: \(error.localizedDescription)")
                    await self.close()
                    return
                }
                
                if let data = data, !data.isEmpty {
                    // Append to buffer
                    self.buffer.append(data)
                    
                    // Try to parse complete HTTP request
                    if let request = HTTPRequest.parse(from: self.buffer) {
                        // Check if we have complete body based on Content-Length
                        if self.isRequestComplete(request) {
                            await self.handleRequest(request)
                            self.buffer = Data() // Clear buffer after handling
                        }
                    }
                }
                
                if !isComplete {
                    await self.receiveRequest()
                } else {
                    await self.close()
                }
            }
        }
    }
    
    /// Check if we have received the complete HTTP request based on Content-Length header
    private func isRequestComplete(_ request: HTTPRequest) -> Bool {
        // If no Content-Length header, request is complete (GET, etc.)
        guard let contentLengthStr = request.headers["Content-Length"],
              let contentLength = Int(contentLengthStr) else {
            return true
        }
        
        // Check if body size matches Content-Length
        let bodySize = request.body?.count ?? 0
        return bodySize >= contentLength
    }
    
    private func handleRequest(_ request: HTTPRequest) async {
        print("📨 \(request.method.rawValue) \(request.path)")
        
        let response = await router.handle(request)
        await sendResponse(response)
    }
    
    private func sendResponse(_ response: Response) async {
        let responseData = response.toData()
        
        connection.send(content: responseData, completion: .contentProcessed { error in
            if let error = error {
                print("❌ Send error: \(error.localizedDescription)")
            }
        })
    }
}
