import Dispatch
import Synchronization
import XPC

func handle(_ request: HelperRequest) -> HelperReply {
    do {
        switch request {
        case let .setAdapter(connected):
            try Hardware.setAdapter(connected: connected)
        case .pulseAdapter:
            try Hardware.pulseAdapter()
        case let .setLight(light):
            try Hardware.setLight(light)
        case let .setTopOffLimit(limit):
            try TopOff.apply(limit: limit)
        case let .setEnergyMode(mode, onBattery):
            try Energy.apply(mode, onBattery: onBattery)
        }
        return HelperReply()
    } catch {
        return HelperReply(error: String(describing: error))
    }
}

let clients = Mutex(0)

atexit { Hardware.restoreAdapter() }
SleepWatcher.start()

let signals = [SIGTERM, SIGINT, SIGHUP].map { signal in
    Darwin.signal(signal, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
    source.setEventHandler { exit(0) }
    source.resume()
    return source
}

let listener = try XPCListener(
    service: HelperService.label,
    requirement: .isFromSameTeam(andMatchesSigningIdentifier: HelperService.appIdentifier)
) { request in
    clients.withLock { $0 += 1 }
    return request.accept { (message: HelperRequest) -> (any Encodable)? in
        handle(message)
    } cancellationHandler: { _ in
        Hardware.restoreAdapter()
        let remaining = clients.withLock { count in
            count -= 1
            return count
        }
        if remaining == 0 { exit(0) }
    }
}

withExtendedLifetime((listener, signals)) {
    dispatchMain()
}
