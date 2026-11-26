import Foundation
import Photos

struct Destination: Codable {
    var source: String
    var path: String
}

struct DiskJob: Codable, Identifiable {
    static let waiting = "Ожидает"
    static let stopped = "Остановлено"

    var id: String
    var name: String
    var destination: Destination?
    var downloadURL: URL?
    var asset: String?
    var phase: String = DiskJob.waiting
    var uploaded = false
    var progress: Double = 0
    var localName: String?
    var remotePath: String?
    var hiddenFromQueue: Bool?

    var isStopped: Bool { phase == Self.stopped }
    var isFinished: Bool { phase == "Готово" }
    var canStopDownload: Bool {
        downloadURL != nil && localName == nil &&
            [Self.waiting, "Подготовка", "Скачивание", "Восстанавливаю соединение", "Ожидание сети"].contains(phase)
    }
    var canRemoveDownload: Bool { downloadURL != nil && !canStopDownload && phase != "Проверка файла" }
    var canRetryDownload: Bool { canRemoveDownload && !isFinished }
}

struct BackupHistory {
    private var assetsBySource: [String: Set<String>] = [:]

    init(jobs: [DiskJob]) {
        for job in jobs {
            if let source = job.destination?.source, let asset = job.asset {
                record(asset, on: source)
            }
        }
    }

    func contains(_ asset: String, on source: String) -> Bool {
        assetsBySource[source]?.contains(asset) == true
    }

    mutating func record(_ asset: String, on source: String) {
        assetsBySource[source, default: []].insert(asset)
    }
}

func backupAssetPredicate(includeVideo: Bool, photoCutoff: Date?) -> NSPredicate {
    var choices: [NSPredicate] = []
    if includeVideo {
        choices.append(NSPredicate(format: "mediaType == %d", Int(PHAssetMediaType.video.rawValue)))
    }
    if let photoCutoff {
        choices.append(NSPredicate(format: "mediaType == %d AND creationDate >= %@",
                                   Int(PHAssetMediaType.image.rawValue), photoCutoff as NSDate))
    }
    return NSCompoundPredicate(orPredicateWithSubpredicates: choices)
}
