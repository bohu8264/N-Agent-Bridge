# N Agent Bridge 正式站外发行

本项目采用 Apple 官方的 Developer ID 站外发行方式，不要求上架 Mac App Store。正式用户收到 `NAgentBridge.dmg` 后，把 App 拖入“应用程序”即可正常打开；第一次仍需由用户本人允许输入监控和辅助功能。

## 当前状态

软件侧流水线已经完成，但这台 Mac 的钥匙串当前只有本机自签身份 `N Agent Bridge Local Signing`，没有 `Developer ID Application`，也没有 notarytool Keychain profile。因此现在只有带版本号的 Development 测试包；正式 `dist/NAgentBridge.dmg` 尚未生成。

## Apple 账号只需准备一次

1. 使用 Apple Developer Program 的 Account Holder 账号创建 `Developer ID Application` 证书，并把带私钥的证书安装到这台 Mac 的登录钥匙串。
2. 在本机交互式保存 Apple 公证凭据。不要把 Apple ID 密码、App 专用密码、API 私钥或证书私钥写进项目、脚本或聊天记录。
3. 推荐的 Keychain profile 名称是 `NAgentBridgeNotary`。使用 Apple ID 的示例命令如下；命令会由 Apple 工具交互处理凭据：

```sh
xcrun notarytool store-credentials "NAgentBridgeNotary" \
  --apple-id "你的 Apple ID" \
  --team-id "你的 10 位 Team ID"
```

也可以使用 App Store Connect API Key 创建 profile。无论采用哪种方式，凭据都只保存在钥匙串，不提交到仓库。

## 生成正式安装包

先从 `security find-identity -v -p codesigning` 复制完整的 Developer ID 名称，然后执行：

```sh
export AIR75_VERSION="0.9.9"
export AIR75_BUILD_NUMBER="24"
export AIR75_SIGNING_IDENTITY="Developer ID Application: 你的名称 (TEAMID)"
export AIR75_NOTARY_PROFILE="NAgentBridgeNotary"
./scripts/release-public.sh
```

脚本按顺序完成：

1. 分别编译 Apple 芯片和 Intel 版本并合并为 Universal App；
2. 使用 Developer ID、Hardened Runtime 和安全时间戳签名；
3. 生成并签名 DMG；
4. 通过 `notarytool` 上传 Apple 公证并等待结果；
5. 把公证票据 Staple 到 DMG；
6. 通过 `codesign`、`spctl`、`stapler validate`、`hdiutil verify` 和 SHA-256 最终检查。

任一步失败，脚本都会以失败退出，不会宣称安装包已经可以分发。只有完整成功后生成的 `dist/NAgentBridge.dmg` 才能发给其他人。

## 权限与升级

从本机自签版本第一次迁移到 Developer ID 正式版时，macOS 会把签名身份从本机证书切换为 Apple Team，开发机可能需要最后重新允许一次输入监控和辅助功能。之后必须长期保持同一个 Bundle ID `com.nagentbridge.mac`、同一个 Apple Team 和 Developer ID 发行身份；正常更新时不要改名、不要改 Bundle ID、不要退回 ad-hoc 或本机自签。

公开发布前还需要在至少一台没有安装过本产品的 Mac 上完成拖拽安装、首次授权、启动、Codex 控制和覆盖升级验收。
