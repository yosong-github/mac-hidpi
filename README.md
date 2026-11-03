# HiDPI

菜单栏小工具。给外接 2K 显示器打开系统级 HiDPI：整个桌面（所有窗口、图标、图像，不只是文字）按 2× 绘制，看起来像的分辨率仍停在原生尺寸。

没有 Dock 图标（`LSUIElement`）。点菜单栏显示器图标即可开关，并选择一套按 2× 渲染的逻辑分辨率。

## 它在做什么

打开「高分辨率 (HiDPI)」后，菜单里的分辨率仍是 2560 × 1440，图标和窗口的视觉大小不变。虚拟屏的整块桌面改在 5120×2880 上绘制，再整幅缩小到 2560×1440 面板上，所以每个应用都更清楚。这不是字体平滑，也不是单个窗口的滤镜。更小的「看起来像」尺寸仍可在「其他分辨率」里选，但不是默认。

2560×1440（16:9）上的预设：

| 看起来像 | 实际渲染 | 说明 |
| --- | --- | --- |
| 2560×1440 | 5120×2880 | 默认。打开 HiDPI 时用这一档 |
| 2048×1152 | 4096×2304 | 可选，空间更多 |
| 1920×1080 | 3840×2160 | 可选 |
| 1706×960 | 3412×1920 | 可选，面板的 2/3 |
| 1600×900 | 3200×1800 | 可选 |
| 1280×720 | 2560×1440 | 可选，与面板像素对齐 |

其它比例的屏幕用同一组比例（1/1、4/5、3/4、2/3、5/8、1/2）生成，并保持宽高比。帧缓冲上限 7680×4320，放不下 2× 原生尺寸时默认用不超过上限的最大一档。

## 方案

