# 显示管理 / Display management

左侧一级导航和菜单栏右键菜单都有「显示管理」。页面列出 macOS 报告在线的显示器，包括没有硬件控制能力的屏幕。每张卡片显示主副屏、内建或外接、当前分辨率和可读取的刷新率、旋转与镜像状态。显示器连接变化或电脑唤醒后重新读取；也可以点「刷新显示器」。

- **外接显示器**：从 DDC/CI 能力表和实际读数发现控制项。常用项目包括亮度、对比度、输入源、色彩预设、显示器音量与静音；展开「更多硬件项目」可查看支持的 RGB 增益、黑电平、背光、锐度、饱和度、画面模式、缩放、菜单语言和电源。
- **Mac 内建屏及兼容 Apple 屏幕**：系统能读取硬件亮度时提供原生亮度控制。其他项目按设备能力显示。
- **软件调暗**：独立屏幕可用，不要求 DDC/CI。通过半透明覆盖层降低画面亮度，不改背光、输入或颜色配置；可以点「恢复原样」，退出 App 后也会恢复。镜像屏不分别调暗。
- **局域网遥控**：兼容的澎湃 OS 显示器可在「局域网遥控」填写显示器自己的私有 IPv4 地址，点击「测试连接」。设备有响应后才显示它返回的输入源、音量。可以在切离 Mac 视频输入后继续用网络遥控切回来。仅在手动点击时连接，不扫描网段，不保留配对；macOS 提示时需允许本地网络访问。
- **如何操作**：拖动数值滑块后点「应用」。选择输入源或休眠、关屏前会提示可能失去当前画面；可通过显示器实体菜单切回。应用后读取实际值，无法读回时只显示「已发送指令」。
- **系统级设置**：点「系统显示设置」调整 macOS 分辨率、刷新率、HDR、旋转、镜像和排列。这些设置和显示器自身的 OSD 配置分别由 macOS 与显示器管理。

## 兼容性和边界

DDC/CI 取决于屏幕固件、显卡、接口，以及 Mac 到屏幕之间的整条连接（线、转接头、扩展坞或 KVM）。若没有可调项目，先看显示器实体菜单有没有 DDC/CI 开关；再试手头已有的直连方案，例如 Mac 的 USB-C 口接一根支持视频的 USB-C → DisplayPort 线，直接到显示器的 DP 口。也可比较 HDMI 直连。如果信号已经通过转接坞，系统显示 DP 或 HDMI 并不能证明中间没有转接。直连也无法为固件没有提供的功能补出硬件控制。

虚拟屏和没有可用硬件接口的屏幕仍会列出。Apple Silicon 优先试 IOAVService，再试同一块显示器可用的 Framebuffer I²C；Intel 使用 Framebuffer I²C。无法按系统路径定位时，尝试通过 EDID 的厂商、型号和序列号唯一匹配。无法唯一匹配或读取指定项目时不会写入。诊断显示系统报告的信号协议与真正收到回复的控制路径；它不能识别所有物理线材或设备型号。

澎湃 OS 遥控走显示器厂商接口（HTTP 6095），不同于 DDC/CI，不能用于普通不联网的显示器。仅用于自己信任的局域网。其他厂商的 USB 控制或网络遥控需要对应型号的协议；软件调暗不能代替硬件对比度、背光或输入切换。参考 [MonitorBar 的局域网实现](https://github.com/Binaryify/MonitorBar/tree/814a29ecc751598df51d56c6d949e1dee35cc573/internal/mitv)。

输入切换只提供显示器报告的端口。若只能读取当前输入，会显示为只读。未识别、恢复出厂和厂商服务类命令不会发送。无效的读数范围也保持只读；固件报告的其他功能代码仅供诊断。HDR、游戏模式等 OSD 设置可能锁定某些硬件项目，写入结果以显示器实际读回为准。

显示管理独立于窗口辅助功能授权，不在启动时自动修改任何显示器设置。默认源码构建的 Preview 使用合成设备和数值，所有预览操作都不会更改硬件或真实布局。

如果希望在不替换已安装版本的情况下试用真实硬件控制，可以用 `BUILD_MODE=display-preview zsh build.sh` 构建 **WindowMemory Display Preview**。此版本只显示显示管理页面，只有在主动应用设置时才会写入屏幕；不读取真实布局，也不注册窗口自动恢复。它有独立的应用标识，不使用正式版的辅助功能授权。

维护者可以运行只读探测，输出在线设备和它们实际响应的项目：

```sh
'build/WindowMemory Preview.app/Contents/MacOS/WindowMemory' --display-diagnostics
```

## English

Open **Display management** from the sidebar or menu-bar context menu. All online displays appear, even when their connection offers no hardware controls. Compatible external monitors expose DDC/CI brightness, contrast, inputs, color presets, sound and additional features discovered per device; supported Apple displays use native brightness. Input options come from the monitor’s advertised capabilities. Apply a slider value explicitly and verify the readback. Switch inputs or display power only when you can switch back using the monitor’s own menu. For resolution, refresh rate, HDR, rotation, mirroring and arrangement, use the macOS Display Settings shortcut.

Cables, ports, docks, firmware and macOS drivers can limit DDC/CI. Unsupported features, unknown vendor commands and factory resets are never written. The default development Preview is isolated and synthetic; its `--display-diagnostics` flag performs hardware reads only. See the bundled third-party notices for transport references.

Software dimming uses a per-display overlay and leaves the physical backlight unchanged. For compatible HyperOS displays, enter the monitor's private IP in **LAN remote** and test the connection before controlling its advertised inputs or volume. This does not scan the network and is not a generic protocol for other brands.
