import Foundation

/// App-wide configuration settings.
/// Provides centralized configuration for logging and other app behaviors.
enum AppConfig {
    /// Set the logging level for the app
    /// Change this to control verbosity of logs
    static func configureLogging() {
        #if DEBUG
            // Increase verbosity during debugging to surface connection traces
            Logger.globalLevel = .verbose
        #else
            // In release builds, only show warnings and errors
            Logger.globalLevel = .warning
        #endif
    }
}
