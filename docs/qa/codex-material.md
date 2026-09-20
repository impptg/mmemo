# Todo 毛玻璃来源

2026-09-17：检查本机 `/Applications/ChatGPT.app/Contents/Resources/app.asar` 的生产构建产物，不是完整开发源码。research 下没有找到 Codex 桌面实现，实际安装包已提供所需实现，因此没有额外下载仓库。

- `.vite/build/main-BT6ViFC-.js`：透明窗口背景 `#00000000`；macOS `setVibrancy(ARe(...))`，普通非不透明窗口返回 `menu`。
- `webview/assets/app-initial-5b0a474bff5e.css`：Electron 的根节点和 body 透明；`.app-shell-left-panel` 背景是 `color-mix(in srgb, var(--color-surface-tertiary) 70%, transparent)`。
- 浅色 token 链：`--color-surface-tertiary` → `--vscode-editor-background` → `--color-background-editor-opaque` → `color-mix(in oklab, #ededed 40%, transparent)`。两层混色合并为 `rgb(237 237 237 / 28%)`。

mmemo 对应迁移：`NSVisualEffectView.material = .menu`，保持 `.behindWindow` 和 `.active`；窗口和 WKWebView 透明，在 `.panel` 上叠加同等浅灰色。保持浅色主题、圆角、位置和减少透明度的无障碍回退；未复制 Codex 的主题切换或特殊窗口策略。

验证：`./tests/native-surfaces.sh` 检查原生材质和透明窗口；`tests/message-surfaces.swift` 检查实际 WebKit 计算后的叠色及既有消息交互。系统版本与桌面背景仍会影响最终材质观感。
