# 自托管部署与维护

## 当前布局

- ECS：59.110.153.116，Ubuntu 24.04，2 核、系统可用总内存约 1.6 GiB。
- API：`https://59.110.153.116`，使用公开可信的 IP 证书，系统正常验证证书。
- 源码部署目录：`/opt/mmemo/current`。
- 私有配置：`/opt/mmemo/server.env`、`/opt/mmemo/bootstrap.json`，0600，不入 Git。
- PostgreSQL 数据卷：`mmemo_postgres`。后端绑定宿主机 127.0.0.1:8787；数据库无公网端口。
- 现有 `pp-web-site` 容器使用 host 网络；增加独立 IP 虚拟主机，域名网站保留原路由。
- 原网站配置备份：`/opt/mmemo/backups/website-http-original.conf`。域名 HTTPS 显式补上 `server_name impptg.com www.impptg.com`，避免与 IP 默认虚拟主机混淆。

## 发布

本地运行 `pnpm install --frozen-lockfile && pnpm build && pnpm check`，将根包文件、锁文件、两个包的 package.json/dist、database 和 deploy 上传到服务器。

```sh
cd /opt/mmemo/current
docker compose --env-file /opt/mmemo/server.env -f deploy/compose.yaml -p mmemo up -d --build --wait
curl --fail https://59.110.153.116/health
```

迁移只在启动时应用未执行的版本；上线前执行 `deploy/backup.sh`。不要运行 `docker compose down -v`，那会删除数据卷。

## IP 证书

Let's Encrypt IP 证书有效期约六天。`mmemo-cert.timer` 每天检查两次，`mmemo-acme-web.service` 仅在回环地址提供 HTTP-01 验证文件；已有 Nginx 将 IP 的验证路径转发给它。

`deploy/renew-certificate.sh` 续期、复制证书到网站容器、验证配置并平滑重载。`--dry-run` 测试续期链路。续期失败可在 `journalctl -u mmemo-cert` 查看，必须在证书过期前恢复。

现有网站容器没有配置挂载。若重建 `pp-web-site`，需要重新应用域名 `server_name` 及运行续期脚本恢复 IP 配置和证书；普通容器重启不丢这些文件。后续可以将网站配置迁移为挂载，但不在本次业务迁移中重建网站。

## 备份与恢复

`mmemo-backup.timer` 每天 03:00 执行备份，保留 14 天，保存在 `/opt/mmemo/backups`。`deploy/verify-restore.sh` 恢复到临时数据库并输出原库/恢复库待办内容摘要，再删除临时库；不会覆盖正式数据库。

服务器内备份不能抵御整机或磁盘丢失。可将加密备份复制到另一台设备。实际回滚时先停止后端写入，再恢复选定备份，重启后端并让客户端重连。

本地迁移前完整备份位于 `~/Library/Application Support/mmemo-migration-backups/20260920-185855`。旧 CloudBase 配置保留作为历史备份；新运行时只使用 `server.json` 和 `server-session.json`。

## 检查

```sh
docker compose --env-file /opt/mmemo/server.env -f deploy/compose.yaml -p mmemo ps
docker stats --no-stream
systemctl list-timers mmemo-cert.timer mmemo-backup.timer
```

`/internal/metrics` 在公网代理明确拒绝，只能通过本机端口和私有管理员令牌读取，用于核对订阅数、待办/爱心读取数。避免输出令牌或打印配置文件。

## 双实例验收

先 `./dev-pair.sh --prepare`，再 `tests/build-native-pair.sh`、`python3 tests/native-pair.py`。测试构建运行与正式版相同的 AppDelegate/WebKit/网络代码，只额外编入本地命令接口；正式版没有该入口。

`tests/recovery.py` 自行启动两个验收进程，会重启 mmemo 后端及数据库、强制访问令牌过期并检查恢复。测试仅操作专用待办，结束核对原数据不变。测试脚本自动退出验收 App，再通过 `./dev-pair.sh` 打开正式 App，避免共用同一账号文件的多个进程同时运行。
