import XCTest

final class TransferSmoke: XCTestCase {
    func testStopRetryAndRemoveDownload() {
        let app = XCUIApplication()
        app.launchEnvironment["PHONE_DISK_FIXTURE"] = "1"
        app.launch()
        let download = app.links["Скачать файл для остановки"]
        XCTAssertTrue(download.waitForExistence(timeout:20))
        download.tap()
        app.buttons["Передача"].tap()
        let name = app.staticTexts["slow file +.bin"]
        XCTAssertTrue(name.waitForExistence(timeout:15))
        let stop = app.buttons["Остановить скачивание"]
        XCTAssertTrue(stop.waitForExistence(timeout:8))
        stop.tap()
        let stopped = app.staticTexts["Остановлено"]
        XCTAssertTrue(stopped.waitForExistence(timeout:15))
        app.buttons["Обновить передачи"].tap()
        XCTAssertTrue(stopped.exists)
        app.terminate()
        app.launch()
        let queue = app.buttons["Передача"]
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
        app.buttons["Передача"].tap()
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
        app.buttons["Передача"].tap()
        XCTAssertTrue(app.staticTexts["fixture-data.txt"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["ci-download.txt"].exists)
        XCTAssertEqual(completed.count,2)
    }
}
