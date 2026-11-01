import SwiftUI
import AppKit

@main
struct DisplayHandoffSetupApp: App {
    var body: some Scene {
        WindowGroup("Display Handoff") { SetupView().frame(minWidth: 720, minHeight: 620) }
            .windowResizability(.contentSize)
    }
}

struct SetupView: View {
    @State private var keyboard = true
    @State private var mouse = true
    @State private var notice = "先检查软件，再选择功能。安装前会保存本机备份。"
    @State private var isError = false
    @State private var confirmRestore = false
    @State private var confirmInstall = false
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var engine: MacSetup {
        MacSetup(config: home.appendingPathComponent(".hammerspoon"),
                 state: home.appendingPathComponent("Library/Application Support/Display Handoff Setup/current"),
                 payload: Bundle.main.resourceURL!.appendingPathComponent("mac"))
    }
    private func appURL(_ bundleID: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    private func open(_ url: String) { if let value = URL(string: url) { NSWorkspace.shared.open(value) } }
    private func run(_ action: () throws -> Void, success: String) {
        do { try action(); notice = success; isError = false }
        catch { notice = error.localizedDescription; isError = true }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                Image(systemName: "display.2").font(.system(size: 42)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 5) {
                    Text("把两台电脑，接成一套工作流。 ").font(.system(size: 25, weight: .semibold))
                    Text("DISPLAY HANDOFF  /  MAC 配置助手 · 实验版").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                mode("音乐键", left: "Windows", right: "Windows", symbol: "arrow.right")
                mode("邮件键", left: "Windows", right: "Mac", symbol: "arrow.left")
            }
            GroupBox("1  准备软件") {
                VStack(alignment: .leading, spacing: 12) {
                    dependency("Deskflow", bundleID: "org.deskflow.deskflow", download: "https://github.com/deskflow/deskflow/releases")
                    dependency("Hammerspoon", bundleID: "org.hammerspoon.Hammerspoon", download: "https://www.hammerspoon.org/go/")
                    Text("Deskflow 两端完成配对，Windows 为服务端；切屏联动请在 Windows 配置助手中安装。").font(.callout).foregroundStyle(.secondary)
                }.padding(8)
            }
            GroupBox("2  安装 Mac 功能") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Windows 风格 Ctrl 快捷键（排除终端与 iTerm）", isOn: $keyboard)
                    Toggle("鼠标侧键、Safari 横滚与窗口／桌面手势", isOn: $mouse)
                    Text("目标：~/.hammerspoon  ·  合并 init.lua，保留其他配置。\n若已有不同版本模块，本版会停止安装以保留自定义规则。").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("备份并安装所选功能") { confirmInstall = true }.buttonStyle(.borderedProminent).tint(.teal)
                        Button("打开 Hammerspoon") {
                            if let url = appURL("org.hammerspoon.Hammerspoon") { NSWorkspace.shared.open(url) }
                            else { notice = "请先安装 Hammerspoon。"; isError = true }
                        }
                    }
                }.padding(8)
            }
            HStack {
                Text("3  在 Hammerspoon 中 Reload Config，并按系统提示开启辅助功能。\n登录启动可在 Hammerspoon 偏好设置中开启。").font(.callout)
                Spacer()
                Button("打开辅助功能设置") { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }
            }
            Text(notice).font(.callout).foregroundStyle(isError ? Color.red : Color.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            HStack {
                Button("撤销本助手的安装…") { confirmRestore = true }
                Button("查看本机备份") { NSWorkspace.shared.open(engine.state.deletingLastPathComponent()) }
                Spacer()
                Button("使用说明") { open("https://github.com/YueyueBird-su/deskflow-display-handoff/blob/codex/setup-app/docs/APP.md") }
            }
        }
        .padding(28).frame(width: 740)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("安装所选 Mac 功能？", isPresented: $confirmInstall, titleVisibility: .visible) {
            Button("备份并安装") {
                run({
                    guard appURL("org.hammerspoon.Hammerspoon") != nil else { throw SetupFailure.message("请先安装 Hammerspoon。") }
                    try engine.install(keyboard: keyboard, mouse: mouse)
                }, success: "配置已安装并备份。请在 Hammerspoon 菜单选择 Reload Config，然后测试 Ctrl+C/V 和鼠标功能。")
            }
            Button("取消", role: .cancel) { }
        } message: { Text("将备份并合并 ~/.hammerspoon/init.lua，写入所选 Lua 模块。不会自动重新加载或修改系统权限。") }
        .confirmationDialog("恢复安装前的 Mac 配置？", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("恢复配置", role: .destructive) {
                run({ try engine.restore() }, success: "已恢复配置并保留备份。请在 Hammerspoon 中 Reload Config，使恢复生效。")
            }
            Button("取消", role: .cancel) { }
        } message: { Text("如果配置在安装后被编辑，助手会停止恢复，保留你的后续修改。") }
    }
    private func mode(_ key: String, left: String, right: String, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 6) {
                Text(key).font(.caption).foregroundStyle(.secondary)
                Text("\(left)  |  \(right)").font(.system(.body, design: .monospaced))
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
    private func dependency(_ name: String, bundleID: String, download: String) -> some View {
        HStack {
            Image(systemName: appURL(bundleID) == nil ? "circle.dashed" : "checkmark.circle.fill").foregroundStyle(.teal)
            Text(name)
            Spacer()
            Button(appURL(bundleID) == nil ? "前往官方下载" : "打开") {
                if let url = appURL(bundleID) { NSWorkspace.shared.open(url) } else { open(download) }
            }
        }
    }
}
