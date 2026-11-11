import IOKit

struct SMCError: Error, CustomStringConvertible {
    let description: String
}

final class SMC {
    private enum Offset {
        static let key = 0
        static let dataSize = 28
        static let result = 40
        static let command = 42
        static let bytes = 48
    }

    private enum Command: UInt8 {
        case writeBytes = 6
        case readKeyInfo = 9
    }

    private static let structSize = 80
    private static let maximumBytes = 32
    private static let selector: UInt32 = 2

    private let connection: io_connect_t

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError(description: "AppleSMC isn't available") }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else { throw SMCError(description: "Couldn't open AppleSMC (\(result))") }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    func write(_ key: String, _ bytes: Array<UInt8>) throws {
        let size = try keySize(key)
        guard size == bytes.count, size <= Self.maximumBytes else {
            throw SMCError(description: "\(key) takes \(size) bytes, not \(bytes.count)")
        }
        var input = Self.request(key, .writeBytes)
        Self.put(UInt32(size), into: &input, at: Offset.dataSize)
        input.replaceSubrange(Offset.bytes..<Offset.bytes + size, with: bytes)
        _ = try call(input)
    }

    private func keySize(_ key: String) throws -> Int {
        let output = try call(Self.request(key, .readKeyInfo))
        return Int(Self.get(output, at: Offset.dataSize))
    }

    private func call(_ input: Array<UInt8>) throws -> Array<UInt8> {
        var output = Array(repeating: UInt8.zero, count: Self.structSize)
        var outputSize = Self.structSize
        let result = input.withUnsafeBytes { inBuffer in
            output.withUnsafeMutableBytes { outBuffer in
                IOConnectCallStructMethod(
                    connection, Self.selector, inBuffer.baseAddress, Self.structSize, outBuffer.baseAddress, &outputSize)
            }
        }
        guard result == KERN_SUCCESS else { throw SMCError(description: "The SMC call failed (\(result))") }
        guard output[Offset.result] == 0 else { throw SMCError(description: "The SMC returned \(output[Offset.result])") }
        return output
    }

    private static func request(_ key: String, _ command: Command) -> Array<UInt8> {
        var buffer = Array(repeating: UInt8.zero, count: structSize)
        var code: UInt32 = 0
        for byte in key.utf8 {
            code = code << 8 | UInt32(byte)
        }
        put(code, into: &buffer, at: Offset.key)
        buffer[Offset.command] = command.rawValue
        return buffer
    }

    private static func put(_ value: UInt32, into buffer: inout Array<UInt8>, at offset: Int) {
        withUnsafeBytes(of: value.littleEndian) { bytes in
            buffer.replaceSubrange(offset..<offset + 4, with: bytes)
        }
    }

    private static func get(_ buffer: Array<UInt8>, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in (0..<4).reversed() {
            value = value << 8 | UInt32(buffer[offset + index])
        }
        return value
    }
}
