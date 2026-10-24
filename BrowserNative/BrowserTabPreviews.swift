import UIKit
import WebKit

struct TabPreview {
    let url: URL
    let renderer: ObjectIdentifier
    let source: String
    let captured: Date
}

@MainActor
final class TabPreviewCapture {
    var completions: [() -> Void] = []
}

extension BrowserController {
    func invalidatePreview(for id: String) {
        tabPreviews.removeValue(forKey: id)
        let pending = previewCaptures.removeValue(forKey: id)
        pending?.completions.forEach { $0() }
    }

    func captureCurrentPreview(completion: @escaping () -> Void) {
        let id = model.activeTabId
        guard mode == "browse", panel == nil, let page = currentRenderer, !page.isHidden,
              page.window != nil, page.bounds.width > 0, page.bounds.height > 0, let url = page.url else {
            completion(); return
        }
        if let pending = previewCaptures[id] { pending.completions.append(completion); return }
        let pending = TabPreviewCapture(); pending.completions.append(completion)
        previewCaptures[id] = pending
        let config = WKSnapshotConfiguration(); config.snapshotWidth = NSNumber(value: 280)
        // Capture the visible renderer before a tab/panel transition hides it.
        page.takeSnapshot(with: config) { [weak self, weak page] image, _ in
            guard let self, self.previewCaptures[id] === pending else { return }
            self.previewCaptures.removeValue(forKey: id)
            if let page, self.renderers[id] === page, page.url == url,
               self.model.tabs.contains(where: { $0.id == id && $0.url == url.absoluteString }), let image {
                let width = min(280, image.size.width)
                let size = CGSize(width: width, height: max(1, image.size.height * width / max(1, image.size.width)))
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let bounded = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                if let data = bounded.jpegData(compressionQuality: 0.65) {
                    self.tabPreviews[id] = TabPreview(url: url, renderer: ObjectIdentifier(page), source: "data:image/jpeg;base64," + data.base64EncodedString(), captured: Date())
                    while self.tabPreviews.count > 12, let oldest = self.tabPreviews.min(by: { $0.value.captured < $1.value.captured })?.key {
                        self.tabPreviews.removeValue(forKey: oldest)
                    }
                }
            }
            pending.completions.forEach { $0() }
        }
    }
}
