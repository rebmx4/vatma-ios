import Foundation
import XCTest
@testable import PhoneDisk

final class DownloadRangeTests: XCTestCase {
    func testPartitionsSuffixExactlyAndRejectsShortFiles() throws {
        XCTAssertNil(DownloadRanges(prefix: 10, size: 9))
        XCTAssertNil(DownloadRanges(prefix: 0, size: 4096))
        for size: Int64 in [10_485_760 + 37, 3_000_000_000, .max] {
            let plan = try XCTUnwrap(DownloadRanges(prefix: 17, size: size))
            let slices = plan.ranges
            XCTAssertEqual(slices.count, 10)
            XCTAssertEqual(slices.first?.lowerBound, 17)
            XCTAssertEqual(slices.last?.upperBound, size)
            for (left, right) in zip(slices, slices.dropFirst()) {
                XCTAssertEqual(left.upperBound, right.lowerBound)
                XCTAssertLessThanOrEqual(abs(left.count - right.count), 1)
            }
        }
        let old = Data(#"{"size":12,"sha256":"sample","partSize":4,"confirmed":4,"etag":"sample"}"#.utf8)
        let migrated = try JSONDecoder().decode(TransferReceipt.self, from: old)
        XCTAssertNil(migrated.downloadRanges)
        XCTAssertEqual(migrated.confirmed, 4)
    }

    func testOutOfOrderStagingRepairAndValidator() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let plan = try XCTUnwrap(DownloadRanges(prefix: 0, size: DownloadRanges.minimumSize + 3))
        try FileManager.default.createDirectory(at: plan.directory(in: dir), withIntermediateDirectories: true)
        let ranges = plan.ranges
        let output = dir.appendingPathComponent("incoming")
        try Data("uncommitted partial copy".utf8).write(to: output)
        var expected = Data()
        for (index, range) in ranges.enumerated() {
            expected.append(Data(repeating: UInt8(index), count: range.count))
        }
        for range in ranges.reversed() {
            let temp = dir.appendingPathComponent(UUID().uuidString)
            try expected.subdata(in: Int(range.lowerBound)..<Int(range.upperBound)).write(to: temp)
            try plan.stage(temp, range: range, in: dir)
        }
        let recovered = try JSONDecoder().decode(DownloadRanges.self, from: JSONEncoder().encode(plan))
        for range in recovered.ranges {
            XCTAssertTrue(recovered.staged(range, in: dir))
            try DownloadRanges.append(recovered.part(at: range.lowerBound, in: dir), range: range, to: output)
            try FileManager.default.removeItem(at: recovered.part(at: range.lowerBound, in: dir))
        }
        XCTAssertEqual(try Data(contentsOf: output), expected)
        let range = ranges[3]
        let url = try XCTUnwrap(URL(string: "https://127.0.0.1/file"))
        func reply(_ status: Int, _ start: Int64, _ end: Int64, _ etag: String) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: [
                "ETag": etag, "Content-Range": "bytes \(start)-\(end - 1)/\(plan.size)"
            ])!
        }
        XCTAssertTrue(plan.accepts(reply(206, range.lowerBound + 3, range.upperBound, "a"), for: range, etag: "a"))
        XCTAssertFalse(plan.accepts(reply(200, range.lowerBound, range.upperBound, "a"), for: range, etag: "a"))
        XCTAssertFalse(plan.accepts(reply(206, range.lowerBound, range.upperBound + 1, "a"), for: range, etag: "a"))
        XCTAssertFalse(plan.accepts(reply(206, range.lowerBound, range.upperBound, "b"), for: range, etag: "a"))
        let short = dir.appendingPathComponent("short")
        try Data([0]).write(to: short)
        XCTAssertThrowsError(try plan.stage(short, range: range, in: dir))
        XCTAssertFalse(plan.staged(range, in: dir))
    }
}
