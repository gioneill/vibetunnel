import os
import SwiftTerm
import SwiftUI

private let logger = Logger(category: "CleanSwiftTermHost")

struct CleanSwiftTermHostingView: UIViewRepresentable {
    var viewModel: TerminalViewModel

    // MARK: - Coordinator

    class Coordinator: NSObject, TerminalViewDelegate {
        let parent: CleanSwiftTermHostingView
        var lastBufferUpdate: Date = Date()

        // Viewport tracking for scrolling through large buffers
        private var viewportStart: Int = 0
        private var totalBufferRows: Int = 0
        private var terminalVisibleRows: Int = 50 // Will be updated from actual terminal
        var isAtBottom: Bool = true

        init(_ parent: CleanSwiftTermHostingView) {
            self.parent = parent
            super.init()
        }

        // MARK: TerminalViewDelegate

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            // Forward input to the server (dispatch on main without capturing self)
            logger.debug("Sending \(data.count) bytes to server")
            let bytes = Array(data)
            let viewModel = parent.viewModel
            DispatchQueue.main.async {
                if let string = String(bytes: bytes, encoding: .utf8) {
                    viewModel.sendInput(string)
                }
            }
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            // Notify server of terminal size change
            logger.info("Terminal resized to \(newCols)x\(newRows)")
            let viewModel = parent.viewModel
            DispatchQueue.main.async {
                viewModel.resize(cols: newCols, rows: newRows)
            }
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {
            // Update viewport position based on scroll
            updateViewportFromScroll(position: position)

            // Update scroll state for UI
            let viewModel = parent.viewModel
            let currentIsAtBottom = self.isAtBottom // Capture before async
            DispatchQueue.main.async {
                viewModel.updateScrollState(isAtBottom: currentIsAtBottom)
            }
        }

        // MARK: - Viewport Management

        func updateBufferState(totalRows: Int, viewportY: Int, cursorY: Int) {
            self.totalBufferRows = totalRows

            // Honor server's viewportY if provided, otherwise maintain current position
            if viewportY > 0 {
                self.viewportStart = max(0, min(viewportY, totalRows - terminalVisibleRows))
            }

            // Auto-scroll when new content arrives and we're at bottom
            if isAtBottom && cursorY >= totalRows - terminalVisibleRows {
                scrollToBottom()
            }
        }

        func getVisibleWindow(bufferSize: Int) -> (start: Int, end: Int) {
            let clampedStart = max(0, min(viewportStart, bufferSize - terminalVisibleRows))
            let clampedEnd = min(clampedStart + terminalVisibleRows, bufferSize)
            return (clampedStart, clampedEnd)
        }

        private func updateViewportFromScroll(position: Double) {
            // Convert SwiftTerm's scroll position to our viewport
            let maxScroll = max(0, totalBufferRows - terminalVisibleRows)
            let newViewportStart = Int(position * Double(maxScroll))

            viewportStart = max(0, min(newViewportStart, maxScroll))
            isAtBottom = position >= 0.95
        }

        func scrollToBottom() {
            let maxScroll = max(0, totalBufferRows - terminalVisibleRows)
            viewportStart = maxScroll
            isAtBottom = true
        }

        func updateTerminalDimensions(rows: Int) {
            // Avoid zero rows which would produce an empty viewport
            if rows > 0 {
                self.terminalVisibleRows = rows
            }
        }

