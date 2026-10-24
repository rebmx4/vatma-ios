import Foundation
import Darwin

@main
enum UIResourceTests {
    static func main() {
        do {
            try containerAliasPreservesUIResources()
            print("PASS: UI resources load through a container symlink; child symlinks remain excluded")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func containerAliasPreservesUIResources() throws {
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? manager.removeItem(at: temporary) }
        let real = temporary.appendingPathComponent("container/BrowserUI", isDirectory: true)
        try manager.createDirectory(at: real.appendingPathComponent("assets", isDirectory: true), withIntermediateDirectories: true)
        try Data("<html>resource fixture</html>".utf8).write(to: real.appendingPathComponent("index.html"))
        try Data("fixture-script".utf8).write(to: real.appendingPathComponent("assets/app.js"))
        let outside = temporary.appendingPathComponent("outside.txt")
        try Data("must not be served".utf8).write(to: outside)
        try manager.createSymbolicLink(at: real.appendingPathComponent("escape.txt"), withDestinationURL: outside)
        let outsideDirectory = temporary.appendingPathComponent("outside-directory", isDirectory: true)
        try manager.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        try Data("must not be served either".utf8).write(to: outsideDirectory.appendingPathComponent("secret.js"))
        try manager.createSymbolicLink(at: real.appendingPathComponent("escape-directory", isDirectory: true), withDestinationURL: outsideDirectory)
        let alias = temporary.appendingPathComponent("container-alias", isDirectory: true)
        try manager.createSymbolicLink(at: alias, withDestinationURL: temporary.appendingPathComponent("container", isDirectory: true))

        let resources = try LocalUIServer.resourceIndex(at: alias.appendingPathComponent("BrowserUI", isDirectory: true))
        guard resources.keys.sorted() == ["assets/app.js", "index.html"] else {
            throw BrowserFailure.invalid("Unexpected UI resource keys: \(resources.keys.sorted())")
        }
        guard let index = resources["index.html"], let script = resources["assets/app.js"] else {
            throw BrowserFailure.invalid("The UI index and nested script must both be present.")
        }
        let html = try String(contentsOf: index, encoding: .utf8)
        let javascript = try String(contentsOf: script, encoding: .utf8)
        guard html == "<html>resource fixture</html>", javascript == "fixture-script" else {
            throw BrowserFailure.invalid("Unexpected fixture content: HTML=\(html), JavaScript=\(javascript)")
        }
    }
}
