import Foundation
import CryptoKit

enum SetupFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct SavedFile: Codable {
    let name: String
    let existed: Bool
    let beforeHash: String?
    let installedHash: String
}
struct Installation: Codable {
    let schema: Int
    let files: [SavedFile]
}

struct MacSetup {
    let config: URL
    let state: URL
    let payload: URL
    private let fm = FileManager.default
    static let begin = "-- BEGIN DISPLAY HANDOFF SETUP"
    static let end = "-- END DISPLAY HANDOFF SETUP"
    static let allowed = ["init.lua", "deskflow_keys.lua", "deskflow_mouse.lua"]

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func merge(_ original: String, keyboard: Bool, mouse: Bool) throws -> String {
        guard keyboard || mouse else { throw SetupFailure.message("请至少选择一项功能。") }
        let starts = original.components(separatedBy: begin).count - 1
        let ends = original.components(separatedBy: end).count - 1
        guard starts == ends, starts <= 1 else { throw SetupFailure.message("配置中存在不完整或重复的安装标记，请先检查 init.lua。") }
        var base = original
        if let a = base.range(of: begin), let b = base.range(of: end) {
            guard a.lowerBound < b.lowerBound else { throw SetupFailure.message("安装标记顺序错误。") }
            base.removeSubrange(a.lowerBound..<b.upperBound)
        }
        // Avoid double loading a module already required by a hand-written init.
        var imports: [String] = []
        for (enabled, module, variable) in [(keyboard, "deskflow_keys", "deskflowKeys"), (mouse, "deskflow_mouse", "deskflowMouse")] {
            guard enabled else { continue }
            let pattern = #"(?m)^[ \t]*(?:local[ \t]+)?(?:[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*)?require[ \t]*\(?[ \t]*["']"# + module + #"["']"#
            if base.range(of: pattern, options: .regularExpression) == nil {
                if base.contains(module) { throw SetupFailure.message("init.lua 已引用 \(module)，请先检查现有加载方式，避免重复。") }
                imports.append("\(variable) = require(\"\(module)\")")
            }
        }
        if imports.isEmpty { return base }
        return base + (base.isEmpty || base.hasSuffix("\n") ? "" : "\n") + begin + "\n" + imports.joined(separator: "\n") + "\n" + end + "\n"
    }
    private func rejectLink(_ url: URL) throws {
        if let attrs = try? fm.attributesOfItem(atPath: url.path), attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            throw SetupFailure.message("检测到符号链接，未改动：\(url.lastPathComponent)。请先检查自定义配置位置。")
        }
    }
    func install(keyboard: Bool, mouse: Bool) throws {
        try rejectLink(config); try rejectLink(state)
        guard !fm.fileExists(atPath: state.path) else { throw SetupFailure.message("已有安装记录。请先撤销本向导的安装，再重新选择功能。") }
        for name in Self.allowed { try rejectLink(config.appendingPathComponent(name)) }
        let initURL = config.appendingPathComponent("init.lua")
        let oldInit = fm.fileExists(atPath: initURL.path) ? try String(contentsOf: initURL, encoding: .utf8) : ""
        var files: [String: Data] = ["init.lua": Data(try Self.merge(oldInit, keyboard: keyboard, mouse: mouse).utf8)]
        for (enabled, name) in [(keyboard, "deskflow_keys.lua"), (mouse, "deskflow_mouse.lua")] {
            guard enabled else { continue }
            let data = try Data(contentsOf: payload.appendingPathComponent(name))
            let target = config.appendingPathComponent(name)
            if fm.fileExists(atPath: target.path), try Data(contentsOf: target) != data {
                throw SetupFailure.message("已有不同版本的 \(name)。为保留自定义规则，本版不会覆盖；请先迁移或备份原文件。")
            }
            files[name] = data
        }
        let backup = state.appendingPathComponent("backup", isDirectory: true)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        var record: [SavedFile] = []
        do {
            // Finish all backups before writing any configuration.
            for name in files.keys.sorted() {
                let target = config.appendingPathComponent(name)
                let existed = fm.fileExists(atPath: target.path)
                var before: String?
                if existed {
                    let data = try Data(contentsOf: target)
                    before = Self.hash(data)
                    try data.write(to: backup.appendingPathComponent(name), options: .atomic)
                }
                record.append(SavedFile(name: name, existed: existed, beforeHash: before, installedHash: Self.hash(files[name]!)))
            }
            try fm.createDirectory(at: config, withIntermediateDirectories: true)
            for entry in record {
                let target = config.appendingPathComponent(entry.name)
                let exists = fm.fileExists(atPath: target.path)
                let currentHash = exists ? Self.hash(try Data(contentsOf: target)) : nil
                guard exists == entry.existed, currentHash == entry.beforeHash else {
                    throw SetupFailure.message("配置在安装期间发生变化，已停止。")
                }
            }
            var written: [SavedFile] = []
            do {
                for entry in record {
                    try files[entry.name]!.write(to: config.appendingPathComponent(entry.name), options: .atomic)
                    written.append(entry)
                }
                let data = try JSONEncoder().encode(Installation(schema: 1, files: record))
                try data.write(to: state.appendingPathComponent("installation.json"), options: .atomic)
            } catch {
                for entry in written.reversed() { try restoreFile(entry, backup: backup) }
                throw error
            }
        } catch {
            try? fm.removeItem(at: state)
            throw error
        }
    }
    private func restoreFile(_ entry: SavedFile, backup: URL) throws {
        let target = config.appendingPathComponent(entry.name)
        if entry.existed {
            try Data(contentsOf: backup.appendingPathComponent(entry.name)).write(to: target, options: .atomic)
        } else if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
    }
    func restore() throws {
        try rejectLink(config);try rejectLink(state)
        let record = try JSONDecoder().decode(Installation.self, from: Data(contentsOf: state.appendingPathComponent("installation.json")))
        guard record.schema == 1, !record.files.isEmpty, Set(record.files.map(\.name)).count == record.files.count,
              record.files.allSatisfy({ Self.allowed.contains($0.name) }) else { throw SetupFailure.message("安装记录格式不受支持。") }
        let backup = state.appendingPathComponent("backup", isDirectory: true)
        try rejectLink(backup)
        for entry in record.files {
            let target = config.appendingPathComponent(entry.name)
            try rejectLink(target);try rejectLink(backup.appendingPathComponent(entry.name))
            let exists = fm.fileExists(atPath: target.path)
            let currentHash = exists ? Self.hash(try Data(contentsOf: target)) : nil
            let alreadyRestored = entry.existed ? currentHash == entry.beforeHash : !exists
            guard currentHash == entry.installedHash || alreadyRestored else {
                throw SetupFailure.message("\(entry.name) 在安装后被修改，未覆盖。请从本机备份合并恢复。")
            }
            if entry.existed, Self.hash(try Data(contentsOf: backup.appendingPathComponent(entry.name))) != entry.beforeHash {
                throw SetupFailure.message("备份校验失败，未改动配置。")
            }
        }
        // Keep a resumable journal: if restoration is interrupted, the backup survives.
        for entry in record.files { try restoreFile(entry, backup: backup) }
        let archive = state.deletingLastPathComponent().appendingPathComponent("restored-" + UUID().uuidString)
        try fm.moveItem(at: state, to: archive)
    }
}
