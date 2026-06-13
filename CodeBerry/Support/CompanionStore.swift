import SwiftUI
import UIKit
import AgentKit

/// Discovers companion Macs (AgentOS) on the local network and manages the
/// handshake session. Build & run commands will ride this link later.
@Observable
@MainActor
final class CompanionStore {
    enum ConnectionState {
        case disconnected
        case connecting(String)
        case connected(CompanionMessage.Welcome)
    }

    private(set) var macs: [CompanionEndpoint] = []
    private(set) var state: ConnectionState = .disconnected
    private(set) var latencyText: String?
    var errorText: String?

    private let browser = CompanionBrowser()
    private let session = CompanionSession()
    private var browseTask: Task<Void, Never>?

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    func startBrowsing() {
        guard browseTask == nil else { return }
        browseTask = Task { [browser] in
            for await endpoints in browser.discoveries() {
                self.macs = endpoints
            }
        }
    }

    func stopBrowsing() {
        browseTask?.cancel()
        browseTask = nil
        browser.stop()
        macs = []
    }

    func connect(to mac: CompanionEndpoint) {
        connect(name: mac.name) { hello, session in
            try await session.connect(to: mac.endpoint, hello: hello)
        }
    }

    /// Off-LAN path: "host:port" as shown in the Mac's AgentOS settings.
    /// Reaches Macs Bonjour can't see (different network via Tailscale/VPN
    /// or port forwarding).
    func connectManually(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.lastIndex(of: ":"),
              let port = UInt16(trimmed[trimmed.index(after: separator)...]),
              separator != trimmed.startIndex else {
            errorText = "Enter the Mac's address as host:port, e.g. my-mac.local:57452."
            return
        }
        let host = String(trimmed[..<separator])
        lastManualAddress = trimmed
        connect(name: host) { hello, session in
            try await session.connect(host: host, port: port, hello: hello)
        }
    }

    var lastManualAddress: String {
        get { UserDefaults.standard.string(forKey: "companionManualAddress") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "companionManualAddress") }
    }

    private func connect(name: String,
                         _ open: @escaping (CompanionMessage.Hello, CompanionSession) async throws -> CompanionMessage.Welcome) {
        guard !isConnected else { return }
        state = .connecting(name)
        errorText = nil
        Task {
            do {
                let hello = CompanionMessage.Hello(
                    appName: "CodeBerry",
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                    deviceName: UIDevice.current.name)
                let welcome = try await open(hello, session)
                state = .connected(welcome)
                let roundTrip = try await session.ping()
                latencyText = String(format: "%.1f ms", roundTrip * 1000)
            } catch {
                state = .disconnected
                errorText = "Couldn't connect to \(name): \(error.localizedDescription)"
            }
        }
    }

    func disconnect() {
        Task {
            await session.disconnect()
            state = .disconnected
            latencyText = nil
        }
    }
}
