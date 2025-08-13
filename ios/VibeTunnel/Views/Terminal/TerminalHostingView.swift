import SwiftTerm
import SwiftUI

/// UIKit bridge for the SwiftTerm terminal emulator.
///
/// Wraps SwiftTerm's TerminalView in a UIViewRepresentable to integrate
/// with SwiftUI, handling terminal configuration, input/output, and resizing.
struct TerminalHostingView: UIViewRepresentable {
    let session: Session
    @Binding var fontSize: CGFloat
    let theme: TerminalTheme
    let onInput: (String) -> Void
    let onResize: (Int, Int) -> Void
    var viewModel: TerminalViewModel
    @State private var isAutoScrollEnabled = true
    @AppStorage("enableURLDetection")
    private var enableURLDetection = true

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminal = SwiftTerm.TerminalView()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        terminal.contentMode = .redraw

        // Configure terminal appearance with theme
        terminal.backgroundColor = UIColor(theme.background)
        terminal.nativeForegroundColor = UIColor(theme.foreground)
        terminal.nativeBackgroundColor = UIColor(theme.background)

        // Set ANSI colors from theme
        let ansiColors: [SwiftTerm.Color] = [
            UIColor(theme.black).toSwiftTermColor(), // 0
            UIColor(theme.red).toSwiftTermColor(), // 1
            UIColor(theme.green).toSwiftTermColor(), // 2
            UIColor(theme.yellow).toSwiftTermColor(), // 3
            UIColor(theme.blue).toSwiftTermColor(), // 4
            UIColor(theme.magenta).toSwiftTermColor(), // 5
            UIColor(theme.cyan).toSwiftTermColor(), // 6
            UIColor(theme.white).toSwiftTermColor(), // 7
            UIColor(theme.brightBlack).toSwiftTermColor(), // 8
            UIColor(theme.brightRed).toSwiftTermColor(), // 9
            UIColor(theme.brightGreen).toSwiftTermColor(), // 10
            UIColor(theme.brightYellow).toSwiftTermColor(), // 11
            UIColor(theme.brightBlue).toSwiftTermColor(), // 12
            UIColor(theme.brightMagenta).toSwiftTermColor(), // 13
            UIColor(theme.brightCyan).toSwiftTermColor(), // 14
            UIColor(theme.brightWhite).toSwiftTermColor() // 15
        ]
        terminal.installColors(ansiColors)

        // Set cursor color
        terminal.caretColor = UIColor(theme.cursor)

        // Set selection color
        terminal.selectedTextBackgroundColor = UIColor(theme.selection)

        // Set up delegates
        // SwiftTerm's TerminalView uses terminalDelegate, not delegate
        terminal.terminalDelegate = context.coordinator

        // Configure terminal options
        terminal.allowMouseReporting = false
        terminal.optionAsMetaKey = true

        // URL detection is handled by SwiftTerm automatically

        // Configure font
        updateFont(terminal, size: fontSize)

        // Start with server-reported dimensions if available, otherwise use sensible defaults
        // Always honor server's row count as it knows the actual terminal environment
        let serverRows = viewModel.terminalRows > 0 ? viewModel.terminalRows : 24
        let serverCols = viewModel.terminalCols > 0 ? viewModel.terminalCols : 80

        // For width: use screen-based calculation as default (will be overridden by user preference if set)
        let screenBasedCols = Int(UIScreen.main.bounds.width / 9) // Approximate char width
        let cols = viewModel.terminalCols > 0 ? serverCols : screenBasedCols
        let rows = serverRows // Always use server's row count when available
        terminal.resize(cols: cols, rows: rows)

