# 画板版本发布验证 · 2026-10-09

## 正式发布

- 版本：0.3.1，构建 4，Apple 芯片、macOS 13+。
- 源码：`1f3e30c794f436fec31e4e4b19883718a6e649fa`，已推送 `main`，标签 `v0.3.1` 指向同一提交。
- [GitHub Release](https://github.com/impptg/mmemo/releases/tag/v0.3.1) 已公开；[源码 CI](https://github.com/impptg/mmemo/actions/runs/37888950081) 桌面与后端任务通过。
- [user_pptg 更新源](https://impptg.github.io/mmemo/updates/user_pptg.xml) 与 [user_mm 更新源](https://impptg.github.io/mmemo/updates/user_mm.xml) 均为 0.3.1 / 4，Pages 构建成功。公开 XML 与签名候选逐字节一致，Ed25519 验证成功。
- 两个 ZIP 均可匿名下载，长度及 SHA-256 与清单一致，归档签名有效。正式 App 的 bundle ID、账号、正式更新源和本地资源已检查；没有 QA IPC、账号配置、画板缓存或私钥。

| 账号 | ZIP SHA-256 |
| --- | --- |
| user_pptg | `7bbe514ee767b75e2026fcff6304c269a99fa4fc70806e6fe00de00b58c68b44` |
| user_mm | `de08eca849e64fe6312781ba74b03ab4d144cd12e4b69466d042855fc109a272` |

0.3.1 修复画板隐藏时退出保存等待动画帧的问题：等待文本失焦提交时增加定时回退，隐藏 WebKit 也能完成保存。0.3.0 的归档保持不变，由 0.3.1 取代；如已安装 0.3.0，更新前先打开画板，避免旧版隐藏画板的退出等待。

## 线上服务

ECS 已部署提交 `315136c` 构建的后端，数据库和服务容器均为 healthy。0.3.1 只修改桌面保存等待，后端源码与该部署一致。数据库迁移包括 `001_initial.sql`、`002_board.sql`；Nginx 配置检查和 reload 成功，公开 `/health` 返回 200。

部署前备份为 `mmemo-20261009T052056Z.dump`，部署后备份为 `mmemo-20261009T052432Z.dump`。原有 21 条待办保留；部署后备份恢复到独立临时库，原库和恢复库待办行数及内容摘要一致。画板新增表已存在，备份包含新增表。

两个正式账号分别登录 `https://59.110.153.116`，读取已认证 HTTPS 快照并建立 WSS。双向光标均到达，未认证快照返回 401。此项只验证生产认证与传输，没有创建画板元素、图片或待办；功能、并发和故障恢复通过本机隔离数据库的真实双 App 验收，见 [功能记录](board-acceptance.md)。

## 客户端安装

本机两个独立账号的旧版 QA App（0.2.1，QA 构建 3）通过真实 Sparkle 界面检测到 0.3.1、点击“安装更新”及“安装并重启应用”，从原路径重启成功。新版入口可见；两个账号的结构化草稿、中文/表情/字面脚本文本、任务引用及待办，与更新前备份完全一致。画板 canonical 元素及图片与预置缓存完全一致。升级后两个客户端均在画板从未打开的状态下正常退出，确认进程结束。

安装验收使用当前源码、相同签名密钥和 Sparkle，但隔离 bundle ID、数据目录与本地更新源。QA 构建号为 5，高于已有 QA 的 4；正式构建号为 4，高于此前正式版的 3。更新 QA 禁用业务联网，因此该项证明安装、缓存保留和退出，不代表在 QA 中打开了线上画板。正式公开归档和更新源另行验证签名与下载摘要。

本机日常运行的 0.1.0 App 保持运行，未替换其程序或数据；该旧版不含自动更新，需要退出后换用对应账号的新版 App。已带 Sparkle 的旧版可使用菜单“检查更新…”。第二台物理 Mac 的首次安装未在此会话验证；本次沿用内部版签名方式，没有新增 Developer ID 公证。

## 证据

逐项功能结果为 `board-native-results.json`。公开发布验证与生产传输结果汇总于 `board-release-results.json`。私有本机证据保存在不入 Git 的 `artifacts/private/board-qa/` 与 `artifacts/private/board-sparkle-031/`，包括原生文件选择截图、升级状态、精确草稿比较及缓存比较。签名包留在 `dist/releases/0.3.1/`。
