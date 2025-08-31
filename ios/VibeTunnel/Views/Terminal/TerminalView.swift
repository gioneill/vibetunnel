import Observation
import SwiftTerm
import SwiftUI

private let logger = Logger(category: "TerminalView")

/// Interactive terminal view for a session.
///
/// Displays a full terminal emulator using SwiftTerm with support for
/// input, output, recording, and font size adjustment.
struct TerminalView: View {
    let session: Session
    @Environment(\.dismiss)
    var dismiss
    @State private var viewModel: TerminalViewModel
    @State private var fontSize: CGFloat = 14
    @State private var showingFontSizeSheet = false
    @State private var showingRecordingSheet = false
    @State private var showingTerminalWidthSheet = false
    @State private var showingTerminalThemeSheet = false
    @State private var selectedTerminalWidth: Int?
    @State private var selectedTheme = TerminalTheme.selected
    @State private var keyboardHeight: CGFloat = 0
    @State private var showScrollToBottom = false
    @State private var showingFileBrowser = false
    @State private var selectedRenderer = TerminalRenderer.selected
    @State private var showingDebugMenu = false
    @State private var showingExportSheet = false
    @State private var exportedFileURL: URL?
    @State private var showingWidthSelector = false
    @State private var currentTerminalWidth: TerminalWidth = .unlimited
    @State private var showingFullscreenInput = false
    @State private var showingCtrlKeyGrid = false
    @FocusState private var isInputFocused: Bool

