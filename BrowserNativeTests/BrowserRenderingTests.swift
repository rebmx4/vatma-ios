import XCTest
import UIKit
import WebKit
import Network
import AVFoundation
@testable import ATMA

@MainActor
final class BrowserRenderingTests: XCTestCase {
    private var controller: BrowserController!
    private var window: UIWindow!
    private var preferences: UserDefaults!
    private var suite: String!
    private var savedPort: Any?
    private var fixture: BrowserRenderingFixtureServer!

    override func setUpWithError() throws {
        suite = "atma.tests.rendering." + UUID().uuidString
        preferences = UserDefaults(suiteName: suite)!
        // The hosted app already owns its listener. Give this test controller
        // a separate loopback origin instead of trying to bind that same port.
        savedPort = UserDefaults.standard.object(forKey: "atma.ui.loopback.port")
        UserDefaults.standard.removeObject(forKey: "atma.ui.loopback.port")
        controller = BrowserController(model: BrowserModel(defaults: preferences))
        window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
    }

    override func tearDownWithError() throws {
        fixture?.stop()
        for page in controller.renderers.values {
            controller.media.unregister(page)
            page.stopLoading()
        }
        controller.ui.stopLoading()
        controller.ui.configuration.userContentController.removeScriptMessageHandler(forName: "atma", contentWorld: .page)
        window.isHidden = true
        window.rootViewController = nil
        window = nil
        controller = nil
        if let savedPort { UserDefaults.standard.set(savedPort, forKey: "atma.ui.loopback.port") }
        else { UserDefaults.standard.removeObject(forKey: "atma.ui.loopback.port") }
        preferences.removePersistentDomain(forName: suite)
        preferences = nil
    }

    func testPlaybackContinuesAcrossPeriodicNativeMediaStateReports() async throws {
        let page = try await openVideo()
        let startValue = try await script("return document.querySelector('video').currentTime;", in: page)
        let start = try XCTUnwrap(startValue as? Double)
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let statusValue = try await script("const v=document.querySelector('video'); return {paused:v.paused,time:v.currentTime};", in: page)
        let status = try XCTUnwrap(statusValue as? [String: Any])
        XCTAssertEqual(status["paused"] as? Bool, false, "State reporting must not stop the website's player")
        XCTAssertGreaterThan(try XCTUnwrap(status["time"] as? Double), start + 2)
    }

    func testPassiveInterruptionNoticeDoesNotManufactureAJavaScriptPause() async throws {
        let page = try await openVideo()
        // This notification deliberately does not interrupt WebKit's player.
        // WebKit owns actual system interruptions; an observer must not create
        // an additional delayed pause command from a passive notification.
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(nanoseconds: 800_000_000)
        let paused = try await script("return document.querySelector('video').paused;", in: page) as? Bool
        XCTAssertEqual(paused, false, "The browser must not enqueue a second page pause from an audio-session notice")
    }

    func testUnrequestedVideoDoesNotStartAndExplicitPlayStillWorks() async throws {
        let url = try await startFixture(video: true)
        try controller.open(url.appendingPathComponent("video-autoplay").absoluteString)
        let page = try XCTUnwrap(controller.currentRenderer)
        try await waitFor("document.querySelector('video')?.readyState>=1 && !!window.__atmaMediaPage", in: page)
        _ = try await script("await document.querySelector('video').play().catch(()=>{}); return true;", in: page)
        let paused = try await script("return document.querySelector('video').paused;", in: page) as? Bool
        XCTAssertEqual(paused, true, "The site must not start audio without a playback request")
        _ = try await script("await window.__atmaMediaPage.command({type:'play'}); return true;", in: page)
        try await waitFor("document.querySelector('video').currentTime>0.3 && !document.querySelector('video').paused", in: page)
    }

