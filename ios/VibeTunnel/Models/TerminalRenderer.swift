import Foundation

/// Available terminal renderer implementations.
/// Allows users to choose between native Swift or web-based terminal rendering.
enum TerminalRenderer: String, CaseIterable, Codable {
    case swiftTerm = "SwiftTerm"
    case xterm = "xterm.js"
    case swiftTermClean = "SwiftTermClean"

    var displayName: String {
        switch self {
        case .swiftTerm:
            "SwiftTerm (Native)"
        case .xterm:
            "xterm.js (WebView)"
        case .swiftTermClean:
            "SwiftTerm (Clean)"
        }
    }

    var description: String {
        switch self {
        case .swiftTerm:
            "Native Swift terminal emulator with best performance"
        case .xterm:
            "JavaScript-based terminal, identical to web version"
        case .swiftTermClean:
            "Minimal SwiftTerm implementation for debugging"
        }
    }

    /// The currently selected renderer (persisted in UserDefaults)
    static var selected: Self {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: "selectedTerminalRenderer"),
               let renderer = Self(rawValue: rawValue)
            {
                return renderer
            }
            return .swiftTerm // Default
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedTerminalRenderer")
        }
    }
}
