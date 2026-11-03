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
            Toggle(
                "启用 HiDPI",
                isOn: Binding(
                    get: { display.isEnabled },
                    set: { model.setEnabled(display, $0) }
                )
            )
            .disabled(model.isBusy)
            if display.isEnabled,
                let current = display.activeMode ?? snapshot.defaultMode ?? snapshot.presets.first
            {
                Picker(
                    "分辨率",
                    selection: Binding(
                        get: {
                            display.activeMode ?? snapshot.defaultMode ?? snapshot.presets.first ?? current
                        },
                        set: { model.select(display, mode: $0) }
                    )
                ) {
                    ForEach(snapshot.presets) { mode in
                        Text(model.modeLabel(mode, on: snapshot)).tag(mode)
                    }
                }
                .disabled(model.isBusy)
                if let active = display.activeMode {
                    Text("渲染 \(active.pixelWidth)×\(active.pixelHeight)")
                }
            }
        }
    }
}