    func testMediaPanelSettingsDoNotLeaveTheNextVisibleDocumentHidden() async throws {
        let url = try await startFixture(video: true).appendingPathComponent("video").absoluteString
        try await waitForUI()
        _ = try await rpc("open", body: ["url": url, "webApp": false])
        let page = try XCTUnwrap(controller.currentRenderer)
        try await waitFor("document.readyState==='complete' && !!window.__atmaMediaPage", in: page)
        let background = BrowserPageScripts.backgroundEnabled
        defer { controller.media.setBackground(background) }
        _ = try await rpc("panel", body: ["panel": "media"])
        controller.view.layoutIfNeeded()
        controller.media.setBackground(!background)
        _ = try await rpc("panel", body: [:])
        controller.view.layoutIfNeeded()
        _ = try await script("window.__mediaPreviousDocument=true; return true;", in: page)
        page.reload()
        try await waitFor("window.__mediaPreviousDocument!==true && document.readyState==='complete' && document.querySelector('video')?.readyState>=1 && !!window.__atmaMediaPage", in: page)
        // Read the actual native-to-document visibility update. A native JS
        // evaluation itself forces activation, so it cannot stand in for input.
        try await waitFor("window.__fixturePageVisible===true", in: page)
        _ = try await script("await window.__atmaMediaPage.command({type:'play'}); return true;", in: page)
        try await waitFor("document.querySelector('video').currentTime>0.3 && !document.querySelector('video').paused", in: page)
    }

    func testLeavingAnInlineVideoStopsItAndRejectsAnAutomaticRestart() async throws {
        let page = try await openVideo()
        try await waitForUI()
        _ = try await rpc("home")
        try await waitFor("document.querySelector('video').paused", in: page)
        _ = try await script("await document.querySelector('video').play().catch(()=>{}); return true;", in: page)
        let paused = try await script("return document.querySelector('video').paused;", in: page) as? Bool
        XCTAssertEqual(paused, true, "A hidden website must not undo the browser's pause")
    }

    func testOverviewShowsBothVisitedPagesInsteadOfSnapshotsOfHiddenRenderers() async throws {
        let url = try await startFixture(video: false)
        try await waitForUI()
        try controller.open(url.appendingPathComponent("red").absoluteString)
        let redID = controller.model.activeTabId
        try await waitForPaint(in: XCTUnwrap(controller.currentRenderer), color: "rgb(220, 38, 40)")
        _ = try await rpc("tabs/new")
        try controller.open(url.appendingPathComponent("blue").absoluteString)
        let blueID = controller.model.activeTabId
        try await waitForPaint(in: XCTUnwrap(controller.currentRenderer), color: "rgb(30, 70, 220)")
        // Use the production button path: renderTabs requests previews before
        // setPanel sends its native panel RPC.
        _ = try await script("document.getElementById('tabs-button').click(); return true;", in: controller.ui)
        try await waitFor("document.querySelectorAll('.tab-shot').length===2 && [...document.querySelectorAll('.tab-shot')].every(image=>image.complete && image.naturalWidth>0)", in: controller.ui)
        let imagesValue = try await script("return Object.fromEntries([...document.querySelectorAll('.tab-card')].map(card=>[card.dataset.tabId,card.querySelector('.tab-shot')?.src]));", in: controller.ui)
        let images = try XCTUnwrap(imagesValue as? [String: String])
        let red = try averageRGB(try XCTUnwrap(images[redID]))
        let blue = try averageRGB(try XCTUnwrap(images[blueID]))
        XCTAssertGreaterThan(red[0], 150); XCTAssertLessThan(red[1], 110)
        XCTAssertGreaterThan(blue[2], 150); XCTAssertLessThan(blue[0], 110)
        _ = try await script("window.__originalTabCard=document.querySelector('.tab-card'); return true;", in: controller.ui)
        for _ in 0..<5 { controller.publish() }
        try await Task.sleep(nanoseconds: 500_000_000)
        let preserved = try await script("return window.__originalTabCard===document.querySelector('.tab-card');", in: controller.ui) as? Bool
        XCTAssertEqual(preserved, true, "Native state reports must preserve the displayed tab card")
    }

