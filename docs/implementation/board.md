# 双人留言画板

## 使用

悬浮待办窗口的头像与消息入口之间新增画板按钮。点击打开独立的 Excalidraw 窗口；拖动、调整大小和关闭窗口不影响保存。窗口外点击不会关闭画板。双方共享一张画布，各自保留缩放、视野和窗口尺寸。

对方在关闭的画板中留下新内容时，入口显示红点；打开后清除。底部“跳到对方最新修改”将视野移至对方最近一次修改的位置。光标移动不产生未读提醒。底部显示保存、离线或失败状态；失败时可重试，本地队列保留。

## 实现

- `apps/board` 将固定版本 Excalidraw 0.18.1、React、样式和字体打包到 `apps/desktop/web/board`；生成目录不入 Git，每次桌面构建自动生成。资源随 App 分发，画板无需公网 CDN。
- `Board.swift` 管理独立 WebKit 窗口、原生图片选择、账号本地缓存、红点和退出保存。认证凭据留在原生层；WebKit 不直接联网。
- `/v1/board/socket` 使用原生 URLSession WebSocket 和 Bearer 会话。服务器以账号所属 `space_id` 隔离元素、图片和光标，不接受客户端指定其他空间。`GET /v1/board` 只返回当前空间的快照及图片。
- PostgreSQL 的 `board_heads/elements/files/requests/reads` 保存版本、元素、图片、幂等请求和阅读进度。迁移 `002_board.sql` 随服务启动应用。
- 客户端发送元素的字段差异，不发送整张画布替换。空间级事务合并字段、保留删除标记，并记录字段作者。条件撤销检查旧值与作者，避免撤销对方修改。
- 每批修改先写入账号目录的 `board-state.json`，收到落盘确认后才发送；网络重试沿用请求 ID，指纹忽略对象字段顺序。确认只移除对应批次，重连先获取快照再补队列。
- 使用 Excalidraw 官方 `restoreElements/reconcileElements` 合并远程元素，保留正在操作的元素；远程更新不写入本地撤销历史，也不更改视角。图片选择器的空占位元素不会进入队列。
- 光标经 WebSocket 临时转发，不写数据库。PostgreSQL LISTEN/NOTIFY 让多个服务实例中的画板连接保持同步。服务关闭时先结束 SSE/WebSocket，客户端随后重连。

## 运维

先备份数据库，再部署后端和 Nginx 配置，最后发布客户端更新。旧客户端可以继续使用原有待办和消息接口。

`deploy/ip-https.conf` 新增 `/v1/board/socket` 的 Upgrade 转发和 75 秒代理超时。后端每 15 秒发送 WebSocket ping；图片包含在已认证的快照/修改消息中，不存在公开图片 URL。不要只更新后端而遗漏 Nginx 的 WebSocket 路由。

图片允许 PNG、JPEG、GIF、WebP 和不含脚本等活动内容的 SVG，单张原始数据最多 8 MiB。当前每个空间限制 20,000 个含删除标记的元素、24 MiB 元素 JSON 和 32 MiB 图片 JSON。超过限制会保留本地待同步内容并显示错误。图片与删除标记暂不自动清理；数据库备份包括画板和图片。账号本地队列也应保留，尤其在离线修改尚未同步时。

`board-state.json` 以原子方式保存，权限 0600。无法读取时保留原文件并显示错误，不用空画板覆盖它。迁移只新增表，不修改原待办数据。需要回退客户端时保留该文件；回退服务时保留新增表。

## 重复验证

先准备本机 PostgreSQL（开发配置的 55432 端口），并完成 `pnpm install --frozen-lockfile && pnpm build && pnpm check`。

```sh
python3 tests/provision-board-qa.py
python3 tests/prepare-board-qa.py
python3 tests/board-acceptance.py
python3 tests/board-service-checks.py
```

测试只允许 localhost 的 `mmemo_board_qa` 数据库，使用独立随机密码、账号目录和 App bundle ID，不操作日常账号配置。`BOARD_QA_DATABASE_URL` 可覆盖本机测试连接。真实桌面验收需要登录的 macOS 图形会话。

验收通过真实 AppKit 鼠标事件、Excalidraw 编辑器、原生图片选择器和两个实际账号进程运行。为避免同一 Mac 的焦点争夺影响正在绘制的鼠标事件，部分并发属性变更通过另一 App 的编辑器 API 注入；两端仍经过真实保存、WebSocket 和数据库路径。

验收说明见 [验收记录](board-acceptance.md)，逐项结果保存在 `board-native-results.json`；截图、账号、缓存和故障诊断留在不入 Git 的 `artifacts/private/board-qa/`。服务端/客户端自动测试应单独运行，不能与使用同一数据库的真实 App 并行运行，避免自动阅读与确认消息干扰断言。
