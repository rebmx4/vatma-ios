import XCTest
import UIKit
import WebKit
@testable import ATMA

@MainActor
final class StoreGalleryCaptureTests: XCTestCase {
    func testCaptureLocalizedGallery() async throws {
        let fixture = try BrowserControllerFixture()
        defer { fixture.close() }
        _ = try await fixture.start()
        let controller = fixture.controller
        let ui = try XCTUnwrap(controller.ui)
        let window = try XCTUnwrap(controller.view.window)
        let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "playback", withExtension: "mp4"))
        let source = try Data(contentsOf: clip).base64EncodedString()
        let site = try BrowserRenderingFixtureServer(resources: [
            "/journal": Data(article(heading: "Quiet trails", intro: "A field guide to weekends outdoors.").utf8),
            "/atelier": Data(article(heading: "Un week-end au vert", intro: "Trois idées pour prendre l’air.", language: "fr").utf8),
            "/video": Data(article(heading: "Morning Light", intro: "", extra: "<video playsinline controls preload='auto' src='data:video/mp4;base64,\(source)'></video>").utf8)
        ])
        defer { site.stop() }
        let root = try await site.start()
        for language in ["en", "es", "fr", "pt-BR", "de", "it", "ru"] {
            _ = try await fixture.rpc("home")
            _ = try await fixture.rpc("panel", body: ["panel": "settings"])
            try await fixture.wait("!!document.getElementById('interface-language')", in: ui)
            _ = try await fixture.script("""
                const select = document.getElementById('interface-language');
                select.value = language; select.dispatchEvent(new Event('change', {bubbles:true}));
                return true;
                """, in: ui, arguments: ["language": language])
            try await fixture.wait("document.documentElement.lang === '\(language)'", in: ui)
            _ = try await fixture.rpc("panel", body: ["panel": "appearance"])
            try await fixture.wait("!!document.getElementById('theme-dark')", in: ui)
            _ = try await fixture.script("document.getElementById('theme-dark').click(); return true;", in: ui)
            try await fixture.wait("document.body.dataset.theme === 'dark'", in: ui)
            _ = try await fixture.rpc("panel", body: ["panel": NSNull()])
            try await fixture.wait("document.body.dataset.surface === 'home' && document.getElementById('overlay').hidden", in: ui)
            try await capture(window, language, "desktop")

            _ = try await fixture.script("document.querySelector('[data-app=atma-private-desktop] button').click(); return true;", in: ui)
            try await fixture.wait("!!document.querySelector('[data-vault-choice=pin]')", in: ui)
            try await capture(window, language, "privacy")
            _ = try await fixture.script("document.querySelector('[data-vault-choice=cancel]').click(); return true;", in: ui)
            try await fixture.wait("document.getElementById('overlay').hidden", in: ui)

            _ = try await fixture.rpc("tabs/new", body: ["privateBrowsing": true])
            try await fixture.wait("document.body.dataset.surface === 'incognito'", in: ui)
            _ = try await fixture.rpc("panel", body: ["panel": "private-device"])
            try await fixture.wait("document.getElementById('private-devices')?.children.length > 0", in: ui)
            try await capture(window, language, "incognito")
            _ = try await fixture.rpc("tabs/private/close")

            try await open(fixture, root.appendingPathComponent("journal"))
            try await capture(window, language, "clean")
            try await open(fixture, root.appendingPathComponent(language == "fr" ? "journal" : "atelier"))
            try await capture(window, language, "translation")

            try await open(fixture, root.appendingPathComponent("video"))
            let page = try XCTUnwrap(controller.currentRenderer)
            try await fixture.wait("document.querySelector('video')?.readyState >= 1 && !!window.__atmaMediaPage", in: page)
            _ = try await fixture.script("await window.__atmaMediaPage.command({type:'play'}); return true;", in: page)
            try await fixture.wait("document.querySelector('video').currentTime > 0.25", in: page)
            _ = try await fixture.rpc("panel", body: ["panel": "media"])
            try await fixture.wait("document.querySelector('.media-controls')?.hidden === false", in: ui)
            try await capture(window, language, "media")
        }
    }

    private func open(_ fixture: BrowserControllerFixture, _ url: URL) async throws {
        _ = try await fixture.rpc("open", body: ["url": url.absoluteString, "webApp": false])
        let page = try XCTUnwrap(fixture.controller.currentRenderer)
        try await fixture.wait("document.readyState === 'complete' && location.href === '\(url.absoluteString)' && !!document.querySelector('article')", in: page)
        try await fixture.wait("document.body.dataset.surface === 'site'", in: fixture.controller.ui)
    }

    private func capture(_ window: UIWindow, _ language: String, _ scene: String) async throws {
        try await Task.sleep(nanoseconds: 370_000_000)
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "gallery-\(language)-\(scene)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func article(heading: String, intro: String, language: String = "en", extra: String = "") -> String {
        """
        <!doctype html><html lang="\(language)"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1"><title>\(heading)</title>
        <style>
        *{box-sizing:border-box}body{margin:0;background:#f2eee6;color:#172925;font:16px Georgia,serif}
        article{max-width:730px;margin:auto;padding:24px 24px 48px}
        header{font:600 12px system-ui;letter-spacing:.16em;border-bottom:1px solid #b8bbad;padding-bottom:18px}
        h1{font-size:clamp(40px,9vw,71px);line-height:1;margin:28px 0 16px;letter-spacing:-.045em}
        p{font-size:20px;line-height:1.5;margin:0 0 25px}
        figure{margin:0 0 28px;border-radius:9px;height:clamp(220px,59vw,360px);background:
          radial-gradient(circle at 76% 27%,#facd87 0 7%, transparent 7.4%),
          linear-gradient(159deg,transparent 0 54%,#557872 54% 64%,transparent 64%),
          linear-gradient(25deg,#274942 0 34%,transparent 34%),
          linear-gradient(155deg,#bdc7aa,#e3bb8c)}
        video{width:100%;aspect-ratio:16/9;background:#111;border-radius:9px}
        h2{font-weight:400;font-size:30px;margin:12px 0 10px}.rule{height:1px;background:#b8bbad}
        </style></head><body><article><header>FIELD NOTES</header><h1>\(heading)</h1><p>\(intro)</p>
        \(extra.isEmpty ? "<figure></figure><div class='rule'></div><h2>\(language == "fr" ? "Une pause loin de la ville" : "Away from the city")</h2>" : extra)
        </article></body></html>
        """
    }
}
