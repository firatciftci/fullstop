nonisolated extension SMC {
    func float(_ key: String) throws -> Float {
        let size = try keySize(key)
        guard size == 4 else { throw SMCError(description: "\(key) isn't a float") }
        var input = Self.request(key, .readBytes)
        Self.put(UInt32(size), into: &input, at: Offset.dataSize)
        let output = try call(input)
        return Float(bitPattern: Self.get(output, at: Offset.bytes))
    }

    func hasKey(_ key: String) -> Bool {
        (try? keySize(key)) != nil
    }
}
