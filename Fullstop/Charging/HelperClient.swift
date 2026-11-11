import Observation
import ServiceManagement
import XPC

enum HelperError: Error {
    case notInstalled
    case unresponsive
    case failed(String)
}

private final class PendingReply {
    private var continuation: CheckedContinuation<HelperReply, any Error>?

    init(_ continuation: CheckedContinuation<HelperReply, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<HelperReply, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

@Observable
final class HelperClient {
    static let shared = HelperClient()

    private(set) var status: SMAppService.Status
    private(set) var installError: String?

    @ObservationIgnored var onDisconnect: (() -> Void)?
    @ObservationIgnored private let service = SMAppService.daemon(plistName: "\(HelperService.label).plist")
    @ObservationIgnored private var session: XPCSession?
    @ObservationIgnored private var generation = 0

    private static let replyTimeout = Duration.seconds(10)

    private init() {
        status = DemoData.isEnabled ? .enabled : service.status
    }

    var isReady: Bool { status == .enabled }

    func refresh() {
        guard !DemoData.isEnabled else { return }
        let current = service.status
        if current != status { status = current }
    }

    func install() {
        guard !DemoData.isEnabled else { return }
        do {
            try service.register()
            installError = nil
        } catch {
            installError = error.localizedDescription
        }
        refresh()
        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func uninstall() async {
        guard !DemoData.isEnabled else { return }
        disconnect()
        try? await service.unregister()
        refresh()
    }

    func send(_ request: HelperRequest) async throws {
        guard !DemoData.isEnabled else { return }
        guard isReady else { throw HelperError.notInstalled }
        let session = try connect()
        let reply: HelperReply = try await withCheckedThrowingContinuation { continuation in
            let pending = PendingReply(continuation)
            do {
                try session.send(request) { (result: Result<HelperReply, any Error>) in
                    Task { @MainActor in pending.resume(with: result) }
                }
            } catch {
                pending.resume(with: .failure(error))
            }
            Task {
                try? await Task.sleep(for: Self.replyTimeout)
                pending.resume(with: .failure(HelperError.unresponsive))
            }
        }
        if let error = reply.error { throw HelperError.failed(error) }
    }

    func disconnect() {
        let session = session
        self.session = nil
        session?.cancel(reason: "Fullstop is done with the helper")
    }

    private func connect() throws -> XPCSession {
        if let session { return session }
        generation += 1
        let current = generation
        let session = try XPCSession(machService: HelperService.label, options: .inactive) { _ in
            Task { @MainActor in Self.shared.sessionEnded(current) }
        }
        session.setPeerRequirement(.isFromSameTeam(andMatchesSigningIdentifier: HelperService.label))
        try session.activate()
        self.session = session
        return session
    }

    private func sessionEnded(_ ended: Int) {
        guard ended == generation, session != nil else { return }
        session = nil
        onDisconnect?()
    }
}
