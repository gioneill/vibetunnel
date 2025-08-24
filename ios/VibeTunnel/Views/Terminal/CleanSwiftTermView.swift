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
        updateFont(size: 14, weight: .regular)

        // Use system colors that adapt to light/dark mode
        nativeForegroundColor = .label
        nativeBackgroundColor = .systemBackground
        
        // Configure terminal behavior with optimal settings
        configureTerminalBehavior()

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

    /// Apply a complete terminal theme with full ANSI color palette
    func applyAdvancedTheme(_ theme: TerminalTheme) {
        // Base colors
        nativeForegroundColor = UIColor(theme.foreground)
        nativeBackgroundColor = UIColor(theme.background)
        caretColor = UIColor(theme.cursor)
        selectedTextBackgroundColor = UIColor(theme.selection)
        
        // Full 16-color ANSI palette (0-15)
        let ansiColors: [SwiftTerm.Color] = [
            // Normal colors (0-7)
            UIColor(theme.black).toSwiftTermColor(),      // 0
            UIColor(theme.red).toSwiftTermColor(),        // 1
            UIColor(theme.green).toSwiftTermColor(),      // 2
            UIColor(theme.yellow).toSwiftTermColor(),     // 3
            UIColor(theme.blue).toSwiftTermColor(),       // 4
            UIColor(theme.magenta).toSwiftTermColor(),    // 5
            UIColor(theme.cyan).toSwiftTermColor(),       // 6
            UIColor(theme.white).toSwiftTermColor(),      // 7
            // Bright colors (8-15)
            UIColor(theme.brightBlack).toSwiftTermColor(), // 8
            UIColor(theme.brightRed).toSwiftTermColor(),   // 9
            UIColor(theme.brightGreen).toSwiftTermColor(), // 10
            UIColor(theme.brightYellow).toSwiftTermColor(),// 11
            UIColor(theme.brightBlue).toSwiftTermColor(),  // 12
            UIColor(theme.brightMagenta).toSwiftTermColor(),// 13
            UIColor(theme.brightCyan).toSwiftTermColor(),  // 14
            UIColor(theme.brightWhite).toSwiftTermColor()  // 15
        ]
        
        installColors(ansiColors)
        logger.info("Applied theme '\(theme.name)' with full ANSI color palette")
    }

    /// Helper method to apply a basic terminal theme (backward compatibility)
    func applyTheme(foreground: UIColor, background: UIColor, cursor: UIColor? = nil) {
        nativeForegroundColor = foreground
        nativeBackgroundColor = background

        if let cursorColor = cursor {
            caretColor = cursorColor
        }
    }

    /// Install ANSI color palette from UIColors
    func installColorPalette(_ colors: [UIColor]) {
        guard colors.count >= 16 else {
            logger.warning("Color palette must have at least 16 colors")
            return
        }
        let swiftTermColors = colors.map { $0.toSwiftTermColor() }
        installColors(swiftTermColors)
    }
    
    // MARK: - Font Configuration
    
    /// Update font with size and weight
    func updateFont(size: CGFloat, weight: UIFont.Weight = .regular) {
        font = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        setNeedsDisplay()
        logger.debug("Font updated to size \(size) with weight \(weight.rawValue)")
    }
    
    /// Update font with custom font
    func updateFont(customFont: UIFont) {
        font = customFont
        setNeedsDisplay()
        logger.debug("Font updated to custom font: \(customFont.fontName) size \(customFont.pointSize)")
    }
    
    // MARK: - Terminal Configuration
    
    /// Configure terminal behavior with optimal settings
    func configureTerminalBehavior() {
        // Input handling
        allowMouseReporting = false
        optionAsMetaKey = true
        
        // Performance optimizations
        layer.shouldRasterize = false
        contentMode = .redraw
        
        // Accessibility
        isAccessibilityElement = true
        accessibilityTraits = [.keyboardKey, .updatesFrequently]
        
        logger.debug("Terminal behavior configured with optimal settings")
    }
}
