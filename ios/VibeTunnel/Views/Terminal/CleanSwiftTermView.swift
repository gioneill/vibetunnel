import os
import SwiftTerm
import UIKit

private let logger = Logger(category: "CleanSwiftTerm")

/// A minimal SwiftTerm TerminalView subclass with basic configuration
class CleanSwiftTermView: SwiftTerm.TerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTerminal()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTerminal()
    }

    private func setupTerminal() {
        // Set a reasonable default font
        font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)

        // Use system colors that adapt to light/dark mode
        nativeForegroundColor = .label
        nativeBackgroundColor = .systemBackground

        // Log initialization
        let terminal = getTerminal()
        logger.info("CleanSwiftTermView initialized with cols: \(terminal.cols), rows: \(terminal.rows)")
    }

    deinit {
        // Critical: invalidate the CADisplayLink to prevent retain cycles
        // Use async dispatch to avoid main actor issues in deinit
        DispatchQueue.main.async { [weak self] in
            self?.updateUiClosed()
        }
        logger.info("CleanSwiftTermView deinitialized")
    }

    /// Helper method to apply a terminal theme
    func applyTheme(foreground: UIColor, background: UIColor, cursor: UIColor? = nil) {
        nativeForegroundColor = foreground
        nativeBackgroundColor = background

        if let cursorColor = cursor {
            caretColor = cursorColor
        }
    }

    /// Install ANSI color palette
    func installColorPalette(_ colors: [UIColor]) {
        guard colors.count >= 16 else {
            logger.warning("Color palette must have at least 16 colors")
            return
        }
        // Convert UIColors to SwiftTerm Color type
        let swiftTermColors = colors.map { uiColor -> Color in
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return Color(
                red: UInt16(red * 65_535),
                green: UInt16(green * 65_535),
                blue: UInt16(blue * 65_535)
            )
        }
        installColors(swiftTermColors)
    }
}
