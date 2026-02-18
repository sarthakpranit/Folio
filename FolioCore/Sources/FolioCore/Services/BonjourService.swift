// BonjourService.swift
// Zero-configuration network discovery for Folio WiFi transfer

import Foundation
import Network
import Combine

// MARK: - Discovered Server

/// Represents a discovered Folio server on the network
public struct DiscoveredServer: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let host: String
    public let port: UInt16
    public let url: URL?
    public let txtRecord: [String: String]

    public init(id: String, name: String, host: String, port: UInt16, txtRecord: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.url = URL(string: "http://\(host):\(port)")
        self.txtRecord = txtRecord
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DiscoveredServer, rhs: DiscoveredServer) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Bonjour Errors

/// Errors specific to Bonjour discovery
public enum BonjourError: LocalizedError {
    case advertisementFailed(String)
    case browsingFailed(String)
    case resolutionFailed(String)
    case notAuthorized

    public var errorDescription: String? {
        switch self {
        case .advertisementFailed(let reason):
            return "Failed to advertise service: \(reason)"
        case .browsingFailed(let reason):
            return "Failed to browse for services: \(reason)"
        case .resolutionFailed(let reason):
            return "Failed to resolve service: \(reason)"
        case .notAuthorized:
            return "Local network access not authorized. Please enable in System Settings."
        }
    }
}

// MARK: - Bonjour Service

/// Service for advertising and discovering Folio servers on the local network
/// Uses Apple's Network framework for modern Bonjour implementation
@MainActor
public final class BonjourService: ObservableObject {

    // MARK: - Published Properties

    /// Whether the service is currently advertising
    @Published public private(set) var isAdvertising: Bool = false

    /// Whether the service is currently browsing for other servers
    @Published public private(set) var isBrowsing: Bool = false

    /// List of discovered Folio servers on the network
    @Published public private(set) var discoveredServers: [DiscoveredServer] = []

    /// Last error that occurred
    @Published public private(set) var lastError: BonjourError?

    // MARK: - Private Properties

    /// The NWListener for advertising our service
    private var listener: NWListener?

    /// The NWBrowser for discovering other services
    private var browser: NWBrowser?

    /// Service type for Folio (follows Bonjour naming convention)
    private let serviceType = "_folio._tcp"

    /// Service name (device name or custom name)
    private var serviceName: String

    /// TXT record data for additional service info
    private var txtRecord: [String: String] = [:]

    /// Dispatch queue for network operations
    private let queue = DispatchQueue(label: "com.folio.bonjour", qos: .userInitiated)

    // MARK: - Initialization

    public init(serviceName: String? = nil) {
        self.serviceName = serviceName ?? Host.current().localizedName ?? "Folio Library"

        // Add version info to TXT record
        self.txtRecord["version"] = FolioCoreVersion
        self.txtRecord["platform"] = "macOS"
    }

    // MARK: - Public Methods - Advertising

