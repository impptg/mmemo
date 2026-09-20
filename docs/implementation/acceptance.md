# 自托管迁移验收 — 2026-09-20

## 交付状态

已部署 PostgreSQL + TypeScript/Fastify，已迁移本地 9 条待办，两个正式 macOS App 已运行并显示“已同步”。运行时不访问 CloudBase。Git 已初始化，配置、会话、密码、原始数据、截图和构建产物均不入库。

## 证据

| 项目 | 结果与证据 |
| --- | --- |
| Monorepo | apps/desktop、apps/server、packages/contracts、database、deploy；pnpm build/check 成功；原生构建与签名成功 |
| 本地迁移 | `migration-results.json`：只读取本地 user_mm 数据；9 条待办的 ID、标题、时间、完成状态、创建者、参与人均与正式数据库一致 |
| 双实例 | `native-pair-results.json`：两个独立 AppDelegate/WebKit 进程；双向增删改、原生勾选、双头像、草稿保留 |
| 延迟 | 实际双 App 端到端同步 341 / 349 ms；正式后端 SSE 集成测试 107 ms |
| 爱心 | 双向原生按钮、断开后补收、确认后不重复；`heart-backlog-results.json` 验证 101 条消息跨页处理 |
| AI | 从真实原生输入框提交，真实模型创建双人待办，另一真实实例自动收到；随后删除测试待办 |
| 权限/事务 | 未登录拒绝、非法参与人/日期/伪造创建者拒绝、整批事务回滚、重复请求去重、同键不同请求拒绝、不同字段并发保留、同字段后写生效 |
| 重启恢复 | `recovery-results.json`：分别重启 ECS 后端和 PostgreSQL，两端恢复订阅，随后新写入正常同步 |
| 会话刷新 | 强制服务器访问令牌过期，两端恢复登录并重新订阅 |
| 无业务轮询 | 两个真实 App 空闲 35 秒，todoReads 14→14、heartReads 14→14，2 条 SSE 订阅保持；本地接口测试另覆盖 16 秒跨心跳区间 |
| 唤醒路径 | 测试调用真实应用的 NSWorkspace 唤醒处理方法，恢复 SSE 且不重复爱心；没有让整台用户 Mac 实际进入物理睡眠 |
| HTTPS | 正常系统证书校验，IP SAN 为 59.110.153.116；健康接口 200，公网内部诊断入口 404 |
| 证书续期 | Let's Encrypt HTTP-01 IP 签发成功；renew --dry-run 成功；每天两次检查的系统 timer 已启用 |
| 备份恢复 | 正式库备份后恢复到独立临时库；9 条待办及内容摘要一致 `c2a4e63edffd7c991f5b56f488c768b8`，临时库已清理；每日备份 timer 已启用 |
| 原网站 | 原配置已备份；域名路由返回页面与容器原 index.html 的 SHA-256 一致；原网站已有证书过期属于迁移前状态，本次未更换其证书 |
| 最终资源 | 后端约 27 MiB，PostgreSQL 约 42 MiB；整机仍约 1007 MiB available。为当前轻负载快照，不代表压力测试容量 |
| 正式界面 | Computer Use 检查两个 dist 下正式 App：各 5 条未完成、4 条已完成，账号均显示已同步；截图在本机 artifacts/private/release-user-*.png |
| 清理 | 原始 9 条待办完整保留，测试待办已删除、测试爱心已确认，临时验收 App 已退出，正式双实例已打开 |

## 测试边界

- 本轮按约定验证同一台 Mac 上的两个独立账号实例，不声称已覆盖第二台物理设备。
- 唤醒通过应用回调及真实网络/服务断开恢复验证，未进行整机物理睡眠或数日连续运行测试。
- 备份位于同一服务器。整机灾难恢复还需要额外的异地备份。
- 日常维护和已有网站容器重建后的配置恢复见 operations.md。
