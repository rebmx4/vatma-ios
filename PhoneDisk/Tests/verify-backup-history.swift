import Foundation
import Photos

@main
struct VerifyBackupHistory {
    static func main() throws {
        let enabled = Date(timeIntervalSince1970: 1_800_000_000)
        let before = enabled.addingTimeInterval(-900_000)
        let after = enabled.addingTimeInterval(100)
        func asset(_ type: PHAssetMediaType, _ date: Date) -> NSDictionary {
            ["mediaType": NSNumber(value: type.rawValue), "creationDate": date] as NSDictionary
        }

        let selected = backupAssetPredicate(includeVideo: true, photoCutoff: enabled)
        precondition(selected.evaluate(with: asset(.video, before)), "Already recorded video must be eligible")
        precondition(selected.evaluate(with: asset(.video, after)), "New video must be eligible")
        precondition(!selected.evaluate(with: asset(.image, before)), "Existing photo date rule must remain")
        precondition(selected.evaluate(with: asset(.image, after)), "New photo must be eligible")
        let switchedOff = backupAssetPredicate(includeVideo: false, photoCutoff: nil)
        precondition(!switchedOff.evaluate(with: asset(.video, after)), "Turning video backup off stops selection")

        let disk = Destination(source: "backup-c", path: "/Видео")
        let completed = DiskJob(id: "first", name: "existing.mov", destination: disk, asset: "asset-1",
                                phase: "Готово", hiddenFromQueue: true)
        let pending = DiskJob(id: "second", name: "pending.mov", destination: disk, asset: "asset-2")
        let data = try JSONEncoder().encode([completed, pending])
        let reopened = try JSONDecoder().decode([DiskJob].self, from: data)
        precondition(reopened.filter { $0.hiddenFromQueue != true }.map(\.id) == ["second"],
                     "Cleaning the queue must hide the completed backup record")
        var history = BackupHistory(jobs: reopened)
        let reenabled = backupAssetPredicate(includeVideo: true, photoCutoff: nil)
        let laterVideos = [
            ("asset-1", asset(.video, before)),
            ("asset-2", asset(.video, before)),
            ("asset-3", asset(.video, after)),
        ]
        let newItems = laterVideos.filter { entry in
            reenabled.evaluate(with: entry.1) && !history.contains(entry.0, on: disk.source)
        }
        precondition(newItems.map { $0.0 } == ["asset-3"], "Re-enabling must enqueue only the new video")
        precondition(reopened.filter { $0.phase != "Готово" }.map(\.id) == ["second"],
                     "Only the unfinished queued transfer may retry")
        history.record("asset-3", on: disk.source)
        precondition(history.contains("asset-3", on: disk.source), "A fresh queue entry must be remembered")
        precondition(!history.contains("asset-1", on: "backup-d"), "The backup history must track each disk")
        print("Verified first backup of older videos and no duplicate queue entries after re-enabling.")
    }
}