        func convertBufferToANSI(_ snapshot: TerminalHostingView.BufferSnapshot) -> String {
            var output = ""

            // Update buffer tracking
            updateBufferState(
                totalRows: snapshot.rows,
                viewportY: snapshot.viewportY,
                cursorY: snapshot.cursorY
            )

            // Start frame: hide cursor, reset, move to home
            output += "\u{001B}[?25l" // Hide cursor (prevent flicker)
            output += "\u{001B}[0m" // Reset all attributes
            output += "\u{001B}[H" // Move cursor home

            // Get viewport window (fall back to a reasonable default if rows not initialized yet)
            if terminalVisibleRows <= 0 {
                // Default to a common terminal height until we learn the real value
                terminalVisibleRows = 24
            }

            let (visibleStart, visibleEnd) = getVisibleWindow(bufferSize: snapshot.cells.count)
            let visibleRows = Array(snapshot.cells[visibleStart..<min(visibleEnd, snapshot.cells.count)])

            // Adjust cursor position relative to visible window
            let adjustedCursorY = snapshot.cursorY - visibleStart

            // Process each visible row
            for rowIndex in 0..<visibleRows.count {
                // Position cursor at start of line (1-based)
                output += "\u{001B}[\(rowIndex + 1);1H"

                let row = visibleRows[rowIndex]

                // Track current attributes for optimization
                var currentFg: Int? = nil
                var currentBg: Int? = nil
                var currentAttrs: Int = 0

                // Process cells in row
                for cell in row {
                    // Handle attribute changes
                    if let attrs = cell.attributes, attrs != currentAttrs {
                        output += "\u{001B}[0m" // Reset
                        currentFg = nil
                        currentBg = nil
                        currentAttrs = attrs

                        // Apply text attributes
                        if (attrs & 0x01) != 0 { output += "\u{001B}[1m" } // Bold
                        if (attrs & 0x02) != 0 { output += "\u{001B}[3m" } // Italic
                        if (attrs & 0x04) != 0 { output += "\u{001B}[4m" } // Underline
                        if (attrs & 0x08) != 0 { output += "\u{001B}[2m" } // Dim
                        if (attrs & 0x10) != 0 { output += "\u{001B}[7m" } // Inverse
                        if (attrs & 0x40) != 0 { output += "\u{001B}[9m" } // Strikethrough
                    } else if cell.attributes == nil && currentAttrs != 0 {
                        output += "\u{001B}[0m" // Reset if no attributes
                        currentFg = nil
                        currentBg = nil
                        currentAttrs = 0
                    }

                    // Handle foreground color
                    if cell.fg != currentFg {
                        currentFg = cell.fg
                        if let fg = cell.fg {
                            if fg <= 255 {
                                output += "\u{001B}[38;5;\(fg)m"
                            }
                        } else {
                            output += "\u{001B}[39m" // Default foreground
                        }
                    }

                    // Handle background color
                    if cell.bg != currentBg {
                        currentBg = cell.bg
                        if let bg = cell.bg {
                            if bg <= 255 {
                                output += "\u{001B}[48;5;\(bg)m"
                            }
                        } else {
                            output += "\u{001B}[49m" // Default background
                        }
                    }

                    // Output the character (or space if empty)
                    output += cell.char.isEmpty ? " " : cell.char
                }

                // Clear to end of line (removes any leftover content)
                output += "\u{001B}[K"
            }

            // Clear everything below last drawn row
            output += "\u{001B}[J"

            // Reset attributes
            output += "\u{001B}[0m"

            // Position cursor (1-based, using adjusted cursor position)
            let cursorRow = max(1, min(terminalVisibleRows, adjustedCursorY + 1))
            let cursorCol = max(1, snapshot.cursorX + 1)
            output += "\u{001B}[\(cursorRow);\(cursorCol)H"

            // Show cursor
            output += "\u{001B}[?25h"

            return output
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
            // Update terminal title if needed
            logger.debug("Terminal title set: \(title)")
        }

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            // Handle clipboard copy
            if let str = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = str
                logger.debug("Copied \(str.count) characters to clipboard")
            }
        }

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
            // Track buffer changes if needed for debugging
            logger.debug("Buffer changed from row \(startY) to \(endY)")
        }

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            // Handle current directory updates
            if let dir = directory {
                logger.debug("Current directory: \(dir)")
            }
        }

        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            // Handle link opening requests
            if let url = URL(string: link) {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> CleanSwiftTermView {
        logger.info("Creating CleanSwiftTermView (raw ANSI mode)")

        let terminalView = CleanSwiftTermView(frame: .zero)

        // Set the delegate through coordinator
        terminalView.terminalDelegate = context.coordinator

        // Apply theme if available
        applyTheme(to: terminalView)
        
        // Wire up raw ANSI feed - direct and simple!
        viewModel.onRawANSIUpdate = { [weak terminalView] ansiData in
            guard let terminalView = terminalView else { return }
            
            DispatchQueue.main.async {
                terminalView.feed(text: ansiData)
            }
        }

        // Initial size setup
        if viewModel.terminalCols > 0 && viewModel.terminalRows > 0 {
            terminalView.resize(cols: viewModel.terminalCols, rows: viewModel.terminalRows)
        }

        // Ensure keyboard input works
        _ = terminalView.becomeFirstResponder()

        return terminalView
    }

    func updateUIView(_ uiView: CleanSwiftTermView, context: Context) {
        // Only handle focus and theme changes
        if viewModel.shouldBecomeFirstResponder {
            _ = uiView.becomeFirstResponder()
        }
        if viewModel.themeChanged {
            applyTheme(to: uiView)
        }
    }

    // MARK: - Helper Methods

    private func applyTheme(to terminalView: CleanSwiftTermView) {
        // Apply theme colors
        if let theme = viewModel.selectedTheme {
            let foreground = UIColor(theme.foreground)
            let background = UIColor(theme.background)
            let cursor = UIColor(theme.cursor)

            terminalView.applyTheme(
                foreground: foreground,
                background: background,
                cursor: cursor
            )

            // Install ANSI colors (0-15: basic colors + bright variants)
            let ansiColors = [
                // Normal colors (0-7)
                UIColor(theme.black),
                UIColor(theme.red),
                UIColor(theme.green),
                UIColor(theme.yellow),
                UIColor(theme.blue),
                UIColor(theme.magenta),
                UIColor(theme.cyan),
                UIColor(theme.white),
                // Bright colors (8-15) - use the same colors but lighter
                UIColor(theme.brightBlack),
                UIColor(theme.brightRed),
                UIColor(theme.brightGreen),
                UIColor(theme.brightYellow),
                UIColor(theme.brightBlue),
                UIColor(theme.brightMagenta),
                UIColor(theme.brightCyan),
                UIColor(theme.brightWhite)
            ]

            terminalView.installColorPalette(ansiColors)
        }
    }
}

// MARK: - UIColor Extension for Hex Colors

extension UIColor {
    fileprivate convenience init?(hex: String) {
        let r, g, b: CGFloat

        var hexColor = hex
        if hexColor.hasPrefix("#") {
            hexColor = String(hexColor.dropFirst())
        }

        if hexColor.count == 6 {
            let scanner = Scanner(string: hexColor)
            var hexNumber: UInt64 = 0

            if scanner.scanHexInt64(&hexNumber) {
                r = CGFloat((hexNumber & 0xFF0000) >> 16) / 255
                g = CGFloat((hexNumber & 0x00FF00) >> 8) / 255
                b = CGFloat(hexNumber & 0x0000FF) / 255

                self.init(red: r, green: g, blue: b, alpha: 1)
                return
            }
        }

        return nil
    }
}
