import Foundation
import Photos

struct Destination: Codable {
    var source: String
    var path: String
}

struct DiskJob: Codable, Identifiable {
    var id: String
    var name: String
    var destination: Destination?
    var downloadURL: URL?
    var asset: String?
    var phase: String = "Ожидает"
    var uploaded = false
    var progress: Double = 0
    var localName: String?
    var remotePath: String?
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
