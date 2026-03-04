import Foundation
import CoreGraphics

/// Custom encoding for CGRect to match expected {x, y, width, height} format
extension CGRect {
    enum CodingKeys: String, CodingKey {
        case x, y, width, height
    }
}

/// Custom encoder to override CGRect's default array-based encoding
extension JSONEncoder {
    static func configuredForIOSAgentDriver() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

/// Wrapper to encode CGRect as flat object instead of nested arrays
struct FrameWrapper: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    
    init(from rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }
    
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
