extension SMC {
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
}
