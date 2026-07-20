# Codex Micro Research

核验日期：2026-07-19。主来源：[OpenAI Codex Micro 官方页](https://openai.com/supply/co-lab/work-louder/)、[Codex 开发文档](https://developers.openai.com/codex/)。

## 官方明确说明

- Codex Micro 支持 Bluetooth / USB-C、Mac / Windows、RGB。
- 每个 Agent Key 显示 Codex 实时状态；官方文字列出 thinking、running、waiting、done。
- joystick 启动 Skills/常见工作流，官方示例是 PR review、debug、refactor。
- Command keys 的明确示例为 accept、reject、push-to-talk、new chat，以及未逐项列出的“more”。
- dial 调整 reasoning level。
- 硬件规格为 13 个机械键、1 个触摸传感器、1 个旋转编码器、1 个平面摇杆。

## 官方没有公开

- 逐个 Agent/Command 键的完整默认映射与确切数量分组；
- 触摸传感器的默认动作；
- RGB 色值、动画时序和传输协议；
- 固件 HID Report、认证协议或 Work Louder Input 私有接口。

## 本项目采用的等价映射（不是官方默认）

- 6 个 Agent Slot，F13–F18；
- Quick Action、Approve、Decline、New Chat、Push to Talk、Send，F19–F24；
- 方向键等价摇杆；旋钮默认 Context Aware；
- 状态色遵循产品需求中的建议色表，尚未称为官方色值。

## Codex 集成验证

本机 Codex CLI 0.144.6 已登录 ChatGPT。稳定 CLI 提供 `codex exec --json`；当前安装版本还提供标记为 experimental 的 app-server V2，schema 明确含 `thread/start`、`turn/start`、`turn/interrupt`、流式通知以及 command/file/permissions approval 回调。本项目用 app-server 满足人工批准，保留协议版本风险提示。
