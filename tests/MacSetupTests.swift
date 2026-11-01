import Foundation

@main
struct MacSetupTests {
    static var assertions = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !condition() { throw SetupFailure.message("FAIL: " + message) }
    }
    static func rejects(_ action: () throws -> Void, _ message: String) throws {
        assertions += 1
        do { try action() } catch { return }
        throw SetupFailure.message("FAIL: accepted " + message)
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("handoff-test-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let payload = root.appendingPathComponent("payload")
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        for name in ["deskflow_keys.lua", "deskflow_mouse.lua"] { try Data(("-- fixture " + name).utf8).write(to: payload.appendingPathComponent(name)) }
        func engine(_ name: String) -> MacSetup {
            MacSetup(config: root.appendingPathComponent(name + "/config"), state: root.appendingPathComponent(name + "/state"), payload: payload)
        }
        let original = "-- user's config\nuserTimer = hs.timer.doEvery(60, function() end)\n"
        let merged = try MacSetup.merge(original, keyboard: true, mouse: true)
        try check(merged.hasPrefix(original), "preserve unrelated init content")
        try check(merged.components(separatedBy: "require(\"deskflow_keys\")").count == 2, "one keyboard import")
        let remerged = try MacSetup.merge(merged, keyboard: true, mouse: true)
        try check(remerged.components(separatedBy: MacSetup.begin).count == 2, "one managed block")
        let existing = "deskflowKeys = require('deskflow_keys')\n"
        try check(try MacSetup.merge(existing, keyboard: true, mouse: false) == existing, "do not duplicate legacy import")
        try rejects({ _ = try MacSetup.merge(MacSetup.begin, keyboard: true, mouse: true) }, "broken managed block")
        try rejects({ _ = try MacSetup.merge("", keyboard: false, mouse: false) }, "empty selection")
        try rejects({ _ = try MacSetup.merge("-- require('deskflow_keys')", keyboard: true, mouse: false) }, "commented import is not active")
        let fresh = engine("fresh")
        try fresh.install(keyboard: true, mouse: false)
        try check(fm.fileExists(atPath: fresh.config.appendingPathComponent("deskflow_keys.lua").path), "write selected module")
        try check(!fm.fileExists(atPath: fresh.config.appendingPathComponent("deskflow_mouse.lua").path), "omit unselected module")
        try rejects({ try fresh.install(keyboard: true, mouse: true) }, "overwrite existing installation")
        try fresh.restore()
        try check(!fm.fileExists(atPath: fresh.config.appendingPathComponent("init.lua").path), "restore absent init")
        let preserved = engine("preserved")
        try fm.createDirectory(at: preserved.config, withIntermediateDirectories: true)
        try Data(original.utf8).write(to: preserved.config.appendingPathComponent("init.lua"))
        try preserved.install(keyboard: true, mouse: true)
        try preserved.restore()
        try check(try String(contentsOf: preserved.config.appendingPathComponent("init.lua"), encoding: .utf8) == original, "byte-exact original init restore")
        let edited = engine("edited")
        try edited.install(keyboard: true, mouse: true)
        let change = Data("-- later user edit".utf8)
        try change.write(to: edited.config.appendingPathComponent("init.lua"))
        try rejects({ try edited.restore() }, "overwrite later user edits")
        try check(try Data(contentsOf: edited.config.appendingPathComponent("init.lua")) == change, "later edits survive rejected restore")
        let custom = engine("custom")
        try fm.createDirectory(at: custom.config, withIntermediateDirectories: true)
        try Data("-- custom keyboard rules".utf8).write(to: custom.config.appendingPathComponent("deskflow_keys.lua"))
        try rejects({ try custom.install(keyboard: true, mouse: false) }, "overwrite custom module")
        let corrupt = engine("corrupt")
        try fm.createDirectory(at: corrupt.config, withIntermediateDirectories: true)
        try Data(original.utf8).write(to: corrupt.config.appendingPathComponent("init.lua"))
        try corrupt.install(keyboard: true, mouse: false)
        try Data("bad backup".utf8).write(to: corrupt.state.appendingPathComponent("backup/init.lua"))
        try rejects({ try corrupt.restore() }, "corrupt backup")
        let symlink = engine("symlink")
        try fm.createDirectory(at: symlink.config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: symlink.config, withDestinationURL: preserved.config)
        try rejects({ try symlink.install(keyboard: true, mouse: false) }, "symbolic-link configuration")
        let interrupted = engine("interrupted")
        try interrupted.install(keyboard: true, mouse: true)
        try fm.removeItem(at: interrupted.config.appendingPathComponent("deskflow_keys.lua"))
        try interrupted.restore()
        try check(!fm.fileExists(atPath: interrupted.config.appendingPathComponent("init.lua").path), "resume interrupted restore")
        print("Mac setup: \(assertions) assertions passed; all filesystem writes used temporary fixtures.")
    }
}
