import Foundation
import ObjectiveC

enum PowerUIError: Error {
    case unavailable
    case outOfRange(Int)
    case failed(String)
}

final class PowerUI {
    static let shared = PowerUI()
    static let limits = 80...100

    private typealias Alloc = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>
    private typealias Initializer = @convention(c) (Unmanaged<AnyObject>, Selector, CFString) -> Unmanaged<AnyObject>?
    private typealias Count = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>) -> UInt64
    private typealias Action = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool
    private typealias SetByte = @convention(c) (AnyObject, Selector, UInt8, AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool

    private static let path = "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI"

    private let client: AnyObject?

    private init() {
        client = Self.makeClient()
    }

    func isEnabled() throws -> Bool {
        guard let (selector, function) = method("isMCLCurrentlyEnabled:", as: Count.self), let client else {
            throw PowerUIError.unavailable
        }
        var error: NSError?
        let value = function(client, selector, &error)
        if let error { throw PowerUIError.failed(error.localizedDescription) }
        return value != 0
    }

    func setLimit(_ value: Int) throws {
        guard Self.limits.contains(value) else { throw PowerUIError.outOfRange(value) }
        if value < Self.limits.upperBound, try !isEnabled() {
            try perform("enableMCL:")
        }
        guard let (selector, function) = method("setMCLLimit:error:", as: SetByte.self), let client else {
            throw PowerUIError.unavailable
        }
        var error: NSError?
        guard function(client, selector, UInt8(value), &error) else {
            throw PowerUIError.failed(error?.localizedDescription ?? "")
        }
    }

    private func perform(_ name: String) throws {
        guard let (selector, function) = method(name, as: Action.self), let client else { throw PowerUIError.unavailable }
        var error: NSError?
        guard function(client, selector, &error) else { throw PowerUIError.failed(error?.localizedDescription ?? "") }
    }

    private func method<T>(_ name: String, as _: T.Type) -> (Selector, T)? {
        guard let client else { return nil }
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(object_getClass(client), selector) else { return nil }
        return (selector, unsafeBitCast(method_getImplementation(method), to: T.self))
    }

    private static func makeClient() -> AnyObject? {
        guard dlopen(path, RTLD_NOW) != nil, let type = NSClassFromString("PowerUISmartChargeClient") else { return nil }
        let allocSelector = NSSelectorFromString("alloc")
        let initSelector = NSSelectorFromString("initWithClientName:")
        guard let allocMethod = class_getClassMethod(type, allocSelector),
            let initMethod = class_getInstanceMethod(type, initSelector)
        else { return nil }
        let alloc = unsafeBitCast(method_getImplementation(allocMethod), to: Alloc.self)
        let initialize = unsafeBitCast(method_getImplementation(initMethod), to: Initializer.self)
        return initialize(alloc(type, allocSelector), initSelector, "Fullstop" as CFString)?.takeRetainedValue()
    }
}
