# mmemo

原生 macOS 双人待办。Swift/AppKit/WebKit 桌面端、TypeScript/Fastify 后端和 PostgreSQL 位于同一个 pnpm monorepo。

## 目录

- `apps/desktop`：桌面应用与 WebKit 界面。
- `apps/server`：账号认证、待办事务、爱心消息、SSE。
- `packages/contracts`：接口校验和 TypeScript 类型。
- `database/migrations`：版本化 PostgreSQL 迁移。
- `deploy`：容器、IP HTTPS、证书续期、数据库备份。
- `tests`：业务、接口和两个真实 App 进程的验收。

## 同步方式

客户端经 HTTPS 读写；数据库事务提交后通过 `LISTEN/NOTIFY` 唤醒服务端，服务端通过 SSE 通知有权限的客户端重新读取。空闲时仅 SSE 心跳，不轮询业务表。首次连接、重连、唤醒和监听器恢复后补读，通知不承担持久消息存储。

待办按字段更新，同字段按服务器提交顺序生效。写接口必须携带 `Idempotency-Key`，传输失败重试复用同一键。爱心保存到数据库，客户端持久去重后确认接收。数据库不向公网开放，用户权限由后端验证；桌面端没有数据库或管理员凭据。

## 本地开发

需要 Node.js 22、pnpm 10、Docker，以及构建桌面端所需的 macOS Command Line Tools。

```sh
pnpm install --frozen-lockfile
pnpm build
docker compose -p mmemo-local -f deploy/compose.local.yaml up -d --wait
# 私有 .secrets/bootstrap.json 包含 passwords 和 todos，不纳入 Git。
DATABASE_URL=postgres://mmemo:local-testing-only@127.0.0.1:55432/mmemo node apps/server/dist/bootstrap.js .secrets/bootstrap.json
DATABASE_URL=postgres://mmemo:local-testing-only@127.0.0.1:55432/mmemo ADMIN_TOKEN=local-test-admin node apps/server/dist/index.js
```

另一个终端运行 `pnpm test`、`pnpm check`。默认集成测试针对上述本地服务；设置 `TEST_BASE_URL` 可针对正式后端进行临时写入测试，运行前退出日常 App，测试会清理自身待办。

## 桌面端

```sh
./run.sh --build       # 构建本机模式
./dev-pair.sh          # 构建并打开两个已配置的独立账号
./dev-pair.sh --prepare
```

账号配置位于 `~/Library/Application Support/mmemo/development/<username>/server.json`，包含 `baseURL`、`username`、`password`、`uid`、`deviceId`，权限必须为 0600。会话保存在 `server-session.json`。AI 配置仍使用同目录 `ai.json`。不要提交这些文件。

`dev-pair.sh` 不再读取 CloudBase。历史实现说明保留在 `docs/history`；根目录 `cloudbase` 和旧文档仅为迁移参考，不被运行时使用。

## 部署与验收

参见 [运维说明](docs/implementation/operations.md)、[验收记录](docs/implementation/acceptance.md)。生产入口使用 IP HTTPS；具体部署参数保存在本地私有配置与服务器 `/opt/mmemo/server.env`。

AI 的 DeepSeek 强制工具调用沿用 `thinking: disabled`，避免模型协议冲突；此次迁移不改变模型配置语义。
