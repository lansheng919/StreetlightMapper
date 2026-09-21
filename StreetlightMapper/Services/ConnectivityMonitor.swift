import Network
import Foundation
import Combine

/// Monitors network reachability and triggers sync when connectivity is restored.
final class ConnectivityMonitor: ObservableObject {

    @Published private(set) var isConnected = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.slmapper.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
