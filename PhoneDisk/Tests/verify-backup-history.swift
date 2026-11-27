import Foundation
import Photos

@main
struct VerifyBackupHistory {
    static func main() throws {
        let oldDate = Date(timeIntervalSince1970: 1_500_000_000)
        let recentDate = Date(timeIntervalSince1970: 1_800_000_000)
        func asset(_ type: PHAssetMediaType, _ date: Date?) -> NSDictionary {
            var fields: [String: Any] = ["mediaType": NSNumber(value: type.rawValue)]
            if let date { fields["creationDate"] = date }
            return fields as NSDictionary
        }

        let options = backupFetchOptions(includePhoto: true, includeVideo: true)
        let selected = options.predicate!
        for date in [oldDate, recentDate, nil] as [Date?] {
            precondition(selected.evaluate(with: asset(.image, date)), "Photos must be eligible regardless of date")
            precondition(selected.evaluate(with: asset(.video, date)), "Videos must be eligible regardless of date")
        }
        precondition(!selected.evaluate(with: asset(.audio, oldDate)), "Auto backup selects only images and videos")
        precondition(options.includeHiddenAssets && options.includeAllBurstAssets)
        precondition(options.includeAssetSourceTypes == [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced])
        let photoOnly = backupFetchOptions(includePhoto: true, includeVideo: false).predicate!
        let videoOnly = backupFetchOptions(includePhoto: false, includeVideo: true).predicate!
        let switchedOff = backupFetchOptions(includePhoto: false, includeVideo: false).predicate!
        precondition(photoOnly.evaluate(with: asset(.image, oldDate)) && !photoOnly.evaluate(with: asset(.video, oldDate)))
        precondition(videoOnly.evaluate(with: asset(.video, oldDate)) && !videoOnly.evaluate(with: asset(.image, oldDate)))
        precondition(!switchedOff.evaluate(with: asset(.image, oldDate)) && !switchedOff.evaluate(with: asset(.video, oldDate)))

        let disk = Destination(source: "backup-c", path: "/Видео")
        let photos = Destination(source: "backup-c", path: "/Фото")
        let completed = DiskJob(id: "first", name: "existing.mov", destination: disk, asset: "asset-1",
                                phase: "Готово", hiddenFromQueue: true)
        let pending = DiskJob(id: "second", name: "pending.mov", destination: disk, asset: "asset-2")
        let completedPhoto = DiskJob(id: "third", name: "existing.heic", destination: photos, asset: "photo-1",
                                    phase: "Готово", hiddenFromQueue: true)
        let data = try JSONEncoder().encode([completed, pending, completedPhoto])
        let reopened = try JSONDecoder().decode([DiskJob].self, from: data)
        precondition(reopened.filter { $0.hiddenFromQueue != true }.map(\.id) == ["second"],
                     "Cleaning the queue must hide the completed backup record")
        var history = BackupHistory(jobs: reopened)
        let availableItems = [
            ("asset-1", asset(.video, oldDate)),
            ("asset-2", asset(.video, oldDate)),
            ("asset-3", asset(.video, recentDate)),
            ("photo-1", asset(.image, recentDate)),
            ("photo-2", asset(.image, oldDate)),
        ]
        let newItems = availableItems.filter { entry in
            selected.evaluate(with: entry.1) && !history.contains(entry.0, on: disk.source)
        }
        precondition(newItems.map { $0.0 } == ["asset-3", "photo-2"],
                     "Scan must include older unbacked photos and skip completed and pending transfers")
        precondition(reopened.filter { $0.phase != "Готово" }.map(\.id) == ["second"],
                     "Only the unfinished queued transfer may retry")
        history.record("asset-3", on: disk.source)
        precondition(history.contains("asset-3", on: disk.source), "A fresh queue entry must be remembered")
        precondition(!history.contains("asset-1", on: "backup-d"), "The backup history must track each disk")
        print("Verified age-independent backup selection and no duplicate queue entries.")
        let fromD = Destination(source:"backup-d",path:"/Видео")
        let fromC = Destination(source:"backup-c",path:"/Видео")
        let photoFromD = Destination(source:"backup-d",path:"/Фото")
        let goingToD: [String:Any] = [
            "video":["enabled":true,"disk":"D"],
            "photo":["enabled":false,"disk":"D"]]
        assert(backupSettingsAllow(fromD,settings:goingToD))
        assert(!backupSettingsAllow(fromC,settings:goingToD))
        assert(!backupSettingsAllow(photoFromD,settings:goingToD))
        assert(!backupSettingsAllow(fromD,settings:["video":["enabled":false,"disk":"D"]]))
        assert(backupSettingsAllow(fromD,settings:goingToD))
    }
}
