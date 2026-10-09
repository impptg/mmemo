# 画板版本发布验证 · 2026-10-09

## 正式发布

- 版本：0.3.0，构建 3，Apple 芯片、macOS 13+。
- 源码：`315136c3da968da0d6cd0157fc278bed2088e50f`，已推送 `main`，标签 `v0.3.0` 指向同一提交。
- [GitHub Release](https://github.com/impptg/mmemo/releases/tag/v0.3.0) 已公开；[源码 CI](https://github.com/impptg/mmemo/actions/runs/37887808397) 桌面与后端任务通过。
- [user_pptg 更新源](https://impptg.github.io/mmemo/updates/user_pptg.xml) 与 [user_mm 更新源](https://impptg.github.io/mmemo/updates/user_mm.xml) 均为 0.3.0 / 3，Pages 构建成功。公开 XML 与签名候选逐字节一致，Ed25519 验证成功。
- 两个 ZIP 均可匿名下载，长度及 SHA-256 与清单一致，归档签名有效。正式 App 的 bundle ID、账号、正式更新源和本地资源已检查；没有 QA IPC、账号配置、画板缓存或私钥。

| 账号 | ZIP SHA-256 |
| --- | --- |
| user_pptg | `2de1d35c0f3cfa60096665f9be10dfd5750f5825cfd00223ec67ac316df0fc66` |
| user_mm | `4e471e06ac62ea504b3121f74e15f06ce40e16415e60e7290ace97f7b5287c74` |

## 线上服务

ECS 已部署对应源码构建的后端，数据库和服务容器均为 healthy。数据库迁移包括 `001_initial.sql`、`002_board.sql`；Nginx 配置检查和 reload 成功，公开 `/health` 返回 200。

部署前备份为 `mmemo-20261009T052056Z.dump`，部署后备份为 `mmemo-20261009T052432Z.dump`。原有 21 条待办保留；部署后备份恢复到独立临时库，原库和恢复库待办行数及内容摘要一致。画板新增表已存在，备份包含新增表。

两个正式账号分别登录 `https://59.110.153.116`，读取已认证 HTTPS 快照并建立 WSS。双向光标均到达，未认证快照返回 401。此项只验证生产认证与传输，没有创建画板元素、图片或待办；功能、并发和故障恢复通过本机隔离数据库的真实双 App 验收，见 [功能记录](board-acceptance.md)。

## 客户端安装

本机两个独立账号的旧版 QA App（0.2.1，QA 构建 3）通过真实 Sparkle 界面检测到 0.3.0、点击“安装更新”及“安装并重启应用”，从原路径重启成功。新版入口可见；两个账号的结构化草稿、中文/表情/字面脚本文本、任务引用及待办，与更新前备份完全一致。画板 canonical 元素及图片与预置缓存完全一致。

安装验收使用当前源码、相同签名密钥和 Sparkle，但隔离 bundle ID、数据目录与本地更新源。QA 构建号为 4，以高于历史 QA 的 3；正式构建号为 3，高于正式旧版的 2。更新 QA 禁用业务联网，因此该项证明安装和缓存保留，不代表在 QA 中打开了线上画板。正式公开归档和更新源另行验证签名与下载摘要。

本机日常运行的 0.1.0 App 保持运行，未替换其程序或数据；该旧版不含自动更新，需要退出后换用对应账号的新版 App。已带 Sparkle 的旧版可使用菜单“检查更新…”。第二台物理 Mac 的首次安装未在此会话验证；本次沿用内部版签名方式，没有新增 Developer ID 公证。

## 证据

逐项功能结果为 `board-native-results.json`。公开发布验证与生产传输结果汇总于 `board-release-results.json`。私有本机证据保存在不入 Git 的 `artifacts/private/board-qa/` 与 `artifacts/private/board-sparkle/`，包括原生文件选择截图、升级状态、精确草稿比较及缓存比较。签名包留在 `dist/releases/0.3.0/`。
