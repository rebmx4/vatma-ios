import XCTest
import WebKit
@testable import ATMA

@MainActor
final class BrowserPrivateDesktopTests: XCTestCase {
    func testShortcutRenameUsesFocusedFieldAndPersistsToDesktop() async throws {
        let fixture = try BrowserControllerFixture(); defer { fixture.close() }
        _ = try await fixture.start()
        let ui = try XCTUnwrap(fixture.controller.ui)
        try await fixture.wait("!!document.querySelector('#apps .app-tile')", in: ui)
        let changed = try await fixture.script("""
            const entries = JSON.parse(localStorage.getItem('atma-preview-apps'));
            const target = entries.find(item => item.url && item.dockSlot == null && item.type !== 'system');
            const tile = document.querySelector('#apps [data-app="' + target.id + '"] .app-tile');
            const touch = {bubbles:true, isPrimary:true, pointerId:1, button:0};
            const popup = new Promise(resolve => {
                const observer = new MutationObserver(() => {
                    const menu = document.querySelector('#shortcut-popup');
                    if (menu) { observer.disconnect(); resolve(menu); }
                });
                observer.observe(document.body, {childList:true});
            });
            tile.dispatchEvent(new PointerEvent('pointerdown', touch));
            const menu = await popup;
            tile.dispatchEvent(new PointerEvent('pointerup', touch));
            const action = [...menu.querySelectorAll('button')].find(button => /Rename|Переименовать/i.test(button.textContent));
            const previous = await window.webkit.messageHandlers.atma.postMessage({action:'state', body:{}});
            action.click();
            window.dispatchEvent(new CustomEvent('atma-native-state', {detail:previous}));
            const field = document.querySelector('#app-form [name=name]');
            if (document.activeElement !== field) return false;
            field.select();
            if (!document.execCommand('insertText', false, 'Gesture fixture')) return false;
            field.form.requestSubmit();
            return true;
            """, in: ui) as? Bool
        XCTAssertEqual(changed, true)
        try await fixture.wait("document.getElementById('overlay').hidden && JSON.parse(localStorage.getItem('atma-preview-apps')).some(item=>item.name==='Gesture fixture')", in: ui)
        _ = try await fixture.script("window.renameFixtureDocument = true; return true;", in: ui)
        ui.reload()
        try await fixture.wait("!window.renameFixtureDocument && [...document.querySelectorAll('#apps .app-name')].some(item=>item.textContent==='Gesture fixture')", in: ui)
    }

    func testDesktopPagerReachesScreenEdgesAndKeepsTheGridInsetAtRest() async throws {
        let fixture = try BrowserControllerFixture(); defer { fixture.close() }
        _ = try await fixture.start()
        let ui = try XCTUnwrap(fixture.controller.ui)
        _ = try await fixture.script("""
            const key = 'atma-preview-apps', entries = JSON.parse(localStorage.getItem(key));
            entries.push({id:'pager-fixture', name:'Page two', type:'web', url:'https://example.com/', slots:{4:20, 6:30}});
            const newValue = JSON.stringify(entries);
            localStorage.setItem(key, newValue);
            window.dispatchEvent(new StorageEvent('storage', {key, newValue}));
            return true;
            """, in: ui)
        try await fixture.wait("document.querySelectorAll('#apps .desktop-page').length >= 2", in: ui)
        let value = try await fixture.script("""
            const pager = document.getElementById('apps');
            const viewport = pager.getBoundingClientRect(), page = pager.firstElementChild;
            const inner = page.getBoundingClientRect(), gutter = getComputedStyle(page);
            return {left: viewport.left, right: viewport.right, screen: innerWidth, width: pager.clientWidth,
                    pageWidth: inner.width, leftGutter: parseFloat(gutter.paddingLeft),
                    rightGutter: parseFloat(gutter.paddingRight)};
            """, in: ui) as? [String: Double]
        let geometry = try XCTUnwrap(value)
        XCTAssertEqual(try XCTUnwrap(geometry["left"]), 0, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(geometry["right"]), try XCTUnwrap(geometry["screen"]), accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(geometry["pageWidth"]), try XCTUnwrap(geometry["width"]), accuracy: 1)
        XCTAssertGreaterThan(try XCTUnwrap(geometry["leftGutter"]), 0)
        XCTAssertEqual(try XCTUnwrap(geometry["leftGutter"]), try XCTUnwrap(geometry["rightGutter"]), accuracy: 1)
    }

    func testQuickAddFromPrivateDesktopStoresTheWebsiteOnlyInTheVault() async throws {
        let fixture = try BrowserControllerFixture(); defer { fixture.close() }
        let url = try await fixture.start().appendingPathComponent("a").absoluteString
        let ui = try XCTUnwrap(fixture.controller.ui)
        _ = try await fixture.rpc("open", body: ["url": url, "privateDesktop": true])
        XCTAssertEqual(fixture.controller.state()["privateDesktop"] as? Bool, true)
        try await fixture.wait("document.title === 'Page-a' && document.readyState === 'complete'",
                               in: XCTUnwrap(fixture.controller.currentRenderer))
        try await fixture.wait("!document.getElementById('pin-site').hidden && !document.getElementById('pin-site').disabled", in: ui)
        _ = try await fixture.script("document.getElementById('pin-site').click(); return true;", in: ui)
        try await fixture.wait("!!document.querySelector('[data-vault-choice=pin]')", in: ui)
        _ = try await fixture.script("document.querySelector('[data-vault-choice=pin]').click(); return true;", in: ui)
        let enterCode = """
            for (const digit of '123456') document.querySelector('[data-pin="' + digit + '"]').click();
            return true;
            """
        _ = try await fixture.script(enterCode, in: ui)
        try await fixture.wait("document.querySelector('.pin-keypad button[data-pin=\"1\"]')?.disabled === false", in: ui)
        _ = try await fixture.script(enterCode, in: ui)
        try await fixture.wait("document.getElementById('pin-site').dataset.saved === 'true'", in: ui)
        let saved = try await fixture.script("""
            const {openVault} = await import('/vault.js');
            const {items} = await openVault('123456', JSON.parse(localStorage.getItem('atma-preview-vault')));
            const ordinary = JSON.parse(localStorage.getItem('atma-preview-apps'));
            return {inVault: items.some(app => app.url === url),
                    onDesktop: ordinary.some(app => app.url === url), mode: document.body.dataset.mode};
            """, in: ui, arguments: ["url": url]) as? [String: Any]
        XCTAssertEqual(saved?["inVault"] as? Bool, true)
        XCTAssertEqual(saved?["onDesktop"] as? Bool, false)
        XCTAssertEqual(saved?["mode"] as? String, "browse")
    }
}
