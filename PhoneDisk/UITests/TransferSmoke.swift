import XCTest

final class TransferSmoke: XCTestCase {
    func testStopRetryAndRemoveDownload() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PHONE_DISK_FIXTURE"] = "1"
        app.launch()
        let download = app.links["Скачать файл для остановки"]
        XCTAssertTrue(download.waitForExistence(timeout:45))
        let startDownload = app.buttons["Запустить контрольное скачивание"]
        let queue = app.buttons["queue-tab-transfers"]
        let filesTab = app.buttons["queue-tab-files"]
        let backupTab = app.buttons["queue-tab-backup"]
        let transfersTab = app.buttons["queue-tab-transfers"]
        let resumable = app.staticTexts["Fixture v2"].exists
        startDownload.tap()
        queue.tap()
        XCTAssertTrue(transfersTab.waitForExistence(timeout:15))
        let name = app.staticTexts["slow file +.bin"]
        XCTAssertTrue(name.waitForExistence(timeout:15))
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
        startDownload.tap()
        Thread.sleep(forTimeInterval:1.3)
        startDownload.tap()
        Thread.sleep(forTimeInterval:1.3)
        startDownload.tap()
        queue.tap()
        let rows = app.cells.containing(.staticText,identifier:"slow file +.bin")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout:10))
        rows.firstMatch.swipeLeft()
        app.buttons["Удалить"].tap()
        app.alerts.buttons["Удалить"].tap()

        app.buttons["Выбрать"].tap()
        XCTAssertTrue(filesTab.isHittable)
        XCTAssertTrue(backupTab.isHittable)
        let entries = app.buttons.matching(identifier:"slow file +.bin")
        let remove = app.buttons["Удалить выбранные передачи"]
        XCTAssertFalse(remove.isEnabled)
        XCTAssertEqual(entries.count,2)
        entries.element(boundBy:0).tap()
        entries.element(boundBy:1).tap()
        XCTAssertTrue(remove.isEnabled)
        remove.tap()
        app.alerts.buttons["Удалить"].tap()
        XCTAssertTrue(app.staticTexts["Передач пока нет"].waitForExistence(timeout:8))
        XCTAssertTrue(transfersTab.isHittable)
        filesTab.tap()
        XCTAssertTrue(download.waitForExistence(timeout:10))
    }

    func testUploadDownloadAndPersistentQueue() throws {
        let app=XCUIApplication()
        app.launchEnvironment["PHONE_DISK_FIXTURE"]="1"
        app.launch()
        let attachment=app.buttons["Выбрать пробный файл"]
        XCTAssertTrue(attachment.waitForExistence(timeout:20))
        let download=app.links["Скачать пробный файл"]
        XCTAssertTrue(download.waitForExistence(timeout:20))
        download.tap()
        attachment.tap()
        app.buttons["queue-tab-transfers"].tap()
        XCTAssertTrue(app.staticTexts["fixture-data.txt"].waitForExistence(timeout:15))
        XCUIDevice.shared.press(.home)
        app.activate()
        let completed=app.staticTexts.matching(identifier:"Готово")
        let finished=NSPredicate{ _,_ in completed.count==2 }
        expectation(for:finished,evaluatedWith:app)
        waitForExpectations(timeout:60)
        XCTAssertTrue(app.staticTexts["ci-download.txt"].exists)
        app.terminate()
        app.launch()
        app.buttons["queue-tab-transfers"].tap()
        XCTAssertTrue(app.staticTexts["fixture-data.txt"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["ci-download.txt"].exists)
        XCTAssertEqual(completed.count,2)
    }
}
