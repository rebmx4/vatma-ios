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
            [Self.waiting, "Подготовка", "Подготовка файла", "Скачивание", "Восстанавливаю соединение", "Ожидание сети"].contains(phase)
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

func backupFetchOptions(includePhoto: Bool, includeVideo: Bool) -> PHFetchOptions {
    var choices: [NSPredicate] = []
    if includePhoto {
        choices.append(NSPredicate(format: "mediaType == %d", Int(PHAssetMediaType.image.rawValue)))
    }
    if includeVideo {
        choices.append(NSPredicate(format: "mediaType == %d", Int(PHAssetMediaType.video.rawValue)))
    }
    let options = PHFetchOptions()
    options.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: choices)
    options.includeHiddenAssets = true
    options.includeAllBurstAssets = true
    options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    return options
}


// Existing jobs stay bound to the original volume. A different current disk
// only applies to newly discovered assets for that media type.
func backupSettingsAllow(_ destination: Destination, settings: [String:Any]) -> Bool {
    let type: String
    switch destination.path {
    case "/Фото": type = "photo"
    case "/Видео": type = "video"
    default: return false
    }
    guard let preference = settings[type] as? [String:Any], preference["enabled"] as? Bool == true,
          let disk = (preference["disk"] as? String)?.lowercased(), ["c","d","e"].contains(disk)
    else { return false }
    return destination.source == "backup-" + disk
}