    /// Start advertising the Folio server on the network
    /// - Parameter port: The port the HTTP server is running on
    public func startAdvertising(port: UInt16) throws {
        guard !isAdvertising else {
            logger.warning("Already advertising Bonjour service")
            return
        }

        // Create NWListener for the service
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        do {
            // Create listener on the specified port
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            logger.error("Failed to create NWListener: \(error)")
            throw BonjourError.advertisementFailed(error.localizedDescription)
        }

        // Set the service type for Bonjour
        listener?.service = NWListener.Service(
            name: serviceName,
            type: serviceType,
            txtRecord: createTXTRecord()
        )

        // Handle state changes
        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleListenerState(state)
            }
        }

        // We don't need to handle incoming connections (HTTP server does that)
        // This listener is just for advertising
        listener?.newConnectionHandler = { connection in
            // Reject connections - the HTTP server handles these
            connection.cancel()
        }

        // Start the listener
        listener?.start(queue: queue)

        logger.info("Started Bonjour advertising: \(serviceName) on port \(port)")
    }

    /// Stop advertising the service
    public func stopAdvertising() {
        guard isAdvertising else { return }

        listener?.cancel()
        listener = nil
        isAdvertising = false

        logger.info("Stopped Bonjour advertising")
    }

    /// Update the TXT record with additional info (e.g., book count)
    public func updateTXTRecord(_ record: [String: String]) {
        txtRecord.merge(record) { _, new in new }

        // Update the listener's service if advertising
        if let listener = listener {
            listener.service = NWListener.Service(
                name: serviceName,
                type: serviceType,
                txtRecord: createTXTRecord()
            )
        }
    }

    // MARK: - Public Methods - Discovery

    /// Start browsing for other Folio servers on the network
    public func startBrowsing() {
        guard !isBrowsing else {
            logger.warning("Already browsing for Bonjour services")
            return
        }

        // Create browser for our service type
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: descriptor, using: parameters)

        // Handle state changes
        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleBrowserState(state)
            }
        }

        // Handle discovered/lost services
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleBrowseResults(results, changes: changes)
            }
        }

        // Start browsing
        browser?.start(queue: queue)

        logger.info("Started browsing for Folio servers")
    }

    /// Stop browsing for servers
    public func stopBrowsing() {
        guard isBrowsing else { return }

        browser?.cancel()
        browser = nil
        isBrowsing = false
        discoveredServers = []

        logger.info("Stopped browsing for Folio servers")
    }

    /// Refresh the list of discovered servers
    public func refresh() {
        if isBrowsing {
            stopBrowsing()
        }
        startBrowsing()
    }

    // MARK: - Private Methods

    /// Create NWTXTRecord from dictionary
    private func createTXTRecord() -> NWTXTRecord {
        var record = NWTXTRecord()
        for (key, value) in txtRecord {
            record[key] = value
        }
        return record
    }

    /// Handle NWListener state changes
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isAdvertising = true
            lastError = nil
            logger.info("Bonjour service ready and advertising")

        case .failed(let error):
            isAdvertising = false
            let bonjourError = BonjourError.advertisementFailed(error.localizedDescription)
            lastError = bonjourError
            logger.error("Bonjour advertising failed: \(error)")

        case .cancelled:
            isAdvertising = false
            logger.info("Bonjour advertising cancelled")

        case .waiting(let error):
            logger.warning("Bonjour advertising waiting: \(error)")

        default:
            break
        }
    }

    /// Handle NWBrowser state changes
    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            isBrowsing = true
            lastError = nil
            logger.info("Bonjour browsing ready")

        case .failed(let error):
            isBrowsing = false

            // Check for authorization error
            if case .posix(let code) = error, code == .EAUTH {
                lastError = .notAuthorized
            } else {
                lastError = .browsingFailed(error.localizedDescription)
            }
            logger.error("Bonjour browsing failed: \(error)")

        case .cancelled:
            isBrowsing = false
            logger.info("Bonjour browsing cancelled")

        default:
            break
        }
    }

    /// Handle browse results changes
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        var updatedServers: [DiscoveredServer] = []

        for result in results {
            // Extract endpoint info
            if case .service(let name, let type, let domain, _) = result.endpoint {
                // Skip our own service
                if name == serviceName { continue }

                // Create server entry
                // Note: We need to resolve to get the actual host/port
                let server = DiscoveredServer(
                    id: "\(name).\(type).\(domain.isEmpty ? "local" : domain)",
                    name: name,
                    host: "", // Will be resolved when selected
                    port: 0,
                    txtRecord: parseTXTRecord(result.metadata)
                )
                updatedServers.append(server)

                logger.debug("Found Folio server: \(name)")
            }
        }

        // Update the published list
        discoveredServers = updatedServers

        // Log changes
        for change in changes {
            switch change {
            case .added(let result):
                if case .service(let name, _, _, _) = result.endpoint {
                    logger.info("Discovered new Folio server: \(name)")
                }
            case .removed(let result):
                if case .service(let name, _, _, _) = result.endpoint {
                    logger.info("Folio server went offline: \(name)")
                }
            default:
                break
            }
        }
    }

    /// Parse TXT record from metadata
    private func parseTXTRecord(_ metadata: NWBrowser.Result.Metadata) -> [String: String] {
        var record: [String: String] = [:]

        if case .bonjour(let txtRecord) = metadata {
            // NWTXTRecord provides direct key-value access
            // Iterate through known keys
            for key in ["version", "platform", "books"] {
                if let value = txtRecord[key] {
                    record[key] = value
                }
            }
        }

        return record
    }

    /// Resolve a discovered server to get its actual host and port
    /// - Parameter server: The server to resolve
    /// - Returns: Resolved server with host and port, or nil if resolution fails
    public func resolve(_ server: DiscoveredServer) async throws -> DiscoveredServer {
        // Create an endpoint to resolve
        let endpoint = NWEndpoint.service(
            name: server.name,
            type: serviceType,
            domain: "local",
            interface: nil
        )

        let queue = self.queue  // Capture queue before closure
        return try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Get the resolved endpoint
                    if let resolvedEndpoint = connection.currentPath?.remoteEndpoint,
                       case .hostPort(let host, let port) = resolvedEndpoint {

                        let hostString: String
                        switch host {
                        case .ipv4(let addr):
                            hostString = addr.debugDescription
                        case .ipv6(let addr):
                            hostString = "[\(addr.debugDescription)]"
                        case .name(let name, _):
                            hostString = name
                        @unknown default:
                            hostString = host.debugDescription
                        }

                        let resolvedServer = DiscoveredServer(
                            id: server.id,
                            name: server.name,
                            host: hostString,
                            port: port.rawValue,
                            txtRecord: server.txtRecord
                        )

                        connection.cancel()
                        continuation.resume(returning: resolvedServer)
                    }

                case .failed(let error):
                    connection.cancel()
                    continuation.resume(throwing: BonjourError.resolutionFailed(error.localizedDescription))

                case .cancelled:
                    break

                default:
                    break
                }
            }

            connection.start(queue: queue)

            // Timeout after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if connection.state != .ready {
                    connection.cancel()
                    continuation.resume(throwing: BonjourError.resolutionFailed("Resolution timed out"))
                }
            }
        }
    }
}
