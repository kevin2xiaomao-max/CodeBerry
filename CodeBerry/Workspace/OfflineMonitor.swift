import Foundation
import Network

// MARK: - M4: Offline
//
// Reachability monitor. The sync/download UI disables network actions
// while offline and shows a banner; nothing is silently retried.

/// Network reachability, observable by SwiftUI.
@Observable
/// Network path monitor. All mutable state is confined to the main queue
/// (the NWPathMonitor handler dispatches there); safe to share.
/// Marked @unchecked Sendable for the @Sendable pathUpdateHandler.
final class OfflineMonitor: @unchecked Sendable {
    static let shared = OfflineMonitor()

    /// True when there is no usable network path.
    private(set) var isOffline: Bool = false
    /// The underlying path status, for debugging.
    private(set) var isExpensive: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "codeberry.offline")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            let expensive = path.isExpensive
            DispatchQueue.main.async {
                self?.isOffline = offline
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Test support

    /// Forces the offline flag (tests / previews).
    func setOfflineForTesting(_ offline: Bool) {
        isOffline = offline
    }
}
