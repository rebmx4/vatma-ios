import NaturalLanguage
import SwiftUI
import Translation
import UIKit
import WebKit

@MainActor
final class BrowserPageTranslation {
    static let interfaceLanguages: Set<String> = ["ru", "en", "es", "de", "fr", "pt-BR", "it"]
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
    private var detections: [ObjectIdentifier: UUID] = [:]
    private var sources: [ObjectIdentifier: String] = [:]
    private var translated: [ObjectIdentifier: String] = [:]
    private var failed = Set<ObjectIdentifier>()
    private var target = "en"
    private struct LanguagePair: Hashable {
        let source: String
        let target: String
    }
    private var supported: [LanguagePair: Bool] = [:]
    private var checking = Set<LanguagePair>()

    init(browser: BrowserController) {
        self.browser = browser
    }

    var status: String {
        guard let page = browser?.currentRenderer else { return "original" }
        let key = ObjectIdentifier(page)
        if workingPage === page { return "translating" }
        if translated[key] != nil { return "translated" }
        if failed.contains(key) { return "unavailable" }
        return "original"
    }

    var offered: Bool {
        guard let page = browser?.currentRenderer, let pair = pair(for: page) else { return false }
        return supported[pair] == true
    }

    func setTarget(_ language: String) {
        if target != language {
            target = language
            failed.removeAll()
            let interruptedPage = workingPage
            cancel()
            if let interruptedPage { restore(interruptedPage) }
        }
        reconcile()
        browser?.publish()
    }

    private func pair(for page: WKWebView) -> LanguagePair? {
        guard let source = sources[ObjectIdentifier(page)],
              Locale.Language(identifier: source).languageCode != Locale.Language(identifier: target).languageCode else { return nil }
        return LanguagePair(source: source, target: target)
    }

    func reconcile() {
        guard Self.available, #available(iOS 18.0, *), let browser, let page = browser.currentRenderer,
              browser.mode == "browse" else { return }
        if let previous = translated[ObjectIdentifier(page)], previous != target {
            restore(page)
        }
        guard let pair = pair(for: page), supported[pair] == nil, checking.insert(pair).inserted else { return }
        Task {
            let status = await LanguageAvailability().status(from: Locale.Language(identifier: pair.source),
                                                             to: Locale.Language(identifier: pair.target))
            checking.remove(pair)
            supported[pair] = status != .unsupported
            browser.publish()
        }
    }

    func didFinish(_ page: WKWebView) {
        guard Self.available, let script = Self.source, ["http", "https"].contains(page.url?.scheme ?? "") else { return }
        let key = ObjectIdentifier(page)
        let ticket = UUID()
        detections[key] = ticket
        page.callAsyncJavaScript("""
            globalThis.__atmaPageTranslation ??= \(script);
            return globalThis.__atmaPageTranslation.languageSample();
            """, arguments: [:], in: nil, in: Self.world) { [weak self, weak page] result in
            guard let self, page != nil, self.detections[key] == ticket else { return }
            self.detections.removeValue(forKey: key)
            guard let payload = (try? result.get()) as? [String: String] else { return }
            let declared = payload["language"] ?? ""
            let sample = payload["sample"] ?? ""
            guard !sample.isEmpty else { return }
            self.sources[key] = Self.pageLanguage(declared: declared, sample: sample)
            self.reconcile()
            self.browser?.publish()
        }
    }

    static func pageLanguage(declared: String, sample: String) -> String? {
        let declared = declared.range(of: #"^[A-Za-z]{2,3}([_-][A-Za-z0-9]{2,8})*$"#, options: .regularExpression) == nil
            ? nil : declared.replacingOccurrences(of: "_", with: "-")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        if let detected = recognizer.dominantLanguage, sample.count >= 100,
           recognizer.languageHypotheses(withMaximum: 1)[detected, default: 0] >= 0.9,
           let declared, Locale.Language(identifier: declared).languageCode != Locale.Language(identifier: detected.rawValue).languageCode {
            return detected.rawValue
        }
        return declared ?? recognizer.dominantLanguage?.rawValue
    }

    func invalidate(_ page: WKWebView) {
        let key = ObjectIdentifier(page)
        detections.removeValue(forKey: key)
        sources.removeValue(forKey: key)
        translated.removeValue(forKey: key)
        failed.remove(key)
        if workingPage === page { cancel() }
    }

    func toggle() {
        guard let page = browser?.currentRenderer else { return }
        if workingPage != nil, workingPage !== page { cancel() }
        guard job == nil else { return }
        let key = ObjectIdentifier(page)
        if translated[key] != nil {
            restore(page)
        } else if let pair = pair(for: page), supported[pair] == true {
            begin(in: page, pair: pair)
        }
    }

    private func restore(_ page: WKWebView) {
        translated.removeValue(forKey: ObjectIdentifier(page))
        page.callAsyncJavaScript("globalThis.__atmaPageTranslation?.restore();", arguments: [:],
                                 in: nil, in: Self.world, completionHandler: nil)
        browser?.publish()
    }

    private func begin(in page: WKWebView, pair: LanguagePair) {
        guard Self.available, #available(iOS 18.0, *),
              !page.isLoading, ["https", "http"].contains(page.url?.scheme ?? "") else { return }
        let ticket = UUID()
        job = ticket
        workingPage = page
        let key = ObjectIdentifier(page)
        failed.remove(key)
        browser?.publish()

        page.callAsyncJavaScript("""
            if (document.readyState === 'loading') return null;
            return globalThis.__atmaPageTranslation?.collect(ticket, language);
            """, arguments: ["ticket": ticket.uuidString, "language": pair.source], in: nil, in: Self.world) { [weak self, weak page] result in
            guard let self, let page, self.job == ticket else { return }
            guard let payload = (try? result.get()) as? [String: Any],
                  let texts = payload["texts"] as? [String], !texts.isEmpty else {
                self.finish(ticket, applied: false)
                return
            }
            self.translate(texts, in: page, ticket: ticket, pair: pair)
        }
    }

    @available(iOS 18.0, *)
    private func translate(_ texts: [String], in page: WKWebView, ticket: UUID, pair: LanguagePair) {
        guard let browser else { cancel(); return }
        let view = TranslationTaskView(texts: texts, source: Locale.Language(identifier: pair.source),
                                       target: Locale.Language(identifier: pair.target)) { [weak self, weak page] results in
            guard let self, let page, self.job == ticket else { return }
            guard let results else {
                self.finish(ticket, applied: false)
                return
            }
            page.callAsyncJavaScript("return globalThis.__atmaPageTranslation?.apply(ticket, results) === true;",
                                     arguments: ["ticket": ticket.uuidString, "results": results], in: nil, in: Self.world) { [weak self] result in
                self?.finish(ticket, applied: (try? result.get()) as? Bool == true)
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

    private func finish(_ ticket: UUID, applied: Bool) {
        guard ticket == job, let page = workingPage else { return }
        let key = ObjectIdentifier(page)
        if applied { translated[key] = target }
        else { failed.insert(key) }
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
    let source: Locale.Language
    let target: Locale.Language
    let completion: @MainActor ([String]?) -> Void

    var body: some View {
        Color.clear.translationTask(source: source, target: target) { session in
            let requests = texts.map { TranslationSession.Request(sourceText: $0) }
            let results = try? await session.translations(from: requests)
            await completion(results?.map(\.targetText))
        }
    }
}
