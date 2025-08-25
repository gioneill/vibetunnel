import os
import SwiftTerm
import SwiftUI

private let logger = Logger(category: "SwiftTermHost")

struct SwiftTermHostingView: UIViewRepresentable {
    var viewModel: TerminalViewModel

    // MARK: - Coordinator

    class Coordinator: NSObject, TerminalViewDelegate {
        let parent: SwiftTermHostingView
        var lastBufferUpdate: Date = Date()

        // Viewport tracking for scrolling through large buffers
        private var viewportStart: Int = 0
        private var totalBufferRows: Int = 0
        private var terminalVisibleRows: Int = 50 // Will be updated from actual terminal
        var isAtBottom: Bool = true

        init(_ parent: SwiftTermHostingView) {
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

    func makeUIView(context: Context) -> SwiftTermView {
        logger.info("Creating SwiftTermView (raw ANSI mode)")

        let terminalView = SwiftTermView(frame: .zero)

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

    func updateUIView(_ uiView: SwiftTermView, context: Context) {
        // Only handle focus and theme changes
        if viewModel.shouldBecomeFirstResponder {
            _ = uiView.becomeFirstResponder()
        }
        if viewModel.themeChanged {
            applyTheme(to: uiView)
        }
    }

    // MARK: - Helper Methods

    private func applyTheme(to terminalView: SwiftTermView) {
        // Apply theme using the enhanced theme system
        if let theme = viewModel.selectedTheme {
            terminalView.applyAdvancedTheme(theme)
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
