import Foundation
import Testing
@testable import VibeTunnel

@Suite("ServerListViewModel Tests", .tags(.critical, .mvvm))
@MainActor
struct ServerListViewModelTests {
    // MARK: - Test Helpers

    private func createTestViewModel() -> (viewModel: ServerListViewModel, keychain: MockKeychainService) {
        let mockKeychain = MockKeychainService()
        let testUserDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let mockStorage = MockStorage()
        let mockNetworkMonitor = MockNetworkMonitor(isConnected: true)
        let connectionManager = ConnectionManager.createForTesting(storage: mockStorage)

        let viewModel = ServerListViewModel(
            connectionManager: connectionManager,
            networkMonitor: mockNetworkMonitor,
            keychainService: mockKeychain,
            userDefaults: testUserDefaults
        )

        return (viewModel, mockKeychain)
    }

    private func createTestProfile(
        name: String = "Test Server",
        url: String = "http://localhost:4020",
        requiresAuth: Bool = false,
        username: String? = nil
    )
        -> ServerProfile
    {
        ServerProfile(
            id: UUID(),
            name: name,
            url: url,
            requiresAuth: requiresAuth,
            username: username
        )
    }

    // MARK: - Tests

    @Test("ViewModel initializes with empty profiles")
    func initializationWithEmptyProfiles() {
        let (viewModel, _) = createTestViewModel()

        #expect(viewModel.profiles.isEmpty)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.showLoginView == false)
        #expect(viewModel.currentConnectingProfile == nil)
    }

    @Test("Adding new profile updates profiles list")
    func addNewProfile() async throws {
        let (viewModel, keychain) = createTestViewModel()

        let profile = createTestProfile(
            name: "Test Server",
            url: "http://192.168.1.100:4020",
            requiresAuth: true,
            username: "testuser"
        )

        try await viewModel.addProfile(profile, password: "testpass123")

        #expect(viewModel.profiles.contains { $0.id == profile.id })

        // Verify password was saved
        let savedPassword = try? keychain.getPassword(for: profile.id)
        #expect(savedPassword == "testpass123")
    }

    @Test("Adding profile without password doesn't save to keychain")
    func addProfileWithoutPassword() async throws {
        let (viewModel, keychain) = createTestViewModel()

        let profile = createTestProfile(requiresAuth: false)

        try await viewModel.addProfile(profile, password: nil)

        #expect(viewModel.profiles.contains { $0.id == profile.id })

        // Verify no password was saved
        let savedPassword = try? keychain.getPassword(for: profile.id)
        #expect(savedPassword == nil)
    }

    @Test("Deleting profile removes from list")
    func deleteProfile() async throws {
        let (viewModel, _) = createTestViewModel()

        let profile = createTestProfile()
        try await viewModel.addProfile(profile, password: nil)

        #expect(viewModel.profiles.contains { $0.id == profile.id })

        try await viewModel.deleteProfile(profile)

        #expect(!viewModel.profiles.contains { $0.id == profile.id })
    }

    @Test("Connecting to profile updates state")
    func connectToProfile() async throws {
        let (viewModel, _) = createTestViewModel()

        let profile = createTestProfile()
        try await viewModel.addProfile(profile, password: nil)

        await viewModel.initiateConnectionToProfile(profile)

        #expect(viewModel.currentConnectingProfile?.id == profile.id)
    }

    @Test("Connection error sets error message with localized description")
    func connectionErrorSetsErrorMessage() async throws {
        let (viewModel, _) = createTestViewModel()

        // Create a profile with an invalid/unreachable server address
        let profile = createTestProfile(
            name: "Invalid Server",
            url: "http://192.168.999.999:4020" // Invalid IP address
        )
        try await viewModel.addProfile(profile, password: nil)

        // Clear any existing error message
        viewModel.errorMessage = nil

        // Attempt to connect - this should fail and set errorMessage
        await viewModel.initiateConnectionToProfile(profile)

        // Verify that an error message was set
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.errorMessage?.contains("Failed to connect") == true ||
            viewModel.errorMessage?.contains("Cannot") == true ||
            viewModel.errorMessage?.contains("Invalid") == true
        )
    }

    @Test("No network connection sets appropriate error message")
    func noNetworkConnectionSetsErrorMessage() async {
        // Create a mock network monitor that simulates no connection
        let mockNetworkMonitor = MockNetworkMonitor(isConnected: false)
        let mockStorage = MockStorage()
        let connectionManager = ConnectionManager.createForTesting(storage: mockStorage)

        let viewModel = ServerListViewModel(
            connectionManager: connectionManager,
            networkMonitor: mockNetworkMonitor,
            keychainService: MockKeychainService(),
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let profile = createTestProfile()

        // Clear any existing error message
        viewModel.errorMessage = nil

        // Attempt to connect without network
        await viewModel.initiateConnectionToProfile(profile)

        // Verify the specific error message for no network
        #expect(viewModel.errorMessage == "No internet connection available")
    }
}