    init(session: Session) {
        self.session = session
        self._viewModel = State(initialValue: TerminalViewModel(session: session, renderer: TerminalRenderer.selected))
    }

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle(session.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .bottomBar)
                .toolbarBackground(.automatic, for: .bottomBar)
                .toolbar {
                    navigationToolbarItems
                    bottomToolbarItems
                    recordingIndicator
                }
        }
        .focusable()
        .onAppear {
            // Choose connection strategy per renderer
            switch selectedRenderer {
            case .swiftTerm:
                viewModel.connectSSE()
            case .xterm:
                viewModel.connectWebSocket()
            }
            isInputFocused = true

            // Load saved terminal width preference
            let savedWidth = TerminalWidthManager.shared.defaultWidth
            if savedWidth > 0 {
                currentTerminalWidth = TerminalWidth.from(value: savedWidth)
                selectedTerminalWidth = savedWidth
                viewModel.resize(cols: savedWidth, rows: max(viewModel.terminalRows, 24))
                logger.info("📐 Restored saved terminal width: \(savedWidth)")
            } else {
                // Default to unlimited if no saved preference
                currentTerminalWidth = .unlimited
                selectedTerminalWidth = nil
                // For unlimited, calculate optimal width
                let screenWidth = UIScreen.main.bounds.width
                let padding: CGFloat = 32
                let charWidth: CGFloat = 9
                let optimalCols = Int((screenWidth - padding) / charWidth)
                viewModel.resize(cols: max(optimalCols, 80), rows: max(viewModel.terminalRows, 24))
                logger.info("📐 No saved width, using unlimited with optimal cols: \(optimalCols)")
            }
        }
        .onDisappear {
            viewModel.disconnect()
        }
        .sheet(isPresented: $showingFontSizeSheet) {
            FontSizeSheet(fontSize: $fontSize)
        }
        .sheet(isPresented: $showingRecordingSheet) {
            RecordingExportSheet(recorder: viewModel.castRecorder, sessionName: session.displayName)
        }
        .sheet(isPresented: $showingTerminalWidthSheet) {
            TerminalWidthSheet(
                selectedWidth: $selectedTerminalWidth,
                isResizeBlockedByServer: viewModel.isResizeBlockedByServer
            )
            .onAppear {
                selectedTerminalWidth = viewModel.terminalCols
            }
        }
        .sheet(isPresented: $showingTerminalThemeSheet) {
            TerminalThemeSheet(selectedTheme: $selectedTheme)
        }
        .sheet(isPresented: $showingFileBrowser) {
            FileBrowserView(
                initialPath: session.workingDir,
                mode: .insertPath,
                onSelect: { _ in
                    showingFileBrowser = false
                },
                onInsertPath: { [weak viewModel] path, _ in
                    // Insert the path into the terminal
                    viewModel?.sendInput(path)
                    showingFileBrowser = false
                }
            )
        }
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showingFullscreenInput) {
            FullscreenTextInput(isPresented: $showingFullscreenInput) { [weak viewModel] text in
                viewModel?.sendInput(text)
            }
        }
        .sheet(isPresented: $showingCtrlKeyGrid) {
            CtrlKeyGrid(isPresented: $showingCtrlKeyGrid) { [weak viewModel] controlChar in
                viewModel?.sendInput(controlChar)
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.startLocation.x < 20 && value.translation.width > 50 {
                        dismiss()
                        HapticFeedback.impact(.light)
                    }
                }
        )
        .task {
            for await notification in NotificationCenter.default
                .notifications(named: UIResponder.keyboardWillShowNotification)
            {
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(Theme.Animation.standard) {
                        keyboardHeight = keyboardFrame.height
                    }
                }
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillHideNotification) {
                withAnimation(Theme.Animation.standard) {
                    keyboardHeight = 0
                }
            }
        }
        .onChange(of: selectedTerminalWidth) { _, newValue in
            if let width = newValue {
                // Explicit width selected
                if width != viewModel.terminalCols {
                    logger.info("📐 Width preference changed to \(width), keeping height at \(viewModel.terminalRows)")
                    viewModel.resize(cols: width, rows: max(viewModel.terminalRows, 24))
                }
            } else {
                // Infinite width selected (nil)
                let screenWidth = UIScreen.main.bounds.width
                let padding: CGFloat = 32
                let charWidth: CGFloat = 9
                let optimalCols = Int((screenWidth - padding) / charWidth)

                if optimalCols != viewModel.terminalCols {
                    logger
                        .info(
                            "📐 Infinite width selected, using optimal cols: \(optimalCols), keeping height at \(viewModel.terminalRows)"
                        )
                    viewModel.resize(cols: max(optimalCols, 80), rows: max(viewModel.terminalRows, 24))
                }
            }
        }
        .onChange(of: currentTerminalWidth) { _, newWidth in
            let targetWidth = newWidth.value == 0 ? nil : newWidth.value
            if targetWidth != selectedTerminalWidth {
                selectedTerminalWidth = targetWidth
                // Width is already handled by onChange(of: selectedTerminalWidth)
                TerminalWidthManager.shared.defaultWidth = newWidth.value
            }
        }
        .onChange(of: viewModel.isAtBottom) { _, newValue in
            withAnimation(Theme.Animation.smooth) {
                showScrollToBottom = !newValue
            }
        }
        // iPad keyboard shortcuts
        .onKeyPress(keys: ["o"]) { press in
            if press.modifiers.contains(.command) && session.isRunning {
                showingFileBrowser = true
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: ["+"]) { press in
            if press.modifiers.contains(.command) {
                // Increase font size
                withAnimation(Theme.Animation.quick) {
                    fontSize = min(fontSize + 2, 30)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: ["-"]) { press in
            if press.modifiers.contains(.command) {
                // Decrease font size
                withAnimation(Theme.Animation.quick) {
                    fontSize = max(fontSize - 2, 8)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: ["t"]) { press in
            if press.modifiers.contains(.command) {
                // Toggle theme
                let themes = TerminalTheme.allThemes
                if let currentIndex = themes.firstIndex(where: { $0.id == selectedTheme.id }) {
                    let nextIndex = (currentIndex + 1) % themes.count
                    selectedTheme = themes[nextIndex]
                    TerminalTheme.selected = selectedTheme
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: ["k"]) { press in
            if press.modifiers.contains(.command) {
                // Clear terminal
                viewModel.sendSpecialKey(.ctrlL)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: ["c"]) { press in
            if press.modifiers.contains(.command) && !press.modifiers.contains(.shift) {
                // Copy to clipboard
                if let content = viewModel.getBufferContent() {
                    UIPasteboard.general.string = content
                    HapticFeedback.notification(.success)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: ["r"]) { press in
            if press.modifiers.contains(.command) {
                // Start/stop recording
                if viewModel.castRecorder.isRecording {
                    viewModel.stopRecording()
                } else {
                    viewModel.startRecording()
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: ["w"]) { press in
            if press.modifiers.contains(.command) {
                // Change terminal width
                showingTerminalWidthSheet = true
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: ["d"]) { press in
            if press.modifiers.contains(.command) {
                // Toggle debug menu
                showingDebugMenu.toggle()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: [.escape]) { _ in
            // Send escape key to terminal
            viewModel.sendSpecialKey(.escape)
            return .handled
        }
        .onKeyPress(keys: [.tab]) { _ in
            // Send tab key to terminal
            viewModel.sendSpecialKey(.tab)
            return .handled
        }
        .sheet(isPresented: $showingExportSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
                    .onDisappear {
                        // Clean up temporary file
                        try? FileManager.default.removeItem(at: url)
                        exportedFileURL = nil
                    }
            }
        }
    }

    // MARK: - Export Functions

    private func exportTerminalBuffer() {
        guard let bufferContent = viewModel.getBufferContent() else { return }

        let fileName = "\(session.displayName)_\(Date().timeIntervalSince1970).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try bufferContent.write(to: tempURL, atomically: true, encoding: .utf8)
            exportedFileURL = tempURL
            showingExportSheet = true
        } catch {
            logger.error("Failed to export terminal buffer: \(error)")
        }
    }

    // MARK: - View Components

    private var mainContent: some View {
        ZStack {
            selectedTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if viewModel.isConnecting {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    terminalContent
                }
            }
        }
    }

    private var navigationToolbarItems: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") {
                    dismiss()
                }
                .foregroundColor(Theme.Colors.primaryAccent)
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                fileBrowserButton
                widthSelectorButton
                menuButton
            }
        }
    }

    private var bottomToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            terminalSizeIndicator
            Spacer()
        }
    }

    private var recordingIndicator: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if viewModel.castRecorder.isRecording {
                recordingView
            }
        }
    }

    // MARK: - Toolbar Components

    private var fileBrowserButton: some View {
        Button(action: {
            HapticFeedback.impact(.light)
            showingFileBrowser = true
        }, label: {
            Image(systemName: "folder")
                .font(.system(size: 16))
                .foregroundColor(Theme.Colors.primaryAccent)
        })
    }

    private var widthSelectorButton: some View {
        Button(action: { showingWidthSelector = true }, label: {
            HStack(spacing: 2) {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 12))
                Text(currentTerminalWidth.label)
                    .font(Theme.Typography.terminalSystem(size: 14))
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
            )
        })
        .foregroundColor(Theme.Colors.primaryAccent)
        .popover(isPresented: $showingWidthSelector, arrowEdge: .top) {
            WidthSelectorPopover(
                currentWidth: $currentTerminalWidth,
                isPresented: $showingWidthSelector
            )
        }
    }

    private var menuButton: some View {
        Menu {
            terminalMenuItems
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(Theme.Colors.primaryAccent)
        }
    }

    @ViewBuilder private var terminalMenuItems: some View {
        Button(action: { viewModel.clearTerminal() }, label: {
            Label("Clear", systemImage: "clear")
        })

        Button(action: { showingFullscreenInput = true }, label: {
            Label("Compose Command", systemImage: "text.viewfinder")
        })

        Button(action: { showingCtrlKeyGrid = true }, label: {
            Label("Ctrl Shortcuts", systemImage: "command.square")
        })

        Divider()

        Menu {
            Button(action: {
                fontSize = max(8, fontSize - 1)
                HapticFeedback.impact(.light)
            }, label: {
                Label("Decrease", systemImage: "minus")
            })
            .disabled(fontSize <= 8)

            Button(action: {
                fontSize = min(32, fontSize + 1)
                HapticFeedback.impact(.light)
            }, label: {
                Label("Increase", systemImage: "plus")
            })
            .disabled(fontSize >= 32)

            Button(action: {
                fontSize = 14
                HapticFeedback.impact(.light)
            }, label: {
                Label("Reset to Default", systemImage: "arrow.counterclockwise")
            })
            .disabled(fontSize == 14)

            Divider()

            Button(action: { showingFontSizeSheet = true }, label: {
                Label("More Options...", systemImage: "slider.horizontal.3")
            })
        } label: {
            Label("Font Size (\(Int(fontSize))pt)", systemImage: "textformat.size")
        }

        Button(action: { showingTerminalWidthSheet = true }, label: {
            Label("Terminal Width", systemImage: "arrow.left.and.right")
        })

        Button(action: { viewModel.toggleFitToWidth() }, label: {
            Label(
                viewModel.fitToWidth ? "Fixed Width" : "Fit to Width",
                systemImage: viewModel.fitToWidth ? "arrow.left.and.right.square" : "arrow.left.and.right.square.fill"
            )
        })

        Button(action: { showingTerminalThemeSheet = true }, label: {
            Label("Theme", systemImage: "paintbrush")
        })

        Button(action: { viewModel.copyBuffer() }, label: {
            Label("Copy All", systemImage: "square.on.square")
        })

        Button(action: { exportTerminalBuffer() }, label: {
            Label("Export as Text", systemImage: "square.and.arrow.up")
        })

        Divider()

        recordingMenuItems

        Divider()

        debugMenuItems
    }

    @ViewBuilder private var recordingMenuItems: some View {
        if viewModel.castRecorder.isRecording {
            Button(action: {
                viewModel.stopRecording()
                showingRecordingSheet = true
            }, label: {
                Label("Stop Recording", systemImage: "stop.circle.fill")
                    .foregroundColor(.red)
            })
        } else {
            Button(action: { viewModel.startRecording() }, label: {
                Label("Start Recording", systemImage: "record.circle")
            })
        }

        Button(action: { showingRecordingSheet = true }, label: {
            Label("Export Recording", systemImage: "square.and.arrow.up")
        })
        .disabled(viewModel.castRecorder.events.isEmpty)
    }

    @ViewBuilder private var debugMenuItems: some View {
        Menu {
            ForEach(TerminalRenderer.allCases, id: \.self) { renderer in
                Button(action: {
                    selectedRenderer = renderer
                    TerminalRenderer.selected = renderer
                    // Recreate view model for clean switch
                    viewModel.disconnect()
                    viewModel = TerminalViewModel(session: session, renderer: renderer)
                    viewModel.connect()
                }, label: {
                    HStack {
                        Text(renderer.displayName)
                        if renderer == selectedRenderer {
                            Image(systemName: "checkmark")
                        }
                    }
                })
            }
        } label: {
            Label("Terminal Renderer", systemImage: "gearshape.2")
        }
    }

    @ViewBuilder private var terminalSizeIndicator: some View {
        if viewModel.terminalCols > 0 && viewModel.terminalRows > 0 {
            Text("\(viewModel.terminalCols)×\(viewModel.terminalRows)")
                .font(Theme.Typography.terminalSystem(size: 11))
                .foregroundColor(Theme.Colors.terminalForeground.opacity(0.5))
        }
    }

    private var recordingView: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.Colors.errorAccent)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .fill(Theme.Colors.errorAccent.opacity(0.3))
                        .frame(width: 16, height: 16)
                        .scaleEffect(viewModel.recordingPulse ? 1.5 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: viewModel.recordingPulse
                        )
                )
            Text("REC")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.Colors.errorAccent)
        }
        .onAppear {
            viewModel.recordingPulse = true
        }
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.large) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.primaryAccent))
                .scaleEffect(1.5)

            Text("Connecting to session...")
                .font(Theme.Typography.terminalSystem(size: 14))
                .foregroundColor(Theme.Colors.terminalForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.errorAccent)

            Text("Connection Error")
                .font(.headline)
                .foregroundColor(Theme.Colors.terminalForeground)

            Text(error)
                .font(Theme.Typography.terminalSystem(size: 12))
                .foregroundColor(Theme.Colors.terminalForeground.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                viewModel.connect()
            }
            .terminalButton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var terminalContent: some View {
        VStack(spacing: 0) {
            // Terminal view based on selected renderer
            Group {
                switch selectedRenderer {
                case .swiftTerm:
                    SwiftTermHostingView(viewModel: viewModel)
                case .xterm:
                    XtermWebView(
                        session: session,
                        fontSize: $fontSize,
                        theme: selectedTheme,
                        onInput: { text in
                            viewModel.sendInput(text)
                        },
                        onResize: { cols, rows in
                            viewModel.resize(cols: cols, rows: rows)
                        },
                        viewModel: viewModel
                    )
                }
            }
            .id(viewModel.terminalViewId)
            .background(selectedTheme.background)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .focused($isInputFocused)
            .overlay(
                ScrollToBottomButton(
                    isVisible: showScrollToBottom
                ) {
                    viewModel.scrollToBottom()
                    showScrollToBottom = false
                }
                .padding(.bottom, Theme.Spacing.large)
                .padding(.leading, Theme.Spacing.large),
                alignment: .bottomLeading
            )

            // Keyboard toolbar
            if keyboardHeight > 0 {
                TerminalToolbar(
                    onSpecialKey: { key in
                        viewModel.sendInput(key.rawValue)
                    },
                    onDismissKeyboard: {
                        isInputFocused = false
                    },
                    onRawInput: { input in
                        viewModel.sendInput(input)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

/// View model for terminal session management.
/// View model for terminal session management.
/// Handles terminal I/O, recording, state management, and WebSocket communication.
@MainActor
@Observable
class TerminalViewModel {
    var isConnecting = true
    var isConnected = false
    var hasReceivedData = false
    var errorMessage: String?
    var terminalViewId = UUID()
    var terminalCols: Int = 0
    var terminalRows: Int = 0
    var isAutoScrollEnabled = true
    var recordingPulse = false
    var isResizeBlockedByServer = false
    var isAtBottom = true
    var fitToWidth = false

    private var sseBootstrapped = false

    // WebSocket client is managed internally via shared instance
    
    
    /// Callback for raw ANSI updates (clean renderer)
    var onRawANSIUpdate: ((String) -> Void)?
    
    // Seeding state for clean renderer
    private var isSeeding = false
    private var bufferedSSEChunks: [String] = []

    // Track theme changes
    var themeChanged = false
    var selectedTheme: TerminalTheme?
    var shouldBecomeFirstResponder = false

    let session: Session
    let castRecorder: CastRecorder
    let renderer: TerminalRenderer
    private var sseClient: SSEClient?
    private let bufferWebSocketClient = BufferWebSocketClient.shared
    private var resizeDebounceTask: Task<Void, Never>?
    private var hasPerformedInitialResize = false
    private var isPerformingInitialResize = false

    init(session: Session, renderer: TerminalRenderer = .selected) {
        self.session = session
        self.renderer = renderer
        self.castRecorder = CastRecorder(sessionId: session.id, width: 80, height: 24)
        setupTerminal()
    }

    private func setupTerminal() {
        // Terminal setup now handled by SimpleTerminalView
    }

    func startRecording() {
        castRecorder.startRecording()
    }

    func stopRecording() {
        castRecorder.stopRecording()
    }

    func connect() {
        logger.info("Launching terminal for session: \(session.id) with renderer: \(renderer.rawValue)")
        isConnecting = true
        errorMessage = nil

        switch renderer {
        case .swiftTerm:
            // Use SSE for native SwiftTerm renderer
            connectSSE()
        case .xterm:
            // Use WebSocket for xterm renderer
            connectWebSocket()
        }
    }

    func connectWebSocket() {
        // Attach auth from APIClient if available
        if let auth = APIClient.shared.authenticationService {
            bufferWebSocketClient.setAuthenticationService(auth)
        }
        // Subscribe to session updates
        bufferWebSocketClient.subscribe(to: session.id) { [weak self] event in
            Task { @MainActor in
                self?.handleWebSocketEvent(event)
            }
        }
        // Ensure socket connection is established
        bufferWebSocketClient.connect()
        logger.info("Starting WebSocket connection for session: \(session.id)")
    }
    
    func connectSSE() {
        // Ensure auth is set for BufferWebSocketClient (for seeding phase)
        if let auth = APIClient.shared.authenticationService {
            bufferWebSocketClient.setAuthenticationService(auth)
        }
        
        // Build SSE URL using APIClient (ensures correct base URL)
        guard let streamURL = APIClient.shared.streamURL(for: session.id) else {
            errorMessage = "Invalid SSE URL"
            return
        }

        // Pass authentication service from APIClient for proper token attachment
        sseClient = SSEClient(url: streamURL, authenticationService: APIClient.shared.authenticationService)
        
        // For SwiftTerm renderer, start seeding phase
        if renderer == .swiftTerm {
            isSeeding = true
            bufferedSSEChunks = []
            
            // Subscribe to /buffers for one-time seed
            bufferWebSocketClient.subscribe(to: session.id) { [weak self] update in
                guard let self = self else { return }
                
                // Only process if still seeding
                guard self.isSeeding else {
                    // Unsubscribe if we're no longer seeding
                    self.bufferWebSocketClient.unsubscribe(from: self.session.id)
                    return
                }
                
                switch update {
                case .bufferUpdate(let snapshot):
                    // For SwiftTerm renderer, we need raw ANSI not buffer snapshots
                    // Skip the buffer update during seeding
                    logger.debug("Received buffer update during seeding, skipping")
                    
                    // Clean up seeding state
                    self.completeSeeding()
                    
                default:
                    // For any other event during seeding, just log it
                    logger.debug("Received non-buffer event during seeding: \(update)")
                    break
                }
            }
            
            // Ensure socket connection is established for seeding
            bufferWebSocketClient.connect()
        }
        
        sseClient?.delegate = self
        sseClient?.start()

        // Keep isConnecting = true, connection status will be updated via delegate
        // when SSE actually connects (.connected event) or fails
        logger.info("Starting SSE connection to: \(streamURL)")
        
        // Add overall connection timeout - if SSE never opens, show error
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
            if isConnecting {
                logger.error("SSE connection timeout - never received HTTP 200")
                errorMessage = "Connection timeout - unable to connect to terminal session"
                isConnecting = false
                sseClient?.stop()
                sseClient = nil
            }
        }
    }


    func disconnect() {
        resizeDebounceTask?.cancel()
        
        // Clean up seeding state if still active
        if isSeeding {
            isSeeding = false
            bufferedSSEChunks.removeAll()
        }
        
        // Unsubscribe from buffers (handles both seeding and normal cases)
        bufferWebSocketClient.unsubscribe(from: session.id)
        
        // Stop SSE if active
        sseClient?.stop()
        sseClient = nil
        
        // Clear raw ANSI callback
        onRawANSIUpdate = nil
        
        isConnected = false
    }


    func sendInput(_ text: String) {
        Task {
            do {
                try await SessionService().sendInput(to: session.id, text: text)
            } catch {
                logger.error("Failed to send input: \(error)")
            }
        }
    }

    func sendSpecialKey(_ key: TerminalInput.SpecialKey) {
        sendInput(key.rawValue)
    }

    func resize(cols: Int, rows: Int) {
        // Guard against invalid dimensions
        guard cols > 0 && rows > 0 && cols <= 1_000 && rows <= 1_000 else {
            logger.warning("Ignoring invalid resize: \(cols)x\(rows)")
            return
        }

        // Guard against blocked resize
        guard !isResizeBlockedByServer else {
            logger.warning("Resize blocked by server, ignoring resize: \(cols)x\(rows)")
            return
        }

        // Handle initial resize with proper synchronization
        if !hasPerformedInitialResize && !isPerformingInitialResize {
            // Check if dimensions are different from what we already have
            // to prevent duplicate initial resizes with same dimensions
            if terminalCols == cols && terminalRows == rows {
                logger.debug("Skipping duplicate initial resize: \(cols)x\(rows)")
                return
            }

            isPerformingInitialResize = true

            // Always update UI dimensions immediately for consistency
            terminalCols = cols
            terminalRows = rows

            // Perform initial resize after a short delay to let layout settle
            resizeDebounceTask?.cancel()
            resizeDebounceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds for initial
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self?.isPerformingInitialResize = false
                    }
                    return
                }
                await self?.performInitialResize(cols: cols, rows: rows)
            }
            return
        }

        // For subsequent resizes, compare against current UI dimensions (not server dimensions)
        guard cols != terminalCols || rows != terminalRows else {
            return
        }

        // Only allow significant changes for subsequent resizes
        let colDiff = abs(cols - terminalCols)
        let rowDiff = abs(rows - terminalRows)

        // Only resize if there's a significant change (more than 5 cols/rows difference)
        guard colDiff > 5 || rowDiff > 5 else {
            logger.debug("Ignoring minor resize change: \(cols)x\(rows) (current: \(terminalCols)x\(terminalRows))")
            return
        }

        // Update UI dimensions immediately
        terminalCols = cols
        terminalRows = rows

        resizeDebounceTask?.cancel()
        resizeDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second for subsequent
            guard !Task.isCancelled else { return }
            await self?.performResize(cols: cols, rows: rows)
        }
    }

    private func performInitialResize(cols: Int, rows: Int) async {
        logger.info("Performing initial terminal resize: \(cols)x\(rows)")

        do {
            try await SessionService().resizeTerminal(sessionId: session.id, cols: cols, rows: rows)
            // If resize succeeded, mark initial resize as complete and clear any server blocks
            await MainActor.run {
                hasPerformedInitialResize = true
                isPerformingInitialResize = false
                isResizeBlockedByServer = false
            }
        } catch {
            logger.error("Failed initial terminal resize: \(error)")
            // Check if the error is specifically about resize being disabled
            if case APIError.resizeDisabledByServer = error {
                await MainActor.run {
                    hasPerformedInitialResize = true // Mark as done even if blocked to prevent retries
                    isPerformingInitialResize = false
                    isResizeBlockedByServer = true
                }
            } else {
                // For other errors, allow retry by clearing the in-progress flag but leaving hasPerformedInitialResize
                // false
                await MainActor.run {
                    isPerformingInitialResize = false
                }
            }
        }
    }

    private func performResize(cols: Int, rows: Int) async {
        logger.info("Resizing terminal: \(cols)x\(rows)")

        do {
            try await SessionService().resizeTerminal(sessionId: session.id, cols: cols, rows: rows)
            // If resize succeeded, ensure the flag is cleared
            await MainActor.run {
                isResizeBlockedByServer = false
            }
        } catch {
            logger.error("Failed to resize terminal: \(error)")
            // Check if the error is specifically about resize being disabled
            if case APIError.resizeDisabledByServer = error {
                await MainActor.run {
                    isResizeBlockedByServer = true
                }
            }
            // Note: UI dimensions remain as set, representing the actual terminal view size
        }
    }

    func clearTerminal() {
        // Reset the terminal by recreating it
        terminalViewId = UUID()
        HapticFeedback.impact(.medium)
    }

    func copyBuffer() {
        // Terminal copy is handled by SwiftTerm's built-in functionality
        HapticFeedback.notification(.success)
    }

    func getBufferContent() -> String? {
        // Terminal buffer content access not available in simplified version
        return nil
    }

    @MainActor
    private func handleTerminalBell() {
        // Haptic feedback for bell
        HapticFeedback.notification(.warning)

        // Visual bell - flash the terminal briefly
        withAnimation(.easeInOut(duration: 0.1)) {
            // SwiftTerm handles visual bell internally
            // but we can add additional feedback if needed
        }
    }

    @MainActor
    private func handleTerminalAlert(title: String?, message: String) {
        // Log the alert
        logger.info("Terminal Alert - \(title ?? "Alert"): \(message)")

        // Show as a system notification if app is in background
        // For now, just provide haptic feedback
        HapticFeedback.notification(.error)
    }

    func scrollToBottom() {
        // Signal the terminal to scroll to bottom
        isAutoScrollEnabled = true
        isAtBottom = true
    }

    func updateScrollState(isAtBottom: Bool) {
        self.isAtBottom = isAtBottom
        self.isAutoScrollEnabled = isAtBottom
    }

    func toggleFitToWidth() {
        fitToWidth.toggle()
        HapticFeedback.impact(.light)

        if fitToWidth {
            // Calculate optimal width to fit the screen
            let screenWidth = UIScreen.main.bounds.width
            let padding: CGFloat = 32 // Account for UI padding
            let charWidth: CGFloat = 9 // Approximate character width
            let optimalCols = Int((screenWidth - padding) / charWidth)

            // Resize to fit
            resize(cols: max(optimalCols, 80), rows: max(terminalRows, 24))
        }
    }



    /// Fetch a one-time snapshot and feed it as initial history before live SSE updates
    private func bootstrapInitialSnapshot() async {
        guard !sseBootstrapped else { return }
        sseBootstrapped = true
        do {
            logger.info("Bootstrapping initial snapshot for session: \(session.id)")
            let serverSnapshot = try await APIClient.shared.getSessionSnapshot(sessionId: session.id)

            if let header = serverSnapshot.header {
                terminalCols = header.width
                terminalRows = header.height
                logger.info("Snapshot header dimensions: \(header.width)x\(header.height)")
            }

            let ansi = serverSnapshot.events
                .filter { $0.type == .output }
                .map { $0.data }
                .joined()

            guard !ansi.isEmpty else {
                logger.info("Snapshot contained no output events")
                return
            }

            // For SwiftTerm renderer, feed raw ANSI directly
            if let rawANSIUpdate = onRawANSIUpdate {
                logger.info("Feeding bootstrapped ANSI (len=\(ansi.count)) to SwiftTerm renderer")
                rawANSIUpdate(ansi)
            }
        } catch {
            logger.error("Failed to bootstrap snapshot: \(error)")
        }
    }

    func handleScroll(position: Double) {
        // Update scroll state based on position
        // Position is 0.0 at top, 1.0 at bottom
        isAtBottom = position >= 0.95
        if isAtBottom {
            isAutoScrollEnabled = true
        }
    }
    
    private func completeSeeding() {
        // Unsubscribe from buffers
        bufferWebSocketClient.unsubscribe(from: session.id)
        
        // End seeding phase
        isSeeding = false
        
        // Flush any buffered SSE chunks
        for chunk in bufferedSSEChunks {
            onRawANSIUpdate?(chunk)
        }
        bufferedSSEChunks.removeAll()
    }
    

    func updateTerminalSize(cols: Int, rows: Int) {
        // Update terminal dimensions and notify server
        terminalCols = cols
        terminalRows = rows
        resize(cols: cols, rows: rows)
    }

    func sendInput(_ data: Data) {
        // Send raw data input to the server
        Task {
            do {
                // Convert data to string and send
                if let text = String(data: data, encoding: .utf8) {
                    try await SessionService().sendInput(to: session.id, text: text)
                } else {
                    // If not UTF-8, try sending as base64 or handle binary data
                    logger.warning("Non-UTF8 input data, sending as-is")
                    let text = String(decoding: data, as: UTF8.self)
                    try await SessionService().sendInput(to: session.id, text: text)
                }
            } catch {
                logger.error("Failed to send input data: \(error)")
            }
        }
    }
}

