# 应用更新 / App updates

从 1.4.0 起，正式版每次启动都会查询 [WindowMemory 的最新正式 Release](https://github.com/LZQVicLi/WindowMemory/releases/latest)。左侧导航底部显示检查结果，有更高的稳定版本时显示版本号和「一键更新」。不自动下载或安装；检查失败也不影响布局与显示管理。预览构建不检查更新。

1. 将正式 App 安装到「应用程序」或自己的 `~/Applications`。
2. 有新版时，点「一键更新」下载通用 ZIP，验证后替换并重启。
3. 如当前目录不可写、发布包无法校验或 macOS 阻止启动，可从「打开下载页」手动更新。

更新只替换应用本身。布局、模板及设置仍存放在本机 Application Support 中。若系统未能打开新版，会尝试恢复旧 App；正常更新后旧 App 保存在 `~/Library/Application Support/WindowMemory/Update Backups/`。更新不会清除隔离属性、关闭 Gatekeeper 或授予系统权限。当前仍是 ad-hoc 签名，签名变化可能需要重新添加窗口控制权限。

## 更新校验

只使用公开的 GitHub Releases API，不读取登录凭证或上传布局数据。版本按 major、minor、patch 数值比较，忽略预发布和草稿。可安装资产须来自固定仓库、版本标签和文件名，且带有 GitHub 返回的 SHA-256 摘要。下载后验证字节数、摘要、ZIP 路径与类型、App 版本、Bundle ID 和两种架构的签名。已有 Developer ID 版本要求更新保持同一签名团队。当前 ad-hoc 版本依赖 GitHub HTTPS 和项目发布链提供来源信任。

每个 Release ZIP 都由打包流程检查是否可被更新器读取。开发时可运行 `--update-diagnostics` 下载并验证公开包，此模式不替换 App，也不运行下载的二进制。

## English

Version 1.4.0 and later check the official stable GitHub release at launch. The sidebar footer offers **Update and restart** when a newer verified package is available. Installing requires your click and a writable Applications directory. A manual download link is always available when an update is found. Layout data stays in Application Support. Failed launches trigger rollback when possible; successful updates retain a backup. Ad-hoc releases may require granting macOS window-control permission again.
