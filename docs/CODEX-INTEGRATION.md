# Codex Integration

优先级为：当前公开 SDK（若出现稳定 Swift/HTTP surface）→稳定 CLI→app-server→自有客户端。本机事实：Codex CLI 0.144.6 已登录 ChatGPT；`codex exec --json` 稳定但非交互审批会失败关闭，不能完成 Approve/Decline 体验；app-server V2 暴露真实 thread/turn/approval 状态，但 CLI 标记 experimental。

`CodexAppServerBackend` 启动官方 CLI 的 stdio app-server，发送 initialize、thread/start、turn/start、turn/interrupt，并把 command/file/permissions approval request 暂存到 UI。只有用户按 Approve/Decline 才返回 accept/decline。默认 sandbox 为 workspace-write、approvalPolicy 为 on-request、reviewer 为 user。

不使用鼠标坐标或截图识别控制 Codex App。
