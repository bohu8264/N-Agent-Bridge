# Contributing to N Agent Bridge

感谢你帮助 N Agent Bridge 支持更多键盘和更可靠的 Codex 工作流。任何人都可以通过 Fork 和 Pull Request 参与，不需要仓库协作者权限。

## 开发流程

1. Fork `bohu8264/N-Agent-Bridge`。
2. 从最新 `main` 创建功能分支，例如 `feature/air96-v3-profile`。
3. 保持改动范围清晰，同时更新代码、测试和相关文档。
4. 运行软件自检；涉及硬件时附上已脱敏的型号、连接方式、固件版本、ACK 和回读结果。
5. 提交 Pull Request，说明改动原因、用户影响、验证方式和尚未验证的限制。

## 开发检查

```sh
CLANG_MODULE_CACHE_PATH=/tmp/nagent-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/nagent-clang-cache \
swift build --disable-sandbox --scratch-path /tmp/nagent-build --product Air75AgentBridge

CLANG_MODULE_CACHE_PATH=/tmp/nagent-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/nagent-clang-cache \
swift run --disable-sandbox --scratch-path /tmp/nagent-build Air75CoreSelfTest --software-only
```

安装完整 Xcode 的环境还应运行 `swift test`。

## 新增键盘型号

新增 NuPhy 型号必须遵守 [新增型号指南](docs/ADDING-NUPHY-KEYBOARD.zh-CN.md)：

- 设备识别 Profile 与硬件写入 driver 分离；
- 未知协议先保持只读，不能根据同系列产品猜测命令；
- 写入前保存完整原始状态；
- 写入后检查 ACK，并完整回读比较；
- 必须验证恢复路径；
- USB、2.4G 和 Bluetooth 分别验收；
- 不得提交包含设备序列号、用户路径、聊天内容或原始私人抓包的文件。

任何无法实机验证的功能都必须在 UI 和文档中明确标注为未验证。

## 代码与隐私要求

- 不扩大普通键盘输入采集范围。
- 不读取或记录 Codex 提示词、回答正文、Token 或 API Key。
- 合成事件必须继续定向发送给目标应用，不能全局广播。
- 不提交证书、私钥、Apple 公证凭据、`.env`、Application Support 备份或构建产物。
- 避免把 NuPhy、OpenAI 或第三方资料直接复制进仓库；只提交有权发布的原创代码和必要说明。

## 提交和 PR

- 提交信息使用简短的动词短语。
- 一个 PR 尽量只处理一类问题。
- 修复问题时说明根因，而不只描述界面现象。
- 若改动硬件协议，请附上失败恢复结果和与现有型号隔离的证据。

提交代码即表示你同意按本仓库的 [MIT License](LICENSE) 发布你的贡献。
