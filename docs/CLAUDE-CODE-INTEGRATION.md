# Claude Code Integration

主来源：[Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview)、[CLI reference](https://code.claude.com/docs/en/cli-reference)、[Hooks](https://code.claude.com/docs/en/hooks)。官方 Agent SDK 支持 Python/TypeScript、会话、流式输入输出、approvals 与 hooks；其他语言可通过 `claude -p --output-format json/stream-json` 集成。

本机未安装 Claude Code CLI。当前 `ClaudeCodeBackend` 已实现可执行文件发现、print/stream-json、新建/恢复/停止与状态边界；外部 permission callback 未接入时始终拒绝，不自动批准。正式版可嵌入官方允许的 TypeScript SDK native binary，或用 `--permission-prompt-tool` 连接受控 MCP callback。
