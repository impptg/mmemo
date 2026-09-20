# CloudBase 接入状态

环境：mmemo-d5g6fybcm3b31a52d。2026-09-17 已完成授权并通过远程 API 验证，地域为上海（ap-shanghai）。

## 已完成

- 官方 npm 包 `@cloudbase/cloudbase-mcp@2.34.4` 已全局安装。
- Codex 全局 MCP `cloudbase` 已启用，使用绝对 Node 与入口文件路径。
- 使用 `INTEGRATION_IDE=CodeX`，关闭工具遥测。
- MCP initialize / tools/list 验证成功，41 个工具。
- 项目 `cloudbaserc.json` 指定 mmemo 环境，不包含凭据。

## 远程验证结果

- 用户确认后完成官方浏览器 CLI 授权，授权范围为账号级 CloudBase 资源权限。
- `auth(status)` 返回 `auth_status: READY`，目标环境正确。
- `auth(set_env)` 返回 `ENV_READY`，固定上述环境和上海地域。
- `queryEnv(info)` 返回 `Status: NORMAL`、`RuntimeMode: postgresql`，已配置 PostgreSQL；没有可用的 NoSQL 或 MySQL 实例。
- `queryAppAuth(getLoginConfig)` 确认用户名密码登录已开启；邮箱、匿名、手机号登录未开启。本次未修改登录策略。
- 套餐为体验版，到期时间为 2027-03-17 23:59:59；本次未改变计费设置。

## 初次配置时的后续事项（历史记录）

- 创建待办业务表与仅允许共享成员访问的行级权限，接入应用登录及云端读写。
- 本次未创建业务数据表或认证用户，桌面应用仍使用本地存储；尚未进行双实例同步测试。
- 双实例需要独立登录状态与本地配置，通过同一远程环境同步，不能以共享本地 JSON 文件代替云端验证。

设备码方式初始化返回非 JSON 页面，已切换官方 web 登录并成功完成。管理端连接已经验证；应用端同步需要单独实现和验证。

官方配置说明：https://docs.cloudbase.net/ai/cloudbase-ai-toolkit/ide-setup/openai-codex-cli


## 2026-09-17 双实例接入结果

- 已创建并验证登录：user_pptg / 2100541450115510274（frog）、user_mm / 2100541456125558785（raccoon）。
- 已应用并回查两次迁移：20260917113000_shared_todos、20260917113500_restrict_table_grants。
- `mmemo_members`、`mmemo_todos` 已启用 RLS，明确收回 CloudBase 默认表写权限；共享空间成员只读表，通过受控事务 RPC 写入。
- Swift CloudClient 使用官方 Auth / PostgreSQL HTTP API，应用用户令牌访问，不使用管理权限绕过 RLS。
- `dev-pair.sh` 生成两个独立应用及本机配置，凭据不入仓库；详情和实际验证范围见 README 的 CloudBase 双账号开发部分。
