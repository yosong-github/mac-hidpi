import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(systemName: model.isAnyEnabled ? "display.2" : "display")
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.displays.isEmpty {
            Text("没有检测到显示器")
        }
        ForEach(model.displays) { display in
            displaySection(display)
            Divider()
        }
        if model.isBusy {
            Text("正在切换…")
        }
        if let lastError = model.lastError, !lastError.isEmpty {
            Text(lastError)
            Button("清除错误") {
                model.lastError = nil
            }
            Divider()
        }
        Button("检查更新…") {
            model.checkForUpdates()
        }
        if !model.versionString.isEmpty {
            Text("版本 \(model.versionString)")
        }
        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private func displaySection(_ display: MenuDisplay) -> some View {
        let snapshot = display.snapshot
        Text(snapshot.name)
        Text("面板 \(snapshot.panel.width)×\(snapshot.panel.height)")
        if snapshot.isBuiltIn {
            Text("内建显示器，不在这里切换")
        } else if snapshot.isOurs {
            Text("这是 HiDPI 虚拟屏幕")
        } else if !snapshot.isEligible {
            Text("没有可用的 HiDPI 分辨率")
        } else {
            Text(model.resolutionLine(display))
            if let diagnostic = model.diagnosticLine(display) {
                Text(diagnostic)
            }
            Toggle(
                "高分辨率 (HiDPI)",
                isOn: Binding(
                    get: { display.isEnabled },
                    set: { model.setEnabled(display, $0) }
                )
            )
            .disabled(model.isBusy)
            if display.isEnabled {
                Menu("其他分辨率") {
                    ForEach(snapshot.presets) { mode in
                        Button(model.modeLabel(mode, on: snapshot)) {
                            model.select(display, mode: mode)
                        }
                        .disabled(model.isBusy)
                    }
                }
            }
        }
    }
}
