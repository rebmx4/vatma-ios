import NaturalLanguage
import SwiftUI
import Translation
import UIKit
import WebKit

@MainActor
final class BrowserPageTranslation {
    static var available: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        if #available(iOS 18.0, *) { return source != nil }
        return false
        #endif
    }

    private static let world = WKContentWorld.world(name: "ATMA.PageTranslation")
    private static let source: String? = {
        guard let url = Bundle.main.url(forResource: "site-translation", withExtension: "js", subdirectory: "BrowserUI/assets") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()
    private weak var browser: BrowserController?
    private weak var workingPage: WKWebView?
    private var job: UUID?
    private var host: UIViewController?
    private var loaded = Set<ObjectIdentifier>()
    private var handled = Set<ObjectIdentifier>()
    private var translated = Set<ObjectIdentifier>()
    private var failed = Set<ObjectIdentifier>()
    var prefersRussian = false

    init(browser: BrowserController) {
        self.browser = browser
    }

    var status: String {
        guard let page = browser?.currentRenderer else { return "original" }
        let key = ObjectIdentifier(page)
        if workingPage === page { return "translating" }
        if translated.contains(key) { return "translated" }
        if failed.contains(key) { return "unavailable" }
        return "original"
    }

    func reconcile() {
        guard Self.available, let browser, browser.mode == "browse", let page = browser.currentRenderer,
              prefersRussian, browser.panel == nil, job == nil,
              !handled.contains(ObjectIdentifier(page)) else { return }
        begin(in: page, manually: false)
    }

    func didFinish(_ page: WKWebView) {
        loaded.insert(ObjectIdentifier(page))
        reconcile()
    }

    func invalidate(_ page: WKWebView) {
        let key = ObjectIdentifier(page)
        loaded.remove(key)
        handled.remove(key)
        translated.remove(key)
        failed.remove(key)
        if workingPage === page { cancel() }
    }

    func toggle() {
        guard let page = browser?.currentRenderer, job == nil else { return }
        let key = ObjectIdentifier(page)
        if translated.contains(key) {
            translated.remove(key)
            page.callAsyncJavaScript("globalThis.__atmaPageTranslation?.restore();", arguments: [:],
                                     in: nil, in: Self.world, completionHandler: nil)
            browser?.publish()
        } else {
            begin(in: page, manually: true)
        }
    }

    private func begin(in page: WKWebView, manually: Bool) {
        guard Self.available, #available(iOS 18.0, *), let source = Self.source,
              loaded.contains(ObjectIdentifier(page)),
              !page.isLoading, ["https", "http"].contains(page.url?.scheme ?? "") else { return }
        let ticket = UUID()
        job = ticket
        workingPage = page
        let key = ObjectIdentifier(page)
        failed.remove(key)
        if manually { browser?.publish() }

        page.callAsyncJavaScript("""
            if (document.readyState === 'loading') return null;
            globalThis.__atmaPageTranslation ??= \(source);
            return globalThis.__atmaPageTranslation.collect(ticket);
            """, arguments: ["ticket": ticket.uuidString], in: nil, in: Self.world) { [weak self, weak page] result in
            guard let self, let page, self.job == ticket else { return }
            guard let payload = (try? result.get()) as? [String: Any],
                  let texts = payload["texts"] as? [String], !texts.isEmpty,
                  let language = payload["language"] as? String,
                  language == "en" || (language.isEmpty &&
                      NLLanguageRecognizer.dominantLanguage(for: texts.prefix(32).joined(separator: " ")) == .english) else {
                self.finish(ticket, applied: false, manually: manually)
                return
            }
            self.translate(texts, in: page, ticket: ticket, manually: manually)
        }
    }

    @available(iOS 18.0, *)
    private func translate(_ texts: [String], in page: WKWebView, ticket: UUID, manually: Bool) {
        guard let browser else { cancel(); return }
        let view = TranslationTaskView(texts: texts) { [weak self, weak page] results in
            guard let self, let page, self.job == ticket else { return }
            guard let results else {
                self.finish(ticket, applied: false, manually: manually)
                return
            }
            page.callAsyncJavaScript("return globalThis.__atmaPageTranslation?.apply(ticket, results) === true;",
                                     arguments: ["ticket": ticket.uuidString, "results": results], in: nil, in: Self.world) { [weak self] result in
                self?.finish(ticket, applied: (try? result.get()) as? Bool == true, manually: manually)
            }
        }
        let controller = UIHostingController(rootView: view)
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        controller.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        browser.addChild(controller)
        browser.view.addSubview(controller.view)
        controller.didMove(toParent: browser)
        host = controller
    }

    private func finish(_ ticket: UUID, applied: Bool, manually: Bool) {
        guard ticket == job, let page = workingPage else { return }
        let key = ObjectIdentifier(page)
        handled.insert(key)
        if applied { translated.insert(key) }
        else if manually { failed.insert(key) }
        cancel()
        browser?.publish()
        reconcile()
    }

    private func cancel() {
        job = nil
        workingPage = nil
        host?.willMove(toParent: nil)
        host?.view.removeFromSuperview()
        host?.removeFromParent()
        host = nil
    }
}

@available(iOS 18.0, *)
private struct TranslationTaskView: View {
    let texts: [String]
    let completion: @MainActor ([String]?) -> Void

    var body: some View {
        Color.clear.translationTask(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "ru")) { session in
            let requests = texts.map { TranslationSession.Request(sourceText: $0) }
            let results = try? await session.translations(from: requests)
            await completion(results?.map(\.targetText))
        }
    }
}
