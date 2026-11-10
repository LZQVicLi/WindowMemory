# 显示管理 / Display management

左侧一级导航和菜单栏右键菜单都有「显示管理」。页面列出 macOS 报告在线的显示器，包括没有硬件控制能力的屏幕。每张卡片显示主副屏、内建或外接、当前分辨率和可读取的刷新率、旋转与镜像状态。显示器连接变化或电脑唤醒后重新读取；也可以点「刷新显示器」。

- **外接显示器**：从 DDC/CI 能力表和实际读数发现控制项。常用项目包括亮度、对比度、输入源、色彩预设、显示器音量与静音；展开「更多硬件项目」可查看支持的 RGB 增益、黑电平、背光、锐度、饱和度、画面模式、缩放、菜单语言和电源。
- **Mac 内建屏及兼容 Apple 屏幕**：系统能读取硬件亮度时提供原生亮度控制。其他项目按设备能力显示。
- **如何操作**：拖动数值滑块后点「应用」。选择输入源或休眠、关屏前会提示可能失去当前画面；可通过显示器实体菜单切回。应用后读取实际值，无法读回时只显示「已发送指令」。
- **系统级设置**：点「系统显示设置」调整 macOS 分辨率、刷新率、HDR、旋转、镜像和排列。这些设置和显示器自身的 OSD 配置分别由 macOS 与显示器管理。

## 兼容性和边界

DDC/CI 取决于屏幕固件、显卡、线缆、接口和扩展坞。若卡片没有可调项目，检查显示器实体菜单是否开启 DDC/CI，或尝试直连、USB-C / DisplayPort。虚拟屏和无法正确映射到硬件的屏幕仍会列出。Apple Silicon 使用可选 IOAVService 接口，Intel 使用 IOKit I²C；系统接口不可用或匹配不唯一时，程序不会猜测另一台设备。

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
