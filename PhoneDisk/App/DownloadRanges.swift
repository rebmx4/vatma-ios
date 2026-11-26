import Foundation

/// A fixed partition lets iOS own every request even after the app is suspended.
struct DownloadRanges: Codable {
    static let count = 10
    static let minimumSize: Int64 = 10 * 1024 * 1024
    let generation: UUID
    let prefix: Int64
    let size: Int64

    init?(prefix: Int64, size: Int64) {
        guard prefix >= 0, size >= prefix, size - prefix >= Self.minimumSize else { return nil }
        generation = UUID()
        self.prefix = prefix
        self.size = size
    }

    var ranges: [Range<Int64>] {
        let width = (size - prefix) / Int64(Self.count)
        let remainder = (size - prefix) % Int64(Self.count)
        var start = prefix
        return (0..<Self.count).map { i in
            let end = start + width + (Int64(i) < remainder ? 1 : 0)
            defer { start = end }
            return start..<end
        }
    }

    func directory(in jobFolder: URL) -> URL {
        jobFolder.appendingPathComponent(generation.uuidString, isDirectory: true)
    }

    func part(at start: Int64, in jobFolder: URL) -> URL {
        directory(in: jobFolder).appendingPathComponent(String(start))
    }

    func resumeData(at start: Int64, in jobFolder: URL) -> URL {
        directory(in: jobFolder).appendingPathComponent("resume-\(start)")
    }

    func staged(_ range: Range<Int64>, in jobFolder: URL) -> Bool {
        let url = part(at: range.lowerBound, in: jobFolder)
        let length = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return length.map(Int64.init) == range.upperBound - range.lowerBound
    }

    func accepts(_ reply: HTTPURLResponse, for range: Range<Int64>, etag: String) -> Bool {
        guard reply.statusCode == 206, reply.value(forHTTPHeaderField: "ETag") == etag,
              let value = reply.value(forHTTPHeaderField: "Content-Range") else { return false }
        let suffix = "-\(range.upperBound - 1)/\(size)"
        guard value.hasPrefix("bytes "), value.hasSuffix(suffix),
              let returnedStart = Int64(value.dropFirst(6).dropLast(suffix.count)) else { return false }
        // A resumed system task can describe only the tail on the wire. Its on-disk
        // temporary file must still match the length of the entire assigned range.
        return range.contains(returnedStart)
    }

    func stage(_ temporary: URL, range: Range<Int64>, in jobFolder: URL) throws {
        guard let length = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              Int64(length) == range.upperBound - range.lowerBound else { throw DiskFailure.rejected }
        if staged(range, in: jobFolder) { return }
        let destination = part(at: range.lowerBound, in: jobFolder)
        let files = FileManager.default
        try files.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                ofItemAtPath: temporary.path)
        if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
        // The system owns the original until this delegate call returns.
        try files.moveItem(at: temporary, to: destination)
    }

    static func append(_ part: URL, range: Range<Int64>, to destination: URL) throws {
        let input = try FileHandle(forReadingFrom: part)
        defer { try? input.close() }
        guard try input.seekToEnd() == UInt64(range.upperBound - range.lowerBound) else { throw DiskFailure.rejected }
        try input.seek(toOffset: 0)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        guard try output.seekToEnd() >= UInt64(range.lowerBound) else { throw DiskFailure.rejected }
        // Bytes beyond the durable prefix may belong to an interrupted assembly.
        try output.truncate(atOffset: UInt64(range.lowerBound))
        try output.seek(toOffset: UInt64(range.lowerBound))
        while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
            try output.write(contentsOf: data)
        }
        try output.synchronize()
    }
}
