import Foundation

/// ANSI color codes for terminal output
enum ANSIColor: String {
    case reset = "\u{001B}[0m"
    
    // Regular colors
    case black = "\u{001B}[30m"
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case magenta = "\u{001B}[35m"
    case cyan = "\u{001B}[36m"
    case white = "\u{001B}[37m"
    
    // Bright colors
    case brightBlack = "\u{001B}[90m"
    case brightRed = "\u{001B}[91m"
    case brightGreen = "\u{001B}[92m"
    case brightYellow = "\u{001B}[93m"
    case brightBlue = "\u{001B}[94m"
    case brightMagenta = "\u{001B}[95m"
    case brightCyan = "\u{001B}[96m"
    case brightWhite = "\u{001B}[97m"
    
    // Styles
    case bold = "\u{001B}[1m"
    case dim = "\u{001B}[2m"
    case italic = "\u{001B}[3m"
    case underline = "\u{001B}[4m"
}

/// Helper for colorized terminal output
struct ColorPrint {
    /// Check if terminal supports colors
    private static var supportsColors: Bool {
        guard let term = ProcessInfo.processInfo.environment["TERM"] else {
            return false
        }
        return term != "dumb" && isatty(STDOUT_FILENO) != 0
    }
    
    /// Apply color to text if terminal supports it
    static func color(_ text: String, _ color: ANSIColor) -> String {
        guard supportsColors else { return text }
        return "\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)"
    }
    
    /// Apply multiple styles to text
    static func styled(_ text: String, _ styles: [ANSIColor]) -> String {
        guard supportsColors else { return text }
        let prefix = styles.map(\.rawValue).joined()
        return "\(prefix)\(text)\(ANSIColor.reset.rawValue)"
    }
    
    // MARK: - Convenience Methods
    
    static func success(_ message: String) -> String {
        color("✅ \(message)", .green)
    }
    
    static func error(_ message: String) -> String {
        color("❌ \(message)", .red)
    }
    
    static func warning(_ message: String) -> String {
        color("⚠️  \(message)", .yellow)
    }
    
    static func info(_ message: String) -> String {
        color("ℹ️  \(message)", .cyan)
    }
    
    static func loading(_ message: String) -> String {
        color("🔄 \(message)", .blue)
    }
    
    static func header(_ text: String) -> String {
        styled(text, [.bold, .brightCyan])
    }
    
    static func label(_ text: String) -> String {
        color(text, .brightBlack)
    }
    
    static func value(_ text: String) -> String {
        color(text, .white)
    }
    
    static func highlight(_ text: String) -> String {
        color(text, .brightYellow)
    }
    
    static func code(_ text: String) -> String {
        color(text, .cyan)
    }
    
    static func comment(_ text: String) -> String {
        color(text, .brightBlack)
    }
}

// MARK: - String Extension for Fluent API

extension String {
    func colored(_ color: ANSIColor) -> String {
        ColorPrint.color(self, color)
    }
    
    func styled(_ styles: [ANSIColor]) -> String {
        ColorPrint.styled(self, styles)
    }
    
    var bold: String {
        styled([.bold])
    }
    
    var dim: String {
        styled([.dim])
    }
    
    var success: String {
        ColorPrint.success(self)
    }
    
    var error: String {
        ColorPrint.error(self)
    }
    
    var warning: String {
        ColorPrint.warning(self)
    }
    
    var info: String {
        ColorPrint.info(self)
    }
}
