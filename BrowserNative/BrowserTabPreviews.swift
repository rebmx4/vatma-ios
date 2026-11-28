import UIKit
import WebKit

struct TabPreview {
    let url: URL
    let source: String
    let captured: Date
}

struct TabPreviewStore {
    private struct Snapshot: Codable {
        let url: URL
        let jpeg: Data
    }

    static let limit = 32
    let directory: URL

    init(directory: URL = URL.cachesDirectory.appendingPathComponent("ATMATabPreviews", isDirectory: true)) {
        self.directory = directory
    }

    private func file(for id: String) -> URL? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return directory.appendingPathComponent(uuid.uuidString).appendingPathExtension("json")
    }

    func preview(for tab: BrowserTab) -> TabPreview? {
        guard !tab.isPrivate, !tab.isPrivateDesktop, let file = file(for: tab.id),
              let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.url.absoluteString == tab.url else { return nil }
        let captured = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return TabPreview(url: snapshot.url, source: "data:image/jpeg;base64," + snapshot.jpeg.base64EncodedString(), captured: captured)
    }

    func save(_ jpeg: Data, url: URL, for tab: BrowserTab) {
        guard !tab.isPrivate, !tab.isPrivateDesktop, tab.url == url.absoluteString,
              let file = file(for: tab.id) else { return }
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Snapshot(url: url, jpeg: jpeg))
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            let newestFirst = files.compactMap { file -> (URL, Date)? in
                guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
                return (file, date)
            }.sorted { $0.1 > $1.1 }
            for (stale, _) in newestFirst.dropFirst(Self.limit) { try? manager.removeItem(at: stale) }
        } catch {
            // File protection or cache eviction can make disk snapshots unavailable.
        }
    }

    func remove(for id: String) {
        if let file = file(for: id) { try? FileManager.default.removeItem(at: file) }
    }
}

@MainActor
final class TabPreviewCapture {
    var completions: [() -> Void] = []
    private(set) var transitionsReleased = false
    func finish() {
        transitionsReleased = true
        let callbacks = completions
        completions.removeAll()
        callbacks.forEach { $0() }
    }
}

extension BrowserController {
    func tabOverviewState() -> [[String: Any]] {
        model.tabs.map { tab in
            var entry = tab.json
            entry["previewDocument"] = tabPreviewDocuments[tab.id, default: 0]
            return entry
        }
    }

    func invalidatePreview(for id: String) {
        tabPreviews.removeValue(forKey: id)
        tabPreviewVersion += 1
        tabPreviewDocuments[id] = tabPreviewVersion
        let pending = previewCaptures.removeValue(forKey: id)
        pending?.finish()
    }

    func tabPreviewSource(for tab: BrowserTab) -> String? {
        guard !tab.isPrivate, !tab.isPrivateDesktop else { return nil }
        if let preview = tabPreviews[tab.id], preview.url.absoluteString == tab.url { return preview.source }
        return tabPreviewStore.preview(for: tab)?.source
    }

    func captureCurrentPreview(completion: @escaping () -> Void) {
        let id = model.activeTabId
        guard !model.active.isPrivate, !model.active.isPrivateDesktop, mode == "browse", panel == nil,
              let page = currentRenderer, !page.isHidden,
              page.window != nil, page.bounds.width > 0, page.bounds.height > 0, let url = page.url,
              ["http", "https"].contains(url.scheme ?? "") else {
            completion(); return
        }
        if let pending = previewCaptures[id] {
            if pending.transitionsReleased { completion() }
            else { pending.completions.append(completion) }
            return
        }
        let pending = TabPreviewCapture(); pending.completions.append(completion)
        previewCaptures[id] = pending
        let finish = { [weak self] in
            guard let self, self.previewCaptures[id] === pending else { return }
            self.previewCaptures.removeValue(forKey: id)
            pending.finish()
        }
        // Allow the transition while a slower WebKit snapshot is still in flight.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { pending.finish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: finish)
        let config = WKSnapshotConfiguration(); config.snapshotWidth = NSNumber(value: 280)
        // Capture the visible renderer before a tab/panel transition hides it.
        page.takeSnapshot(with: config) { [weak self, weak page] image, _ in
            guard let self, self.previewCaptures[id] === pending else { return }
            if let page, self.renderers[id] === page, page.url == url,
               let tab = self.model.tabs.first(where: { $0.id == id && !$0.isPrivate && !$0.isPrivateDesktop && $0.url == url.absoluteString }),
               let image, image.size.width > 0, image.size.height > 0 {
                let width = min(280, image.size.width)
                let size = CGSize(width: width, height: max(1, image.size.height * width / max(1, image.size.width)))
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let bounded = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                if let data = bounded.jpegData(compressionQuality: 0.65) {
                    self.tabPreviews[id] = TabPreview(url: url, source: "data:image/jpeg;base64," + data.base64EncodedString(), captured: Date())
                    self.tabPreviewStore.save(data, url: url, for: tab)
                    while self.tabPreviews.count > TabPreviewStore.limit, let oldest = self.tabPreviews.min(by: { $0.value.captured < $1.value.captured })?.key {
                        self.tabPreviews.removeValue(forKey: oldest)
                    }
                    self.tabPreviewVersion += 1
                    self.publish()
                }
            }
            finish()
        }
    }
}
