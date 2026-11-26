import WebKit

struct OverviewHistoryEntry {
    let tabID: String
    let url: String
    let title: String
    let item: WKBackForwardListItem?

    var json: [String: String] { ["tabId": tabID, "url": url, "title": title] }
}

extension BrowserController {
    func closeTab(_ id: String) throws {
        guard model.tabs.contains(where: { $0.id == id }) else { throw BrowserFailure.invalid("Unknown tab.") }
        try closeTabs([id])
    }

    func closeTabs(_ ids: Set<String>) throws {
        let activeID = model.activeTabId
        let replacementIndex = model.tabs.prefix(model.activeIndex).filter { !ids.contains($0.id) }.count
        let opener = windowOpeners[activeID]
        let keepOverview = panel == "tabs"
        windowOpeners = windowOpeners.filter { !ids.contains($0.key) && !ids.contains($0.value) }
        for id in ids {
            removeRenderer(for: id)
            tabPreviewDocuments.removeValue(forKey: id)
        }
        model.tabs.removeAll { ids.contains($0.id) }
        model.discardUnusedPrivateSessions()
        if model.tabs.isEmpty {
            let blank = BrowserTab(profileId: BrowserModel.actualProfile)
            model.tabs = [blank]
            model.activeTabId = blank.id
            mode = "home"
            if !keepOverview { panel = nil }
        } else if ids.contains(activeID) {
            let destination = opener.flatMap { candidate in model.tabs.first { $0.id == candidate }?.id }
                ?? model.tabs[min(replacementIndex, model.tabs.count - 1)].id
            try selectTab(destination, keepOverview: keepOverview)
            return
        }
        changed()
    }

    func duplicateOverviewTab(_ id: String) throws {
        guard let index = model.tabs.firstIndex(where: { $0.id == id }) else {
            throw BrowserFailure.invalid("Unknown tab.")
        }
        var copy = model.tabs[index]
        copy.id = UUID().uuidString
        copy.privateDesktopBrowsing = copy.isPrivateDesktop
        copy.shortcutId = nil
        copy.shortcutStartURL = nil
        copy.loading = false
        copy.error = nil
        model.tabs.insert(copy, at: index + 1)
        try selectTab(copy.id, keepOverview: panel == "tabs")
    }

    func overviewHistory() -> [OverviewHistoryEntry] {
        var entries: [OverviewHistoryEntry] = []
        let ordered = model.tabs[model.activeIndex...] + model.tabs[..<model.activeIndex]
        for tab in ordered where !tab.isPrivate && !tab.isPrivateDesktop {
            let list = renderers[tab.id]?.backForwardList
            var seen: Set<String> = []
            let current = list?.currentItem
            let page = current?.url.absoluteString ?? tab.url
            if (try? AddressResolver.validated(page)) != nil {
                seen.insert(page)
                entries.append(OverviewHistoryEntry(tabID: tab.id, url: page, title: current?.title ?? tab.title, item: current))
            }
            let items = Array((list?.backList ?? []).reversed()) + (list?.forwardList ?? [])
            for item in items {
                let url = item.url.absoluteString
                guard (try? AddressResolver.validated(url)) != nil, seen.insert(url).inserted else { continue }
                entries.append(OverviewHistoryEntry(tabID: tab.id, url: url, title: item.title ?? "", item: item))
                if entries.count >= 100 { break }
            }
            if entries.count >= 100 { break }
        }
        return entries
    }

    func openOverviewHistory(tabID: String, url: String) throws {
        guard let entry = overviewHistory().first(where: { $0.tabID == tabID && $0.url == url }) else {
            throw BrowserFailure.invalid("Unknown history entry.")
        }
        try selectTab(tabID)
        if let page = renderers[tabID], let item = entry.item, page.backForwardList.currentItem !== item {
            page.go(to: item)
        }
    }
}