采用和 [BetterDisplay](https://github.com/waydabber/BetterDisplay) 的虚拟屏幕镜像同一类做法，不写显示器覆盖 plist：

1. 用私有 API `CGVirtualDisplay` 建一块 HiDPI 虚拟屏。默认请求逻辑点尺寸 2560×1440、`maxPixels` 5120×2880、`hiDPI = 1`。模式选择只接受点尺寸等于请求值且像素正好是 2 倍的模式，1× 的 2560×1440 不会被选中。
2. 若系统没有露出对应的 2× 模式，再试一次：把模式尺寸直接设成帧缓冲大小。
3. 用 `CGConfigureDisplayMirrorOfDisplay` 让物理外接屏镜像这块虚拟屏。macOS 把整个桌面画进虚拟屏的 2× 帧缓冲，面板只负责显示缩小后的整幅画面。
4. 退出菜单里的「退出」会先取消镜像，再释放虚拟屏。进程被强制结束后，虚拟屏会随进程消失，镜像有可能要拔插一次显示器才恢复。

不需要管理员密码，不改 SIP，不用重启。虚拟屏对象必须留在进程里，所以应用要一直开着。

### 为什么不用 `/Library/Displays/.../Overrides`

覆盖 plist 能让系统设置里直接出现 HiDPI 分辨率，也没有镜像那一层。但要往 `/Library/Displays/Contents/Resources/Overrides` 写文件（管理员权限），并且通常要重新插拔显示器、注销或重启才生效。Intel 上的较新 macOS 还有报告说已经不再读取这个目录。这和「菜单里马上开关」对不上，所以没有走这条路。

覆盖方案在 Apple Silicon 上、并且可以接受重启时，仍然更省 GPU。本应用的代价是多一块帧缓冲、镜像带来的一点延迟，以及私有 API 可能在未来系统上失效。

## 系统要求

- macOS 13 或更新
- Apple Silicon 与 Intel（发布包是通用二进制）
- 外接显示器。内建屏幕只列出来，不能在这里开关

开关 HiDPI 本身没有提权步骤。签名、公证、Sparkle 替换应用是另外的事，下面单独写。

## 使用

1. 用下面的安装方式把 `HiDPI.app` 放进「应用程序」。
2. 菜单栏出现显示器图标。没有 Dock 图标。
3. 外接屏下打开「高分辨率 (HiDPI)」。第一次如果系统还没有 2× 模式，会弹出管理员密码框，把覆盖文件写到 `/Library/Displays/.../Overrides`。分辨率应仍显示 2560 × 1440，诊断行的像素应为 5120 × 2880。
4. 若诊断写着要重新插拔或注销，做完后再开一次开关，就会改用真实屏幕。在此之前会先用虚拟屏幕，整个桌面同样按 2× 绘制。需要更小的界面时，再打开「其他分辨率」。
5. 关掉开关，或选「退出」，外接屏回到普通扩展桌面。

请从菜单退出，不要强制退出。

## 安装未签名或临时签名的应用

没有 Developer ID 时，CI 用 ad-hoc 签名（`codesign -s -`）。macOS 会拦截从网络下载的应用。

把应用拖进「应用程序」之后：

- 在 Finder 里右键 `HiDPI.app` →「打开」，再确认打开。或
- 终端执行：

```bash
xattr -cr /Applications/HiDPI.app
```

然后再次打开。Gatekeeper 仍可能要求你在「系统设置 → 隐私与安全性」里允许这一次。

## 从源码构建

需要完整 Xcode（命令行工具里的 Swift 不够签名和 `iconutil`）。

```bash
git clone https://github.com/yosong-github/mac-hidpi.git
cd mac-hidpi
swift test
scripts/build-app.sh 0.0.0
open dist/HiDPI.app
```

`scripts/build-app.sh` 的参数会同时写入 `CFBundleShortVersionString` 和 `CFBundleVersion`。本地开发用 `0.0.0` 即可。

`swift run HiDPI` 能跑界面，但没有打包进 `.app`，菜单栏行为不完整，也不要拿它做更新测试。

每次 push 和 pull request 的 CI 也会打出安装包，并作为 Actions artifact 上传（保留 14 天），名字是 `HiDPI-0.0.0-<短提交号>`。打开该次运行页面，在底部 Artifacts 里下载。解压后是 `HiDPI-0.0.0-<短提交号>.dmg` 和同名 `.zip`。这是测试包，版本号固定为 `0.0.0`，不是 GitHub Release。正式发布仍由 `v*` 标签触发。

## 版本与发布

版本只由 git 标签决定，仓库里不另存一个版本号文件。标签必须是 `vMAJOR.MINOR.PATCH`（例如 `v1.2.3`），不要带前导零或 `-beta`。

每次 push 和 pull request 都会在测试任务里上传上面的 dmg/zip artifact。推送版本标签后，GitHub Actions 还会：

1. 在 `macos-26` 上跑测试、SwiftLint、swift-format，并打通用二进制
2. 打出 `HiDPI-<version>.zip`、`HiDPI-<version>.dmg` 和 `appcast.xml`
3. 创建 GitHub Release，把这三个文件挂上去

在已检出的仓库里发版：

```bash
scripts/cut-release.sh 1.2.3
```

脚本会打带注释的标签 `v1.2.3` 并 `git push origin v1.2.3`。也可以在 Actions 里手动跑 **CI** workflow，输入不带 `v` 的版本号（必须从默认分支跑）。手动跑会在同一趟里打标签并发布。用 `GITHUB_TOKEN` 推标签通常不会再触发第二趟 workflow。

## 自动更新（Sparkle 2）

应用通过 Swift Package Manager 依赖 Sparkle 2.9.3。

- 菜单有「检查更新…」
- `SUEnableAutomaticChecks` 打开，大约每 24 小时后台检查一次
- 允许用户在 Sparkle 的界面里选择自动下载安装；默认仍会先询问
- 更新包是 Release 里的 zip（zip 根上就是 `HiDPI.app`）
- appcast 的固定地址是  
  `https://github.com/yosong-github/mac-hidpi/releases/latest/download/appcast.xml`  
  分叉出去构建时，地址会换成该仓库的 `GITHUB_REPOSITORY`

### 生成 EdDSA 密钥

在一台 Mac 上先构建一次，让 SwiftPM 拉下 Sparkle 的工具：

```bash
swift build -c release
TOOL="$(find .build -type f -name generate_keys -perm +111 | head -n 1)"
"$TOOL" --account mac-hidpi
"$TOOL" --account mac-hidpi -p
"$TOOL" --account mac-hidpi -x "$HOME/hidpi-sparkle-private.txt"
```

- `--account mac-hidpi` 避免覆盖钥匙串里其它 Sparkle 应用的默认 `ed25519` 项
- `-p` 打印的那一行 base64 是公钥。把它写进 `Config/SUPublicEDKey`（文件里只留这一行），提交到仓库
- `-x` 导出的单行内容是私钥。不要提交

```bash
gh secret set SPARKLE_ED_PRIVATE_KEY < "$HOME/hidpi-sparkle-private.txt"
rm "$HOME/hidpi-sparkle-private.txt"
```

密钥名称就是 `SPARKLE_ED_PRIVATE_KEY`。

公钥还是占位符 `PLACEHOLDER_SET_SPARKLE_PUBLIC_KEY`，或者没有私钥时，CI 仍会发布 dmg、zip 和 appcast，但 appcast 不写 `sparkle:edSignature`，并在日志里警告。装了占位构建的用户无法校验更新。**第一次正式发布之前**就要换上公钥并设好私钥，否则以后换密钥，已经发出去的应用对不上签名。

丢失私钥后，已安装的副本不能再通过 Sparkle 升级（Developer ID 应用有钥匙轮换，ad-hoc 没有）。私钥只放在 GitHub secret 和你自己的备份里。

### ad-hoc 签名和 Sparkle 的关系

Sparkle 会用旧应用的 designated requirement 去验证新包。ad-hoc 签名的 requirement 含有这一次构建的 cdhash，每次打包都不一样，所以：

- 检查更新、下载 zip 可以成功
- 安装阶段会失败，日志里类似 “Code signature of the new version doesn't match the old version”
- 用户需要自己下载新的 dmg

另外，ad-hoc 没有硬化运行时。公证必须用 Developer ID，并且嵌套的 `Sparkle.framework` 要用同一张证书重签。

想让自动安装真正成功，构建之间的代码签名身份必须稳定。两条路：

1. **Developer ID（推荐）**。设置下面的 secret 后，CI 用这张证书签名；公证相关的 secret 齐全时还会 `notarytool` 并 stapler。
2. **长期自签的 Code Signing 证书**。身份不变，Sparkle 的签名比对可以通过。Gatekeeper 仍不信任它，用户第一次仍要右键打开或 `xattr`。公证不会成功。

自签证书可以在「钥匙串访问 → 证书助理 → 创建证书」里做：名称自定，身份类型选「自签名根证书」，证书类型选「代码签名」。导出 `.p12` 后：

```bash
base64 < hidpi-signing.p12 | gh secret set APPLE_CERTIFICATE_BASE64
gh secret set APPLE_CERTIFICATE_PASSWORD
```

### 可选的 Developer ID 与公证

| Secret | 作用 |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Developer ID Application 或自签代码签名证书的 `.p12`，base64 |
| `APPLE_CERTIFICATE_PASSWORD` | 该 p12 的密码 |
| `APPLE_ID` | 公证用的 Apple ID。不设则只签名、不公证 |
| `APPLE_APP_SPECIFIC_PASSWORD` | Apple ID 的 App 专用密码 |
| `APPLE_TEAM_ID` | 公证用的 Team ID |

只设证书、不设公证三项时，应用会被稳定签名，但下载后仍要按上面的方式打开。

## 在真实的 Mac 和 2K 屏上验收

CI 跑在没有外接屏的 macOS runner 上，虚拟显示器和镜像只能在你的机器上确认。建议：

1. 接上 2560×1440 显示器，打开菜单，确认名称和「面板 2560×1440」。
2. 打开「高分辨率 (HiDPI)」。若弹出管理员密码，输入一次。菜单应仍写「分辨率 2560 × 1440」。诊断应含「整个桌面 2×」和「5120 × 2880 像素」。图标、图像和所有窗口都应更清楚，视觉大小不变。若提示重新插拔，插拔后再开一次，方式应从「虚拟屏幕」变成「真实屏幕」。
3. 如需对比，再到「其他分辨率」里试 1920×1080、1706×960 或 1280×720。那几档会改变看起来像的尺寸。
4. 关闭开关，确认回到独立扩展桌面，分辨率回到面板原生。
5. 从菜单退出，系统设置里不应留下虚拟屏。再打开应用，上次为这块屏保存的档位应自动恢复。
6. 内建屏幕没有开关。睡眠唤醒、拔插显示器各做一次。
7. 若失败，菜单里会留下错误，里面有系统实际列出的模式。把这段文字留存下来。

已知限制：

- 开启期间，这块外接屏不是独立桌面，它显示虚拟屏的内容
- 多占一块最高约 4K 的帧缓冲，可能有一帧延迟；高刷新和 HDR 不保证保留
- 私有 API，系统更新后可能失效
- 两台厂商/产品/序列号都相同且 unit number 也相同的显示器会共用一条设置
- 菜单栏如果原来在这块外接屏上，可能会跳一下

## 端到端测试更新

1. 按上一节生成密钥，把公钥写入 `Config/SUPublicEDKey` 并推到默认分支，把私钥设为 `SPARKLE_ED_PRIVATE_KEY`。
2. 若要测「安装」而不只是「发现新版本」，同时设好 `APPLE_CERTIFICATE_BASE64` 和 `APPLE_CERTIFICATE_PASSWORD`（Developer ID 或自签证书）。两版必须用同一张证书。
3. `scripts/cut-release.sh 0.1.0`。等 Release 出现后，用 dmg 把应用装进「应用程序」，右键打开。
4. `scripts/cut-release.sh 0.1.1`。等 `appcast.xml` 出现在该 Release 的附件里。`releases/latest/download/appcast.xml` 指向最新一份。
5. 打开已安装的 0.1.0，选「检查更新…」。应看到 0.1.1，下载 zip 并替换应用，重启后关于版本显示 0.1.1。
6. 若仍是 ad-hoc：下载会开始，安装会被签名比对拒绝。控制台里看 `HiDPI` 或 `Sparkle` 的日志可以确认。然后改用手动安装 0.1.1 的 dmg。

本地对照 appcast 时，可以用 `HIDPI_FEED_URL` 覆盖写入包内的地址，用 `python3 -m http.server` 提供 xml 和 zip。包内地址在构建时写死，改服务器内容不用重编，改地址则要重编。

## 工程结构

- `Sources/HiDPICore`：分辨率阶梯、模式匹配、持久化模型和 appcast XML。单测在 `Tests/HiDPICoreTests`
- `Sources/CGVirtualDisplayShim`：私有 `CGVirtualDisplay` 的 Objective-C 包装
- `Sources/HiDPIDisplay`：枚举显示器、切换模式、镜像
- `Sources/HiDPIApp`：SwiftUI 菜单栏界面和 Sparkle
- `Sources/hidpi-appcast`：CI 用来写 `appcast.xml` 的小工具
- `scripts/build-app.sh`、`scripts/package-release.sh`、`scripts/cut-release.sh`

SwiftLint 配置是 `.swiftlint.yml`，Apple `swift-format` 配置是 `.swift-format`。两者都在 CI 里跑。

## 许可

MIT，见 `LICENSE`。