    func testShortcutKeepsItsProfileAndCompactToolbarWithoutReloadingTheWebsite() async throws {
        let url = try await startFixture(video: false).appendingPathComponent("red").absoluteString
        try await waitForUI()
        let pinned = try XCTUnwrap(controller.model.profiles.compactMap { $0["id"] as? String }.first { $0 != BrowserModel.actualProfile })
        _ = try await rpc("open", body: ["url": url, "profileId": pinned, "webApp": true])
        let page = try XCTUnwrap(controller.currentRenderer)
        try await waitForPaint(in: page, color: "rgb(220, 38, 40)")
        XCTAssertEqual(controller.model.active.profileId, pinned)
        XCTAssertTrue(page.configuration.websiteDataStore === controller.model.store(for: pinned))
        try await waitFor("document.body.dataset.webApp==='true' && document.body.dataset.controlsCollapsed==='false' && document.getElementById('address').getBoundingClientRect().height>0", in: controller.ui)
        controller.view.layoutIfNeeded()
        let compactHeight = controller.ui.frame.height
        XCTAssertLessThan(compactHeight, 90)
        _ = try await script("window.__retainedPage='same document'; return true;", in: page)
        _ = try await rpc("chrome", body: ["collapsed": true])
        try await waitFor("document.body.dataset.controlsCollapsed==='false' && document.getElementById('address').getBoundingClientRect().height>0 && getComputedStyle(document.querySelector('.device-row')).display==='none'", in: controller.ui)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.ui.frame.height, compactHeight, accuracy: 1, "Saved apps must always retain their thin address toolbar")
        XCTAssertTrue(controller.currentRenderer === page)
        let marker = try await script("return window.__retainedPage;", in: page) as? String
        XCTAssertEqual(marker, "same document", "Chrome actions must not reload or replace the website")
        let homeAtRight = try await script("return document.getElementById('go-home').getBoundingClientRect().left > document.getElementById('address-form').getBoundingClientRect().right;", in: controller.ui) as? Bool
        XCTAssertEqual(homeAtRight, true)
        _ = try await rpc("home")
        _ = try await rpc("profile", body: ["profileId": BrowserModel.actualProfile])
        _ = try await rpc("open", body: ["url": url, "profileId": pinned, "webApp": true])
        XCTAssertEqual(controller.model.active.profileId, pinned, "A later global profile choice must not override a pinned shortcut")
        XCTAssertTrue(controller.currentRenderer?.configuration.websiteDataStore === controller.model.store(for: pinned))
    }

    func testNormalBrowserCanHideOnlyTheDeviceRowAtThePhysicalBottom() async throws {
        let url = try await startFixture(video: false).appendingPathComponent("blue").absoluteString
        try await waitForUI()
        _ = try await rpc("open", body: ["url": url, "webApp": false])
        let page = try XCTUnwrap(controller.currentRenderer)
        try await waitForPaint(in: page, color: "rgb(30, 70, 220)")
        controller.view.layoutIfNeeded()
        let fullHeight = page.frame.height
        let bottom = controller.ui.convert(controller.ui.bounds, to: controller.view).maxY
        XCTAssertEqual(bottom, controller.view.bounds.maxY, accuracy: 1, "Closed-keyboard chrome must use the physical bottom edge")
        _ = try await rpc("chrome", body: ["collapsed": true])
        try await waitFor("document.body.dataset.webApp==='false' && document.body.dataset.controlsCollapsed==='true' && document.getElementById('address').getBoundingClientRect().height>0 && document.getElementById('go-home').getBoundingClientRect().height>0 && document.getElementById('device-picker').getBoundingClientRect().height===0", in: controller.ui)
        controller.view.layoutIfNeeded()
        XCTAssertGreaterThan(page.frame.height, fullHeight + 25)
        XCTAssertTrue(controller.currentRenderer === page)
        _ = try await rpc("chrome", body: ["collapsed": false])
        try await waitFor("document.getElementById('device-picker').getBoundingClientRect().height>0", in: controller.ui)
        _ = try await script("window.__modeChanges=[]; window.__modeObserver=new MutationObserver(()=>window.__modeChanges.push(document.body.dataset.mode)); window.__modeObserver.observe(document.body,{attributes:true,attributeFilter:['data-mode']}); document.getElementById('pin-site').click(); return true;", in: controller.ui)
        try await waitFor("document.getElementById('pin-site').dataset.saved==='true'", in: controller.ui)
        let stableMode = try await script("window.__modeObserver.disconnect(); return document.body.dataset.mode==='browse' && window.__modeChanges.every(mode=>mode==='browse');", in: controller.ui) as? Bool
        XCTAssertEqual(stableMode, true, "Quick-add metadata is not a full native state and must not replace it")
        let savedProfile = try await script("window.__savedShortcutURL=url; return JSON.parse(localStorage.getItem('atma-preview-apps')).find(app=>app.url===url)?.profileId;", in: controller.ui, arguments: ["url": url]) as? String
        XCTAssertEqual(savedProfile, controller.model.active.profileId)
        _ = try await script("document.getElementById('go-home').click(); return true;", in: controller.ui)
        try await waitFor("document.body.dataset.mode==='home' && innerHeight>300 && (()=>{const app=JSON.parse(localStorage.getItem('atma-preview-apps')).find(app=>app.url===window.__savedShortcutURL); const tile=document.querySelector('[data-app=\"'+app.id+'\"] button').getBoundingClientRect(); const desktop=document.getElementById('apps').getBoundingClientRect(); return tile.width>0 && tile.left>=desktop.left && tile.right<=desktop.right && tile.top>=desktop.top && tile.bottom<=desktop.bottom;})()", in: controller.ui)
    }

    func testPopupTransitionCapturesItsVisibleOpener() async throws {
        let url = try await startFixture(video: false)
        try await waitForUI()
        try controller.open(url.appendingPathComponent("red").absoluteString)
        let openerID = controller.model.activeTabId
        let opener = try XCTUnwrap(controller.currentRenderer)
        try await waitForPaint(in: opener, color: "rgb(220, 38, 40)")
        let popup = try controller.createSiteWindow(from: opener, configuration: WKWebViewConfiguration(), url: url.appendingPathComponent("blue"))
        let deadline = Date().addingTimeInterval(5)
        while controller.currentRenderer !== popup && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertTrue(controller.currentRenderer === popup)
        popup.load(URLRequest(url: url.appendingPathComponent("blue")))
        try await waitForPaint(in: popup, color: "rgb(30, 70, 220)")
        _ = try await script("document.getElementById('tabs-button').click(); return true;", in: controller.ui)
        try await waitFor("document.querySelectorAll('.tab-shot').length===2 && [...document.querySelectorAll('.tab-shot')].every(image=>image.complete && image.naturalWidth>0)", in: controller.ui)
        let imagesValue = try await script("return Object.fromEntries([...document.querySelectorAll('.tab-card')].map(card=>[card.dataset.tabId,card.querySelector('.tab-shot')?.src]));", in: controller.ui)
        let images = try XCTUnwrap(imagesValue as? [String: String])
        let red = try averageRGB(try XCTUnwrap(images[openerID]))
        XCTAssertGreaterThan(red[0], 150); XCTAssertLessThan(red[1], 110)
    }

    func testQuickAddedWebsiteStoresItsDeclaredIconAndKeepsItOffline() async throws {
        let url = try await startFixture(video: false).appendingPathComponent("red").absoluteString
        try await waitForUI()
        _ = try await rpc("open", body: ["url": url, "webApp": false])
        try await waitForPaint(in: XCTUnwrap(controller.currentRenderer), color: "rgb(220, 38, 40)")
        _ = try await script("document.getElementById('pin-site').click(); return true;", in: controller.ui)
        try await waitFor("JSON.parse(localStorage.getItem('atma-preview-apps')).some(app=>app.url===\(jsonString(url)) && app.iconUrl?.startsWith('data:image/png;base64,'))", in: controller.ui)
        _ = try await rpc("home")
        let stored = try await script("return JSON.parse(localStorage.getItem('atma-preview-apps')).find(app=>app.url===url)?.iconUrl;", in: controller.ui, arguments: ["url": url]) as? String
        let pixel = try averageRGB(XCTUnwrap(stored))
        XCTAssertGreaterThan(pixel[1], 160); XCTAssertLessThan(pixel[0], 90)
        fixture.stop()
        _ = try await script("window.__iconPreviousDocument=true; return true;", in: controller.ui)
        controller.ui.reload()
        try await waitFor("window.__iconPreviousDocument!==true && document.readyState==='complete' && !!document.body.dataset.mode", in: controller.ui)
        try await waitFor("[...document.querySelectorAll('.app-item')].some(item=>item.querySelector('img')?.naturalWidth===192)", in: controller.ui)
        let reloaded = try await script("return JSON.parse(localStorage.getItem('atma-preview-apps')).find(app=>app.url===url)?.iconUrl;", in: controller.ui, arguments: ["url": url]) as? String
        XCTAssertEqual(reloaded, stored, "Saved artwork must survive a fresh UI document without the website")
    }

    func testManualShortcutUsesManifestFallbackAndRepairsAnOldMissingIcon() async throws {
        let url = try await startFixture(video: false).appendingPathComponent("manifest-only").absoluteString
        try await waitForUI()
        _ = try await script("document.getElementById('settings').click(); return true;", in: controller.ui)
        try await waitFor("!!document.getElementById('add-desktop-app')", in: controller.ui)
        _ = try await script("document.getElementById('add-desktop-app').click(); return true;", in: controller.ui)
        try await waitFor("!!document.getElementById('app-form')", in: controller.ui)
        _ = try await script("const form=document.getElementById('app-form'); form.elements.name.value='Manual icon fixture'; form.elements.url.value=url; form.requestSubmit(); return true;", in: controller.ui, arguments: ["url": url])
        let saved = "JSON.parse(localStorage.getItem('atma-preview-apps')).find(app=>app.name==='Manual icon fixture')"
        try await waitFor("\(saved)?.iconUrl?.startsWith('data:image/png;base64,')", in: controller.ui)
        let icon = try await script("return \(saved).iconUrl;", in: controller.ui) as? String
        let pixel = try averageRGB(XCTUnwrap(icon))
        XCTAssertGreaterThan(pixel[1], 160); XCTAssertLessThan(pixel[0], 90)
        _ = try await script("const apps=JSON.parse(localStorage.getItem('atma-preview-apps')); delete apps.find(app=>app.name==='Manual icon fixture').iconUrl; localStorage.setItem('atma-preview-apps',JSON.stringify(apps)); return true;", in: controller.ui)
        controller.ui.reload()
        try await waitForUI()
        try await waitFor("\(saved)?.iconUrl?.startsWith('data:image/png;base64,')", in: controller.ui)
        let repaired = try await script("return \(saved).iconUrl;", in: controller.ui) as? String
        XCTAssertEqual(repaired, icon, "Previously created shortcuts must recover their website artwork")
    }

    private func jsonString(_ value: String) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: [value]), encoding: .utf8)!.dropFirst().dropLast().description
    }

    private func openVideo() async throws -> WKWebView {
        let url = try await startFixture(video: true)
        try controller.open(url.appendingPathComponent("video").absoluteString)
        let page = try XCTUnwrap(controller.currentRenderer)
        try await waitFor("document.querySelector('video')?.readyState>=1 && !!window.__atmaMediaPage", in: page)
        _ = try await script("await window.__atmaMediaPage.command({type:'play'}); return true;", in: page)
        try await waitFor("document.querySelector('video').currentTime>0.3 && !document.querySelector('video').paused", in: page)
        XCTAssertEqual(controller.media.state["available"] as? Bool, true, "The real production media bridge must own the playing page")
        return page
    }

    private func startFixture(video: Bool) async throws -> URL {
        var resources: [String: Data] = [:]
        for (path, color) in [("/red", "rgb(220,38,40)"), ("/blue", "rgb(30,70,220)")] {
            resources[path] = Data("<!doctype html><html><head><title>\(path) fixture</title><link rel='apple-touch-icon' href='/art/site.png'><style>html,body{margin:0;width:100%;height:100%;background:\(color)}</style></head><body></body></html>".utf8)
        }
        let artwork = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).pngData { context in
            context.cgContext.setFillColor(UIColor(red: 0.1, green: 0.85, blue: 0.2, alpha: 1).cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        resources["/art/site.png"] = artwork
        resources["/manifest/icons/logo.png"] = artwork
        resources["/manifest-only"] = Data("<!doctype html><html><head><title>Manifest fixture</title><link rel='apple-touch-icon' href='/missing.png'><link rel='manifest' href='/manifest/app.json'></head><body>Manifest icon</body></html>".utf8)
        resources["/manifest/app.json"] = Data(#"{"icons":[{"src":"icons/logo.png","sizes":"192x192","type":"image/png"}]}"#.utf8)
        if video {
            let bundle = Bundle(for: BrowserRenderingTests.self)
            let mediaURL = try XCTUnwrap(bundle.url(forResource: "playback", withExtension: "mp4"))
            let media = try Data(contentsOf: mediaURL).base64EncodedString()
            let videoPage = "<!doctype html><html><head><title>Playback fixture</title><script>const setVisible=window.__atmaMediaPage.setPageVisible;window.__atmaMediaPage.setPageVisible=visible=>{window.__fixturePageVisible=visible;return setVisible(visible);};</script></head><body><video playsinline controls preload='auto' width='320' height='180' src='data:video/mp4;base64,\(media)'></video></body></html>"
            resources["/video"] = Data(videoPage.utf8)
            resources["/video-autoplay"] = Data(videoPage.replacingOccurrences(of: "<video playsinline controls ", with: "<video playsinline controls autoplay ").utf8)
        }
        fixture = try BrowserRenderingFixtureServer(resources: resources)
        return try await fixture.start()
    }

    private func waitForUI() async throws {
        try await waitFor("!!document.getElementById('go-home') && !!document.body.dataset.mode", in: controller.ui)
    }

    private func waitForPaint(in page: WKWebView, color: String) async throws {
        let encoded = String(data: try JSONSerialization.data(withJSONObject: [color]), encoding: .utf8)!
        try await waitFor("document.readyState==='complete' && getComputedStyle(document.body).backgroundColor===\(encoded)[0]", in: page)
        _ = try await script("await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))); return true;", in: page)
    }

    private func waitFor(_ expression: String, in page: WKWebView) async throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if (try? await script("return Boolean(\(expression));", in: page)) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let details = try? await script("""
            const rect = element => element ? element.getBoundingClientRect().toJSON() : null;
            const v = document.querySelector('video'), desktop = document.getElementById('apps');
            return JSON.stringify({url:location.href,ready:document.readyState,mediaBridge:!!window.__atmaMediaPage,
              video:v?{ready:v.readyState,network:v.networkState,paused:v.paused,time:v.currentTime,error:v.error?.code}:null,
              viewport:{width:innerWidth,height:innerHeight},mode:document.body.dataset.mode,surface:document.body.dataset.surface,
              desktop:{rect:rect(desktop),scrollLeft:desktop?.scrollLeft,pages:desktop?.children.length},
              tiles:[...document.querySelectorAll('.app-item')].slice(0,24).map(item=>({id:item.dataset.app,rect:rect(item.querySelector('button'))}))});
            """, in: page)
        XCTFail("Fixture condition timed out: \(expression); details: \(String(describing: details))")
        throw NSError(domain: "ATMA.RenderingFixture", code: 1)
    }

    private func script(_ source: String, in page: WKWebView, arguments: [String: Any] = [:]) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            page.callAsyncJavaScript(source, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    private func rpc(_ action: String, body: [String: Any] = [:]) async throws -> Any? {
        try await script("return await window.webkit.messageHandlers.atma.postMessage({action,body});", in: controller.ui, arguments: ["action": action, "body": body])
    }

    private func averageRGB(_ source: String) throws -> [UInt8] {
        let encoded = try XCTUnwrap(source.split(separator: ",", maxSplits: 1).last)
        let bytes = try XCTUnwrap(Data(base64Encoded: String(encoded)))
        let image = try XCTUnwrap(UIImage(data: bytes)?.cgImage)
        var pixel: [UInt8] = [0, 0, 0, 0]
        try pixel.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel
    }
}
