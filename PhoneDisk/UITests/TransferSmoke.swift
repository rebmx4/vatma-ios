import XCTest

final class TransferSmoke: XCTestCase {
    func testStopRetryAndRemoveDownload() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PHONE_DISK_FIXTURE"] = "1"
        app.launch()
        let download = app.links["Скачать файл для остановки"]
        XCTAssertTrue(download.waitForExistence(timeout:45))
        let queue = app.buttons["queue-tab-transfers"]
        let filesTab = app.buttons["queue-tab-files"]
        let backupTab = app.buttons["queue-tab-backup"]
        let transfersTab = app.buttons["queue-tab-transfers"]
        let resumable = app.staticTexts["Fixture v2"].exists
        if !resumable { download.tap() }
        queue.tap()
        XCTAssertTrue(transfersTab.isSelected, app.debugDescription)
        let name = app.staticTexts["slow file +.bin"]
        XCTAssertTrue(name.waitForExistence(timeout:30), app.debugDescription)
        let stop = app.buttons["Остановить скачивание"]
        XCTAssertTrue(app.staticTexts["Скачивание"].waitForExistence(timeout:20))
        if resumable {
            let speed = app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@", "МБ/с")).firstMatch
            XCTAssertTrue(speed.waitForExistence(timeout:20))
        }
        XCTAssertTrue(filesTab.isHittable)
        XCTAssertTrue(backupTab.isHittable)
        XCTAssertTrue(transfersTab.isHittable)
        backupTab.tap()
        XCTAssertTrue(app.webViews.staticTexts["Настройки автокопий"].waitForExistence(timeout:20))
        queue.tap()
        XCTAssertTrue(name.waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["Скачивание"].exists)
        XCTAssertTrue(stop.waitForExistence(timeout:10))
        stop.tap()
        let stopped = app.staticTexts["Остановлено"]
        XCTAssertTrue(stopped.waitForExistence(timeout:15))
        filesTab.tap()
        XCTAssertTrue(download.waitForExistence(timeout:20))
        queue.tap()
        XCTAssertTrue(stopped.waitForExistence(timeout:15))
        filesTab.tap()
        XCTAssertTrue(download.waitForExistence(timeout:15))
        download.tap()
        XCTAssertTrue(stopped.waitForExistence(timeout:15))
        XCTAssertEqual(app.cells.containing(.staticText,identifier:"slow file +.bin").count,1)
        app.buttons["Обновить передачи"].tap()
        XCTAssertTrue(stopped.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(queue.waitForExistence(timeout:20))
        queue.tap()
        XCTAssertTrue(stopped.waitForExistence(timeout:15))
        app.buttons["Повторить скачивание"].tap()
        XCTAssertTrue(app.staticTexts["Готово"].waitForExistence(timeout:55))
        app.buttons["Удалить запись передачи"].tap()
        app.alerts.buttons["Нет"].tap()
        XCTAssertTrue(name.exists)
        app.buttons["Удалить запись передачи"].tap()
        app.alerts.buttons["Удалить"].tap()
        XCTAssertTrue(app.staticTexts["Передач пока нет"].waitForExistence(timeout:8))

        filesTab.tap()
        XCTAssertTrue(download.waitForExistence(timeout:10))
        let bulkNames = ["fixture-one.bin", "fixture-two.bin", "fixture-three.bin"]
        for filename in bulkNames {
            app.links[filename].tap()
        }
        queue.tap()
        for filename in bulkNames {
            XCTAssertTrue(app.cells.containing(.staticText,identifier:filename).firstMatch.waitForExistence(timeout:10))
        }
        let swipedRow = app.cells.containing(.staticText, identifier: bulkNames[2]).firstMatch
        swipedRow.swipeLeft()
        app.buttons["Удалить"].tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.staticTexts[bulkNames[2]].waitForExistence(timeout: 8), app.debugDescription)
        confirmation.buttons["Удалить"].tap()
        XCTAssertTrue(swipedRow.waitForNonExistence(timeout: 12), app.debugDescription)
        for remaining in bulkNames.prefix(2) {
            XCTAssertTrue(app.cells.containing(.staticText, identifier: remaining).firstMatch.exists)
        }

        app.buttons["Выбрать"].tap()
        XCTAssertTrue(filesTab.isHittable)
        XCTAssertTrue(backupTab.isHittable)
        let remove = app.buttons["Удалить выбранные передачи"]
        XCTAssertFalse(remove.isEnabled)
        app.buttons[bulkNames[0]].tap()
        app.buttons[bulkNames[1]].tap()
        XCTAssertTrue(remove.isEnabled)
        remove.tap()
        app.alerts.buttons["Удалить"].tap()
        XCTAssertTrue(app.staticTexts["Передач пока нет"].waitForExistence(timeout:8))
        XCTAssertTrue(transfersTab.isHittable)
        filesTab.tap()
        XCTAssertTrue(download.waitForExistence(timeout:10))
    }

    func testUploadDownloadAndPersistentQueue() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PHONE_DISK_FIXTURE"] = "1"
        app.launchEnvironment["PHONE_DISK_FIXTURE_PERSISTENCE"] = "1"
        app.launch()
        let attachment=app.buttons["Выбрать пробный файл"]
        XCTAssertTrue(attachment.waitForExistence(timeout:20))
        XCTAssertTrue(app.links["Скачать пробный файл"].waitForExistence(timeout: 20))
        let download = app.buttons["Запустить контрольное скачивание"]
        XCTAssertTrue(download.isHittable)
        download.tap()
        attachment.tap()
        app.buttons["queue-tab-transfers"].tap()
        XCTAssertTrue(app.staticTexts["fixture-data.txt"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["ci-download.txt"].waitForExistence(timeout:10), app.debugDescription)
        XCUIDevice.shared.press(.home)
        app.activate()
        let completed=app.staticTexts.matching(identifier:"Готово")
        let finished=NSPredicate{ _,_ in completed.count==2 }
        let completion = XCTNSPredicateExpectation(predicate: finished, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [completion], timeout: 60), .completed, app.debugDescription)
        XCTAssertTrue(app.staticTexts["ci-download.txt"].exists)
        app.terminate()
        app.launch()
        app.buttons["queue-tab-transfers"].tap()
        XCTAssertTrue(app.staticTexts["fixture-data.txt"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["ci-download.txt"].exists)
        XCTAssertEqual(completed.count,2)
    }
}