// MARK: - WebSocket Event Handling

extension TerminalViewModel {
    private func handleWebSocketEvent(_ event: TerminalWebSocketEvent) {
        switch event {
        case .bufferUpdate(let snapshot):
            hasReceivedData = true
            
            // Update terminal dimensions from buffer snapshot
            terminalCols = snapshot.cols
            terminalRows = snapshot.rows
            if isConnecting { isConnecting = false; isConnected = true }
            
            // Note: XtermWebView handles buffer updates internally
            
        case .output:
            // Direct output event (not typically used in buffer mode)
            hasReceivedData = true
            if isConnecting { isConnecting = false; isConnected = true }
            
        case .resize(_, let dims):
            let parts = dims.split(separator: "x")
            if parts.count == 2, let c = Int(parts[0]), let r = Int(parts[1]) {
                logger.info("WebSocket resize: \(c)x\(r)")
                terminalCols = c
                terminalRows = r
            }
            if isConnecting { isConnecting = false; isConnected = true }
            
        case .bell:
            handleTerminalBell()
            
        case .exit(let exitCode):
            logger.info("Session exited with code: \(exitCode)")
            errorMessage = "Session ended (exit code: \(exitCode))"
            isConnected = false
            bufferWebSocketClient.unsubscribe(from: session.id)
            
        case .header(let width, let height):
            terminalCols = width
            terminalRows = height
            if isConnecting { isConnecting = false; isConnected = true }

        case .alert(let title, let message):
            handleTerminalAlert(title: title, message: message)
        }
    }
}