        // Provide terminal instance to coordinator early to avoid races
        context.coordinator.terminal = terminal
        return terminal
    }

    func updateUIView(_ terminal: SwiftTerm.TerminalView, context: Context) {
        updateFont(terminal, size: fontSize)

        // URL detection is handled by SwiftTerm automatically

        // Update theme colors
        terminal.backgroundColor = UIColor(theme.background)
        terminal.nativeForegroundColor = UIColor(theme.foreground)
        terminal.nativeBackgroundColor = UIColor(theme.background)
        terminal.caretColor = UIColor(theme.cursor)
        terminal.selectedTextBackgroundColor = UIColor(theme.selection)

        // Update ANSI colors
        let ansiColors: [SwiftTerm.Color] = [
            UIColor(theme.black).toSwiftTermColor(), // 0
            UIColor(theme.red).toSwiftTermColor(), // 1
            UIColor(theme.green).toSwiftTermColor(), // 2
            UIColor(theme.yellow).toSwiftTermColor(), // 3
            UIColor(theme.blue).toSwiftTermColor(), // 4
            UIColor(theme.magenta).toSwiftTermColor(), // 5
            UIColor(theme.cyan).toSwiftTermColor(), // 6
            UIColor(theme.white).toSwiftTermColor(), // 7
            UIColor(theme.brightBlack).toSwiftTermColor(), // 8
            UIColor(theme.brightRed).toSwiftTermColor(), // 9
            UIColor(theme.brightGreen).toSwiftTermColor(), // 10
            UIColor(theme.brightYellow).toSwiftTermColor(), // 11
            UIColor(theme.brightBlue).toSwiftTermColor(), // 12
            UIColor(theme.brightMagenta).toSwiftTermColor(), // 13
            UIColor(theme.brightCyan).toSwiftTermColor(), // 14
            UIColor(theme.brightWhite).toSwiftTermColor() // 15
        ]
        terminal.installColors(ansiColors)

        // Terminal reference is already set in makeUIView, just update if needed
        if context.coordinator.terminal !== terminal {
            context.coordinator.terminal = terminal
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onInput: onInput,
            onResize: onResize,
            viewModel: viewModel
        )
    }

    private func updateFont(_ terminal: SwiftTerm.TerminalView, size: CGFloat) {
        // Use system monospaced font which has better compatibility with SwiftTerm
        // The custom SF Mono font seems to have rendering issues
        let font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)

        // SwiftTerm uses the font property directly
        terminal.font = font
    }

    // MARK: - Buffer Types

    struct BufferSnapshot {
        let cols: Int
        let rows: Int
        let viewportY: Int
        let cursorX: Int
        let cursorY: Int
        let cells: [[BufferCell]]
    }

    struct BufferCell {
        let char: String
        let width: Int
        let fg: Int?
        let bg: Int?
        let attributes: Int?
    }

    @MainActor
    class Coordinator: NSObject {
        let onInput: (String) -> Void
        let onResize: (Int, Int) -> Void
        let viewModel: TerminalViewModel
        weak var terminal: SwiftTerm.TerminalView?
        private let logger = Logger(category: "Terminal")
        private var displayLink: CADisplayLink?
        private var displayLinkFramesRemaining: Int = 0

        // Track previous buffer state for incremental updates
        private var previousSnapshot: BufferSnapshot?
        private var isFirstUpdate = true

        // Selection support
        private var selectionStart: (x: Int, y: Int)?
        private var selectionEnd: (x: Int, y: Int)?

        init(
            onInput: @escaping (String) -> Void,
            onResize: @escaping (Int, Int) -> Void,
            viewModel: TerminalViewModel
        ) {
            self.onInput = onInput
            self.onResize = onResize
            self.viewModel = viewModel
            super.init()

            // Set the coordinator reference on the viewModel
            Task { @MainActor in
                viewModel.terminalCoordinator = self
                viewModel.notifyCoordinatorReady()
            }
        }

        /// Update terminal buffer from binary buffer data using optimized ANSI sequences
        func updateBuffer(from snapshot: BufferSnapshot) {
            guard let terminal else {
                logger.error("❌ updateBuffer called but terminal is nil!")
                return
            }

            logger.info("🧵 updateBuffer on main thread: \(Thread.isMainThread)")

            // Get the actual terminal dimensions (what iOS can display)
            let terminalRows = terminal.getTerminal().rows

            // Apply viewport windowing if server sent more rows than we can display
            var adjustedSnapshot = snapshot
            if snapshot.rows > terminalRows {
                logger
                    .info(
                        "📐 Windowing: server sent \(snapshot.rows) rows, terminal shows \(terminalRows) rows, cursor at row \(snapshot.cursorY)"
                    )

                // Calculate the visible window to keep cursor in view
                let cursorRow = snapshot.cursorY
                let halfHeight = terminalRows / 2

                let visibleStart: Int = if cursorRow < halfHeight {
                    // Cursor near top - show from beginning
                    0
                } else if cursorRow >= snapshot.rows - halfHeight {
                    // Cursor near bottom - show last rows
                    max(0, snapshot.rows - terminalRows)
                } else {
                    // Cursor in middle - center window around cursor
                    cursorRow - halfHeight
                }

                let visibleEnd = min(visibleStart + terminalRows, snapshot.rows)

                // Extract only the visible cells
                let visibleCells = Array(snapshot.cells[visibleStart..<visibleEnd])

                // Adjust cursor position relative to visible window
                let adjustedCursorY = cursorRow - visibleStart

                logger
                    .info(
                        "📐 Window: showing rows \(visibleStart)-\(visibleEnd - 1), cursor at local row \(adjustedCursorY)"
                    )

                // Create adjusted snapshot with windowed data
                adjustedSnapshot = BufferSnapshot(
                    cols: snapshot.cols,
                    rows: visibleCells.count,
                    viewportY: 0, // Reset viewport since we're windowing
                    cursorX: snapshot.cursorX,
                    cursorY: adjustedCursorY,
                    cells: visibleCells
                )
            }

            // Check if buffer has any visible content
            var visibleCellCount = 0
            var totalCells = 0
            for row in adjustedSnapshot.cells {
                for cell in row {
                    totalCells += 1
                    if cell.char != " " && cell.char != "" && cell.width > 0 {
                        visibleCellCount += 1
                    }
                }
            }

            logger
                .info(
                    "📝 updateBuffer: \(adjustedSnapshot.cols)x\(adjustedSnapshot.rows), cursor: (\(adjustedSnapshot.cursorX),\(adjustedSnapshot.cursorY)), visible cells: \(visibleCellCount)/\(totalCells)"
                )

            // Skip entirely empty buffers unless it's the first update
            if visibleCellCount == 0 && !isFirstUpdate {
                logger.warning("⏭️ Skipping empty buffer update to preserve local content")
                return
            }

            // Check terminal dimensions but don't auto-resize in updateBuffer
            let currentCols = terminal.getTerminal().cols
            let currentRows = terminal.getTerminal().rows

            let dimensionsMismatch = currentCols != adjustedSnapshot.cols || currentRows != adjustedSnapshot.rows
            if dimensionsMismatch {
                logger
                    .debug(
                        "📐 Dimension info - Terminal: \(currentCols)x\(currentRows), Buffer: \(adjustedSnapshot.cols)x\(adjustedSnapshot.rows)"
                    )
                // Don't resize here - let the UI-driven resize handle terminal dimensions
                // Just render the buffer content as-is
                // We'll force a full redraw below but NOT clear the screen
            }

            // Handle viewport scrolling - disabled when using windowing
            let viewportChanged = false // Viewport is now handled by windowing

            // Use incremental updates if possible
            let ansiData: String
            if isFirstUpdate || previousSnapshot == nil || viewportChanged || dimensionsMismatch {
                // Full redraw needed
                // Only clear screen on the very first update, not on dimension mismatches
                let wasFirstUpdate = isFirstUpdate
                ansiData = convertBufferToOptimizedANSI(adjustedSnapshot, clearScreen: isFirstUpdate)
                isFirstUpdate = false
                logger
                    .verbose(
                        "Full redraw performed (wasFirstUpdate: \(wasFirstUpdate), dimensionsMismatch: \(dimensionsMismatch))"
                    )
            } else if let previous = previousSnapshot {
                // Incremental update
                ansiData = generateIncrementalUpdate(from: previous, to: adjustedSnapshot)
                logger.verbose("Incremental update performed")
            } else {
                // Fallback to full redraw if somehow previousSnapshot is nil
                ansiData = convertBufferToOptimizedANSI(adjustedSnapshot, clearScreen: false)
                logger.verbose("Fallback full redraw performed")
            }

            // Store current snapshot for next update
            previousSnapshot = adjustedSnapshot

            // Feed the ANSI data to the terminal
            if !ansiData.isEmpty {
                // Log what we're about to send
                let preview = String(ansiData.prefix(200))
                logger.info("🔤 Sending ANSI data (\(ansiData.count) bytes): \(preview.debugDescription)")
                feedData(ansiData)
            } else {
                logger.warning("⚠️ No ANSI data to send - buffer may be empty")
            }

            // Log successful update
            logger.verbose("✅ Buffer update completed successfully")
        }

        /// Handle viewport scrolling
        private func handleViewportScroll(delta: Int, snapshot: BufferSnapshot) {
            guard terminal != nil else { return }

            // SwiftTerm handles scrolling internally, but we can optimize by
            // using scroll region commands if scrolling by small amounts
            if abs(delta) < 5 && abs(delta) > 0 {
                var scrollCommands = ""

                // Set scroll region to full screen
                scrollCommands += "\u{001B}[1;\(snapshot.rows)r"

                if delta > 0 {
                    // Scrolling down - content moves up
                    scrollCommands += "\u{001B}[\(delta)S"
                } else {
                    // Scrolling up - content moves down
                    scrollCommands += "\u{001B}[\(-delta)T"
                }

                // Reset scroll region
                scrollCommands += "\u{001B}[r"

                feedData(scrollCommands)
            }
        }

        private func convertBufferToOptimizedANSI(_ snapshot: BufferSnapshot, clearScreen: Bool = false) -> String {
            var output = ""

            if clearScreen {
                // Clear screen and reset cursor for first update
                output += "\u{001B}[2J\u{001B}[H"
            } else {
                // For non-first updates, just home the cursor without clearing
                // This allows us to overwrite content line by line
                output += "\u{001B}[H"
            }

            // Track current attributes to minimize escape sequences
            var currentFg: Int?
            var currentBg: Int?
            var currentAttrs: Int = 0

            // Render each row
            for (rowIndex, row) in snapshot.cells.enumerated() {
                // Don't use absolute positioning for each line - just use newlines
                if rowIndex > 0 {
                    output += "\r\n"
                }

                // Check if this is an empty row (marked by empty array or single empty cell)
                if row.isEmpty || (row.count == 1 && row[0].width == 0) {
                    // For empty rows, output a clear line to ensure no stale content
                    output += "\u{001B}[K"
                    continue
                }

                var lastNonSpaceIndex = -1
                for (index, cell) in row.enumerated() {
                    if cell.char != " " || cell.bg != nil {
                        lastNonSpaceIndex = index
                    }
                }

                // Only render up to the last non-space character
                var currentCol = 0
                for cell in row {
                    if currentCol > lastNonSpaceIndex && lastNonSpaceIndex >= 0 {
                        break
                    }

                    // Handle attributes efficiently
                    var needsReset = false
                    if let attrs = cell.attributes, attrs != currentAttrs {
                        needsReset = true
                        currentAttrs = attrs
                    }

                    // Handle colors efficiently
                    if cell.fg != currentFg || cell.bg != currentBg || needsReset {
                        if needsReset {
                            output += "\u{001B}[0m"
                            currentFg = nil
                            currentBg = nil

                            // Apply attributes
                            if let attrs = cell.attributes {
                                if (attrs & 0x01) != 0 { output += "\u{001B}[1m" } // Bold
                                if (attrs & 0x02) != 0 { output += "\u{001B}[3m" } // Italic
                                if (attrs & 0x04) != 0 { output += "\u{001B}[4m" } // Underline
                                if (attrs & 0x08) != 0 { output += "\u{001B}[2m" } // Dim
                                if (attrs & 0x10) != 0 { output += "\u{001B}[7m" } // Inverse
                                if (attrs & 0x40) != 0 { output += "\u{001B}[9m" } // Strikethrough
                            }
                        }

                        // Apply foreground color
                        if cell.fg != currentFg {
                            currentFg = cell.fg
                            if let fg = cell.fg {
                                if fg & 0xFF00_0000 != 0 {
                                    // RGB color
                                    let red = (fg >> 16) & 0xFF
                                    let green = (fg >> 8) & 0xFF
                                    let blue = fg & 0xFF
                                    output += "\u{001B}[38;2;\(red);\(green);\(blue)m"
                                } else if fg <= 255 {
                                    // Palette color
                                    output += "\u{001B}[38;5;\(fg)m"
                                }
                            } else {
                                output += "\u{001B}[39m"
                            }
                        }

                        // Apply background color
                        if cell.bg != currentBg {
                            currentBg = cell.bg
                            if let bg = cell.bg {
                                if bg & 0xFF00_0000 != 0 {
                                    // RGB color
                                    let red = (bg >> 16) & 0xFF
                                    let green = (bg >> 8) & 0xFF
                                    let blue = bg & 0xFF
                                    output += "\u{001B}[48;2;\(red);\(green);\(blue)m"
                                } else if bg <= 255 {
                                    // Palette color
                                    output += "\u{001B}[48;5;\(bg)m"
                                }
                            } else {
                                output += "\u{001B}[49m"
                            }
                        }
                    }

                    // Add the character
                    output += cell.char
                    currentCol += cell.width
                }
            }

            // Don't clear remaining rows - the buffer should handle its own viewport
            // The server sends the visible area, and we shouldn't assume what's below

            // Reset attributes
            output += "\u{001B}[0m"

            // Position cursor (ensure it's within actual buffer bounds)
            // The cursor should be positioned within the buffer area, not beyond it
            let maxRow = max(1, snapshot.rows) // Ensure at least row 1
            let cursorRow = max(1, min(snapshot.cursorY + 1, maxRow))
            let cursorCol = max(1, snapshot.cursorX + 1)

            output += "\u{001B}[\(cursorRow);\(cursorCol)H"

            return output
        }

        /// Generate incremental ANSI updates by comparing previous and current snapshots
        private func generateIncrementalUpdate(
            from oldSnapshot: BufferSnapshot,
            to newSnapshot: BufferSnapshot
        )
            -> String
        {
            var output = ""
            var currentFg: Int?
            var currentBg: Int?
            var currentAttrs: Int = 0

            // Update cursor if changed
            let cursorChanged = oldSnapshot.cursorX != newSnapshot.cursorX || oldSnapshot.cursorY != newSnapshot.cursorY

            // Check each row for changes
            for rowIndex in 0..<min(newSnapshot.cells.count, oldSnapshot.cells.count) {
                let oldRow = rowIndex < oldSnapshot.cells.count ? oldSnapshot.cells[rowIndex] : []
                let newRow = rowIndex < newSnapshot.cells.count ? newSnapshot.cells[rowIndex] : []

                // Quick check if rows are identical
                if rowsAreIdentical(oldRow, newRow) {
                    continue
                }

                // Handle empty rows efficiently
                let oldIsEmpty = oldRow.isEmpty || (oldRow.count == 1 && oldRow[0].width == 0)
                let newIsEmpty = newRow.isEmpty || (newRow.count == 1 && newRow[0].width == 0)

                if oldIsEmpty && newIsEmpty {
                    continue // Both empty, no change
                } else if !oldIsEmpty && newIsEmpty {
                    // Row became empty - clear it
                    output += "\u{001B}[\(rowIndex + 1);1H\u{001B}[2K"
                    continue
                } else if oldIsEmpty && !newIsEmpty {
                    // Empty row now has content - render full row
                    output += "\u{001B}[\(rowIndex + 1);1H"
                    for cell in newRow {
                        updateColorIfNeeded(&output, &currentFg, cell.fg, isBackground: false)
                        updateColorIfNeeded(&output, &currentBg, cell.bg, isBackground: true)
                        output += cell.char
                    }
                    continue
                }

                // Find changed segments in this row
                var segments: [(start: Int, end: Int)] = []
                var currentSegmentStart = -1

                let maxCells = max(oldRow.count, newRow.count)
                for colIndex in 0..<maxCells {
                    let oldCell = colIndex < oldRow.count ? oldRow[colIndex] : nil
                    let newCell = colIndex < newRow.count ? newRow[colIndex] : nil

                    if !cellsAreIdentical(oldCell, newCell) {
                        if currentSegmentStart == -1 {
                            currentSegmentStart = colIndex
                        }
                    } else if currentSegmentStart >= 0 {
                        // End of changed segment
                        segments.append((start: currentSegmentStart, end: colIndex - 1))
                        currentSegmentStart = -1
                    }
                }

                // Handle last segment if it extends to end
                if currentSegmentStart >= 0 {
                    segments.append((start: currentSegmentStart, end: maxCells - 1))
                }

                // Render each changed segment
                for segment in segments {
                    // Move cursor to start of segment
                    var colPosition = 0
                    for i in 0..<segment.start where i < newRow.count {
                        colPosition += newRow[i].width
                    }
                    output += "\u{001B}[\(rowIndex + 1);\(colPosition + 1)H"

                    // Render cells in segment
                    for colIndex in segment.start...segment.end {
                        guard colIndex < newRow.count else {
                            // Clear remaining cells if old row was longer
                            output += "\u{001B}[K"
                            break
                        }
                        let cell = newRow[colIndex]

                        // Handle attributes
                        var needsReset = false
                        if let attrs = cell.attributes, attrs != currentAttrs {
                            needsReset = true
                            currentAttrs = attrs
                        }

                        // Apply styles if changed
                        if cell.fg != currentFg || cell.bg != currentBg || needsReset {
                            if needsReset {
                                output += "\u{001B}[0m"
                                currentFg = nil
                                currentBg = nil

                                // Apply attributes
                                if let attrs = cell.attributes {
                                    if (attrs & 0x01) != 0 { output += "\u{001B}[1m" }
                                    if (attrs & 0x02) != 0 { output += "\u{001B}[3m" }
                                    if (attrs & 0x04) != 0 { output += "\u{001B}[4m" }
                                    if (attrs & 0x08) != 0 { output += "\u{001B}[2m" }
                                    if (attrs & 0x10) != 0 { output += "\u{001B}[7m" }
                                    if (attrs & 0x40) != 0 { output += "\u{001B}[9m" }
                                }
                            }

                            // Apply colors
                            updateColorIfNeeded(&output, &currentFg, cell.fg, isBackground: false)
                            updateColorIfNeeded(&output, &currentBg, cell.bg, isBackground: true)
                        }

                        output += cell.char
                    }
                }
            }

            // Handle newly added rows
            if newSnapshot.cells.count > oldSnapshot.cells.count {
                for rowIndex in oldSnapshot.cells.count..<newSnapshot.cells.count {
                    output += "\u{001B}[\(rowIndex + 1);1H"
                    output += "\u{001B}[2K" // Clear line

                    let row = newSnapshot.cells[rowIndex]
                    for cell in row {
                        // Apply styles
                        updateColorIfNeeded(&output, &currentFg, cell.fg, isBackground: false)
                        updateColorIfNeeded(&output, &currentBg, cell.bg, isBackground: true)
                        output += cell.char
                    }
                }
            }

            // Update cursor position if changed
            if cursorChanged {
                // Ensure cursor is within bounds
                let maxRow = max(1, newSnapshot.rows)
                let cursorRow = max(1, min(newSnapshot.cursorY + 1, maxRow))
                let cursorCol = max(1, newSnapshot.cursorX + 1)
                output += "\u{001B}[\(cursorRow);\(cursorCol)H"
            }

            return output
        }

        private func rowsAreIdentical(_ row1: [BufferCell], _ row2: [BufferCell]) -> Bool {
            guard row1.count == row2.count else { return false }

            for i in 0..<row1.count where !cellsAreIdentical(row1[i], row2[i]) {
                return false
            }
            return true
        }

        private func cellsAreIdentical(_ cell1: BufferCell?, _ cell2: BufferCell?) -> Bool {
            guard let cell1, let cell2 else {
                return cell1 == nil && cell2 == nil
            }

            return cell1.char == cell2.char &&
                cell1.fg == cell2.fg &&
                cell1.bg == cell2.bg &&
                cell1.attributes == cell2.attributes
        }

        private func updateColorIfNeeded(
            _ output: inout String,
            _ current: inout Int?,
            _ new: Int?,
            isBackground: Bool
        ) {
            if new != current {
                current = new
                if let color = new {
                    if color & 0xFF00_0000 != 0 {
                        // RGB color
                        let red = (color >> 16) & 0xFF
                        let green = (color >> 8) & 0xFF
                        let blue = color & 0xFF
                        output += "\u{001B}[\(isBackground ? 48 : 38);2;\(red);\(green);\(blue)m"
                    } else if color <= 255 {
                        // Palette color
                        output += "\u{001B}[\(isBackground ? 48 : 38);5;\(color)m"
                    }
                } else {
                    // Default color
                    output += "\u{001B}[\(isBackground ? 49 : 39)m"
                }
            }
        }

        func feedData(_ data: String) {
            Task { @MainActor in
                guard let terminal else {
                    logger.warning("❌ feedData: No terminal instance available")
                    return
                }

                // Check if this looks like initial content
                let hasVisibleContent = data.contains { char in
                    !char.isWhitespace && !char.isNewline && char != "\u{001B}"
                }

                if hasVisibleContent && isFirstUpdate {
                    isFirstUpdate = false
                }

                // Enhanced logging
                let preview = String(data.prefix(200))
                if hasVisibleContent {
                    logger.info("   Preview: \(preview.debugDescription)")
                }

                // Store current scroll position before feeding data
                let wasAtBottom = viewModel.isAutoScrollEnabled

                // Feed the output to the terminal
                terminal.feed(text: data)

                // Simplified display refresh - let SwiftTerm handle most of the work
                terminal.setNeedsDisplay()

                // Only use the display link for critical updates
                if hasVisibleContent {
                    // self.startShortDisplayRefresh()  // TEMPORARILY DISABLED FOR TESTING                             
                    //   │ │
                }

                // Log what the terminal shows after feeding
                let terminalContent = getBufferContent() ?? "<empty>"
                let lines = terminalContent.split(separator: "\n", maxSplits: 5, omittingEmptySubsequences: false)
                for (index, line) in lines.prefix(5).enumerated() {
                    logger.info("   Line \(index): \(String(line).prefix(80))")
                }

                // Auto-scroll to bottom if enabled
                if wasAtBottom {
                    // SwiftTerm automatically scrolls when feeding data at bottom
                    // No explicit API needed for auto-scrolling
                }
            }
        }

        private func startShortDisplayRefresh() {
            // Refresh for ~10 frames to ensure paints commit
            displayLink?.invalidate()
            displayLinkFramesRemaining = 10

            let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
            link.add(to: .main, forMode: .common)
            displayLink = link
            logger.debug("🪄 Started short display refresh link")
        }

        @objc private func handleDisplayLink() {
            guard let terminal else { return }
            terminal.setNeedsDisplay()
            terminal.layer.setNeedsDisplay()
            CATransaction.flush()

            displayLinkFramesRemaining -= 1
            if displayLinkFramesRemaining <= 0 {
                displayLink?.invalidate()
                displayLink = nil
                logger.debug("🪄 Stopped short display refresh link")
            }
        }

        func getBufferContent() -> String? {
            guard let terminal else { return nil }

            // Get the terminal buffer content
            let terminalInstance = terminal.getTerminal()
            var content = ""
            var nonEmptyLines = 0

            // Read all lines from the terminal buffer
            for row in 0..<min(10, terminalInstance.rows) { // Only check first 10 lines for debugging
                if let line = terminalInstance.getLine(row: row) {
                    var lineText = ""
                    for col in 0..<terminalInstance.cols where col < line.count {
                        let char = line[col]
                        lineText += String(char.getCharacter())
                    }
                    let trimmed = lineText.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        nonEmptyLines += 1
                        logger.verbose("Row \(row): '\(trimmed.prefix(50))'")
                    }
                    // Don't trim for content - preserve exact spacing
                    content += lineText + "\n"
                }
            }

            logger
                .info("📄 Buffer content check: \(nonEmptyLines) non-empty lines out of \(terminalInstance.rows) total")

            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // MARK: - TerminalViewDelegate

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            if let string = String(bytes: data, encoding: .utf8) {
                onInput(string)
            }
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            // Ignore obviously invalid/ephemeral sizes during layout churn
            guard newCols >= 10, newRows >= 5 else {
                return
            }

            // Only notify if dimensions actually changed
            if newCols != viewModel.terminalCols || newRows != viewModel.terminalRows {
                onResize(newCols, newRows)
            } else {
                logger.debug("   Skipping resize callback - dimensions unchanged")
            }
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {
            // Check if user is at bottom
            Task { @MainActor in
                // Estimate if at bottom based on position
                let isAtBottom = position >= 0.95
                viewModel.updateScrollState(isAtBottom: isAtBottom)

                // The view model will handle button visibility through its state
            }
        }

        func scrollToBottom() {
            // Scroll to bottom by sending page down keys
            if let terminal {
                terminal.feed(text: "\u{001b}[B")
            }
        }

        func setMaxWidth(_ maxWidth: Int) {
            // Store the max width preference for terminal rendering
            // When maxWidth is 0, it means unlimited
            // This could be used to constrain terminal rendering in the future
            // For now, just log the preference
            logger.info("Max width set to: \(maxWidth == 0 ? "unlimited" : "\(maxWidth) columns")")
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
            // Handle title change if needed
        }

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            // Handle directory update if needed
        }

        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            // Open URL with haptic feedback
            if let url = URL(string: link) {
                DispatchQueue.main.async {
                    HapticFeedback.impact(.light)
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            // Handle clipboard copy with improved selection support
            if let string = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = string

                // Provide haptic feedback
                HapticFeedback.notification(.success)

                // If we have buffer data, we can provide additional context
                if previousSnapshot != nil {
                    // Log selection range for debugging
                    logger.debug("Copied \(string.count) characters")
                }
            }
        }

        /// Get selected text from buffer with proper Unicode handling
        func getSelectedText() -> String? {
            guard let start = selectionStart,
                  let end = selectionEnd,
                  let snapshot = previousSnapshot
            else {
                return nil
            }

            var selectedText = ""

            // Normalize selection coordinates
            let startY = min(start.y, end.y)
            let endY = max(start.y, end.y)
            let startX = start.y < end.y ? start.x : min(start.x, end.x)
            let endX = start.y < end.y ? max(start.x, end.x) : end.x

            // Extract text from buffer
            for y in startY...endY {
                guard y < snapshot.cells.count else { continue }
                let row = snapshot.cells[y]

                var rowText = ""
                var currentX = 0

                for cell in row {
                    let cellStartX = currentX
                    let cellEndX = currentX + cell.width

                    // Check if cell is within selection
                    if y == startY && y == endY {
                        // Single line selection
                        if cellEndX > startX && cellStartX < endX {
                            rowText += cell.char
                        }
                    } else if y == startY {
                        // First line of multi-line selection
                        if cellStartX >= startX {
                            rowText += cell.char
                        }
                    } else if y == endY {
                        // Last line of multi-line selection
                        if cellEndX <= endX {
                            rowText += cell.char
                        }
                    } else {
                        // Middle lines - include everything
                        rowText += cell.char
                    }

                    currentX = cellEndX
                }

                // Add line to result
                if !rowText.isEmpty {
                    if !selectedText.isEmpty {
                        selectedText += "\n"
                    }
                    selectedText += rowText.trimmingCharacters(in: .whitespaces)
                }
            }

            return selectedText.isEmpty ? nil : selectedText
        }

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
            // Handle range change if needed
        }
    }
}

/// Add conformance with proper isolation
extension TerminalHostingView.Coordinator: @preconcurrency SwiftTerm.TerminalViewDelegate {}

// MARK: - UIColor Extension for SwiftTerm

extension UIColor {
    /// Convert UIColor to SwiftTerm.Color (which uses 16-bit color components)
    func toSwiftTermColor() -> SwiftTerm.Color {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        // Convert from 0.0-1.0 range to 0-65535 range
        let red16 = UInt16(red * 65_535.0)
        let green16 = UInt16(green * 65_535.0)
        let blue16 = UInt16(blue * 65_535.0)

        return SwiftTerm.Color(red: red16, green: green16, blue: blue16)
    }
}
