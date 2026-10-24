# 签名、公证与首次打开

## 当前 Release 状态

当前 1.0–1.3 的产物使用 `codesign --sign -`，即 **ad-hoc 临时签名**，不是 Apple Developer ID 签名，也不是 Apple Development 开发证书签名；没有 Team ID，未经过 Apple 公证。开源、公开 GitHub 仓库和提供校验和都不会让 Gatekeeper 自动信任 App。

签名封装可用于检查文件是否被改动，但 ad-hoc 不证明发行者身份。系统可能阻止下载的 App 首次运行；版本更新也可能需要重新添加窗口控制授权记录。当前不会因为没有公证而减少应用本身的布局功能，但用户需要手动允许可信下载，组织管理的电脑也可能禁止此操作。

在终端中可以只读核对：

```sh
codesign -dv --verbose=2 '/Applications/窗口记忆.app'
```

当前会显示 `Signature=adhoc`、`TeamIdentifier=not set`。

## 下载后提示无法验证开发者

这属于 Gatekeeper 的发行者与安全校验，和 App 打开后申请的“窗口控制 / 辅助功能”权限是两件事。

确认下载来自本仓库，且 `SHA256SUMS.txt` 校验通过后，如果 macOS 显示开发者无法验证：

1. 先尝试打开 App，并关闭拦截提示。
2. 前往 **系统设置 → 隐私与安全性 → 安全性**，找到这个 App 的拦截记录。
3. 由用户选择 **仍要打开**，按系统要求确认后打开。
4. App 运行后，再按悬浮引导开启窗口控制权限。

较旧 macOS 也可能支持右键 App → 打开进行确认；新系统请以“隐私与安全性”中的入口为准，不承诺右键菜单一定能放行。“仍要打开”只是用户为这个 App 作出信任决定，不等于 App 已公证，也不保证组织策略允许放行。若提示实际为文件损坏或签名无效，应重新下载和校验，不能一概按“开发者无法验证”处理。

参考：[Apple 首次打开说明](https://support.apple.com/guide/mac-help/mh40617/mac)。不需要关闭 Gatekeeper、SIP 或执行移除隔离属性的命令。

## 面向公众的正式发行方式

推荐 **Developer ID Application 签名 → Apple 公证 → 附加公证票据（staple）→ 校验 → 发布**，这样在系统默认策略下通常可正常首次打开，仍可能出现“从互联网下载”的普通确认提示。

1. 加入 Apple Developer Program。个人或组织会员均可发行 Mac App；标准会员年费为 99 美元，实际本地价格与资格以 Apple 为准。个人团队签发的 Developer ID 也能公证，并非必须公司主体。
2. 由团队 Account Holder 创建 **Developer ID Application** 证书和私钥。免费个人开发团队、`Apple Development` 或自行创建的证书不能替代正式发行身份。
3. 为最终 App 启用 hardened runtime，使用 Developer ID 签名及安全时间戳，验证签名。
4. 用 `xcrun notarytool submit … --wait` 提交到 Apple，并确认结果为 `Accepted`，检查日志。
5. 用 `xcrun stapler staple` 和 `validate` 附加、校验票据，再重新打包 ZIP / DMG；DMG 也可以签名、公证并附票据。
6. 重新生成 SHA-256 校验和，用 `spctl --assess` 验证最终下载产物，再发布新版本。

证书私钥、`.p12`、密码或 Apple API 私钥应保存在系统钥匙串或 GitHub Actions Secrets，绝不能提交到公开仓库。当前自动发布流程仍明确使用 ad-hoc；在拿到正式发行凭据之前不会标为已公证。

正式签名通常有助于后续版本保持一致的发行身份，但辅助功能、登录项目等仍受 macOS 自身授权规则管理，公证不会代用户开启这些权限。

参考：[Developer ID](https://developer.apple.com/developer-id/) · [Apple 公证流程](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [会员信息](https://developer.apple.com/programs/)
