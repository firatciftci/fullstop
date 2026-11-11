import Observation
import ServiceManagement
import XPC

enum HelperError: Error {
    case notInstalled
    case failed(String)
}

@Observable
final class HelperClient {
    static let shared = HelperClient()

    private(set) var status: SMAppService.Status

    @ObservationIgnored private let service = SMAppService.daemon(plistName: "\(HelperService.label).plist")
    @ObservationIgnored private var session: XPCSession?

    private init() {
        status = service.status
    }

    var isReady: Bool { status == .enabled }

    func refresh() {
        status = service.status
    }

    func install() {
        try? service.register()
        refresh()
        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func send(_ request: HelperRequest) async throws {
        guard isReady else { throw HelperError.notInstalled }
        let session = try connect()
        let reply: HelperReply = try await withCheckedThrowingContinuation { continuation in
            do {
                try session.send(request) { (result: Result<HelperReply, any Error>) in
                    continuation.resume(with: result)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        if let error = reply.error { throw HelperError.failed(error) }
    }

    private func connect() throws -> XPCSession {
        if let session { return session }
        let session = try XPCSession(machService: HelperService.label, options: .inactive) { _ in
            Task { @MainActor in Self.shared.session = nil }
        }
        session.setPeerRequirement(.isFromSameTeam(andMatchesSigningIdentifier: HelperService.label))
        try session.activate()
        self.session = session
        return session
    }
}
