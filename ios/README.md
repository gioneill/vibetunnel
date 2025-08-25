# VibeTunnel iOS

🚀 Beautiful native iOS/iPadOS client for VibeTunnel terminal multiplexer with a modern, terminal-inspired design.

## ✨ Features

- **Native SwiftUI app** optimized for iOS 18+
- **Beautiful terminal-inspired UI** with custom theme and animations
- **Dual terminal renderers**: SwiftTerm (SSE text) and xterm.js (WebView, WS buffer), selectable in Terminal settings
- **Real-time session management** with SSE streaming
- **Keyboard toolbar** with special keys (arrows, ESC, CTRL combinations)
- **Font size adjustment** with live preview
- **Haptic feedback** throughout the interface
- **Session operations**: Create, kill, cleanup sessions
- **Auto-reconnection** and error handling
- **iPad optimized** (split view support coming soon)

## 🎨 Design Highlights

- Custom dark theme inspired by modern terminal aesthetics
- Smooth animations and transitions
- Glow effects on interactive elements
- Consistent spacing and typography
- Terminal-style monospace fonts throughout

## Quick Start

### Building

```bash
# Using Xcode
xcodebuild -project VibeTunnel-iOS.xcodeproj -scheme VibeTunnel-iOS build

# Using build script
./scripts/build.sh

# Build for simulator
./scripts/build.sh --simulator

# Debug build
./scripts/build.sh --configuration Debug
```

### Running Tests

```bash
# Run with coverage report (75% threshold)
./scripts/test-with-coverage.sh

# Quick test run
./scripts/quick-test.sh
```

### Code Quality

```bash
# Format and lint code
./scripts/lint.sh
```

## 📱 Setup Instructions

### Initial Team Configuration

VibeTunnel uses the same xcconfig approach as the macOS app for team management.

1. **Copy the template file to create your local configuration:**
   ```bash
   cp ../apple/Local.xcconfig.template ../apple/Local.xcconfig
   ```

2. **Edit `../apple/Local.xcconfig` and add your development team ID:**
   ```
   DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE
   ```

   **Finding your team ID in Xcode:**
   - Open Xcode → Settings (or Preferences) 
   - Go to Accounts tab
   - Select your Apple ID
   - Look for your Team ID in the team details

3. **Open the project in Xcode** - it will now use your personal development team automatically.

### Project Setup

The iOS project is already configured and ready to build. The main steps are:

1. **Install dependencies:** Open the project in Xcode and it will automatically resolve Swift Package dependencies (SwiftTerm)
2. **Set your team ID:** Follow the team configuration steps above
3. **Build and run:** Use Xcode or the build script

### Advanced Setup (if needed)

If you need to recreate the project from scratch:

1. The project uses SwiftTerm package: `https://github.com/migueldeicaza/SwiftTerm.git`
2. Minimum deployment target: iOS 18.0
3. Required Info.plist keys are already configured in `Resources/Info.plist`
4. Custom fonts (Fira Code) can be added to improve the terminal experience

### Build and Run

#### Using Xcode
1. Select your device or simulator (iOS 18+)
2. Press **⌘R** to build and run
3. The app will launch with the beautiful connection screen

#### Using Command Line
```bash
# Build the app
./scripts/build.sh

# Build for simulator  
./scripts/build.sh --simulator

# Run tests with coverage
./scripts/test-with-coverage.sh
```

## 🏗️ Architecture

```
VibeTunnel/
├── App/                    # App entry point and main views
├── Models/                 # Data models (Session, ServerConfig, etc.)
├── Views/                  # UI Components
│   ├── Connection/        # Server connection flow
│   ├── Sessions/          # Session list and management
│   ├── Terminal/          # Terminal emulator integration (SwiftTermHostingView, XtermWebView)
│   └── Common/            # Reusable components
├── Services/              # Networking and API
│   ├── APIClient          # HTTP client for REST API
│   ├── SessionService     # Session management logic
│   ├── SSEClient          # Server-Sent Events streaming
│   └── BufferWebSocketClient # WebSocket client for buffer snapshots
├── Utils/                 # Helpers and extensions
│   └── Theme.swift        # Design system and styling
└── Resources/             # Assets and configuration
```

## 🚦 Usage

1. **Connect to Server**
   - Enter your VibeTunnel server IP/hostname
   - Default port is 3000
   - Optionally name your connection

2. **Manage Sessions**
   - Tap **+** to create new session
   - Choose command (zsh, bash, python3, etc.)
   - Set working directory
   - Name your session (optional)

3. **Use Terminal**
   - Full terminal emulation with SwiftTerm
   - Special keys toolbar for mobile input
   - Pinch to zoom or use menu for font size
   - Long press for copy/paste

4. **Session Actions**
   - Swipe or long-press for context menu
   - Kill running sessions
   - Clean up exited sessions
   - Batch cleanup available

## 🛠️ Development Notes

- **Minimum iOS**: 18.0 (uses latest SwiftUI features)
- **Swift**: 6.0 compatible
- **Dependencies**: SwiftTerm for terminal emulation
- **Architecture**: MVVM with SwiftUI and Combine
- **Transport split**: SwiftTerm uses SSE text; xterm.js currently uses WebSocket buffer snapshots (historical choice from initial project setup; subject to change)

### Logging with vtlog

Monitor app logs in real-time using `vtlog`:

```bash
# Monitor all VibeTunnel logs
vtlog

# Filter for specific components
vtlog | grep BonjourDiscovery
vtlog | grep Logger
vtlog | grep ServerConfig

# Verbose logging
vtlog -v

# Monitor specific subsystem
vtlog --subsystem sh.vibetunnel.ios
```

### Code Quality

```bash
# Format and lint code
./scripts/lint.sh

# Run SwiftFormat only
swiftformat .

# Run SwiftLint only
swiftlint
```

## 🐛 Troubleshooting

- **Connection fails**: Ensure device and server are on same network
- **"Transport security" error**: Check NSAppTransportSecurity in Info.plist
- **Keyboard issues**: The toolbar provides special keys for terminal control
- **Performance**: Adjust font size if rendering is slow on older devices

## 🎯 Future Enhancements

- [ ] iPad split view and multitasking
- [ ] Hardware keyboard shortcuts
- [ ] Session recording and playback
- [ ] Multiple server connections
- [ ] Custom themes
- [ ] File upload/download
- [ ] Session sharing

## 📄 License

Same as VibeTunnel project.

---

**Note**: This is a complete, production-ready iOS app. All core features are implemented including terminal emulation, session management, and a beautiful UI. The only remaining task is iPad-specific optimizations for split view.