// MARK: - SSEClientDelegate

extension TerminalViewModel: SSEClientDelegate {
    nonisolated func sseClient(_ client: SSEClient, didReceiveEvent event: SSEClient.SSEEvent) {
        Task { @MainActor in
            switch event {
            case .connected:
                if isConnecting {
                    isConnecting = false
                    isConnected = true
                    errorMessage = nil
                    logger.info("SSE connected - HTTP 200 received")
                    logger.info("UI state: isConnecting=\(isConnecting) isConnected=\(isConnected)")
                    
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if isConnected && !hasReceivedData {
                            logger.info("SSE connected but no data yet - showing idle hint")
                        }
                    }

                    Task { await self.bootstrapInitialSnapshot() }
                }
                
            case .terminalOutput(_, let type, let data):
                if isConnecting {
                    isConnecting = false
                    isConnected = true
                    errorMessage = nil
                    logger.info("SSE connected - received terminal output")
                    logger.info("UI state: isConnecting=\(isConnecting) isConnected=\(isConnected)")
                }
                
                hasReceivedData = true
                
                if type == "r" {
                    let components = data.split(separator: "x")
                    if components.count == 2,
                       let width = Int(components[0]),
                       let height = Int(components[1])
                    {
                        logger.info("SSE resize from output: \(width)x\(height)")
                        terminalCols = width
                        terminalRows = height
                    }
                } else if type == "o" {
                    if renderer == .swiftTerm {
                        if isSeeding {
                            bufferedSSEChunks.append(data)
                            logger.debug("Buffered SSE chunk during seeding (len=\(data.count))")
                        } else {
                            onRawANSIUpdate?(data)
                        }
                    }
                }
                
            case .exit(let exitCode, let sessionId):
                guard sessionId == session.id else {
                    logger.warning("Ignoring exit for different session: \(sessionId)")
                    return
                }
                if isSeeding {
                    isSeeding = false
                    bufferedSSEChunks.removeAll()
                    bufferWebSocketClient.unsubscribe(from: session.id)
                }
                logger.info("Session exited with code: \(exitCode)")
                errorMessage = "Session ended (exit code: \(exitCode))"
                isConnected = false
                logger.info("UI state: isConnecting=\(isConnecting) isConnected=\(isConnected)")
                sseClient?.stop()
                sseClient = nil
                
            case .error(let message):
                logger.error("SSE error: \(message)")
                errorMessage = message
                if isSeeding {
                    completeSeeding()
                }
            }
        }
    }
}
