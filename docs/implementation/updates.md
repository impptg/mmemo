# mmemo 内部更新

## 范围

Apple 芯片、macOS 13+、现有 user_pptg 与 user_mm 两个独立应用。Sparkle 2.10.0 官方二进制固定 SHA-256；更新包和更新清单均使用 Ed25519 签名。自动检查默认由 Sparkle 询问是否开启，开启后约每 6 小时检查；应用退出时不检查。后台更新以菜单栏圆点和“有新版本”菜单提醒，不抢焦点。手动检查使用中文标准更新窗口。

用户确认后才下载和安装；不启用无人值守安装。有 AI 请求、待办写入或爱心发送进行中时，安装/退出会被拒绝，完成后可从菜单继续。重启前冻结输入并原子保存草稿；保存失败保留当前进程。文本和事项引用按结构化数据保存，不恢复 HTML。数据与账号配置保留在原 Application Support 目录。

## GitHub 布局

- 源码：impptg/mmemo 的 main。
- 安装包：GitHub Releases，标签 v<version>。
- 更新清单：gh-pages 分支的 updates/user_pptg.xml 与 updates/user_mm.xml。
- 固定地址：https://impptg.github.io/mmemo/updates/user_pptg.xml 与 https://impptg.github.io/mmemo/updates/user_mm.xml。
- Pages 只托管静态文件，无更新 API、数据库或后台常驻进程。
- .github/workflows/desktop.yml 验证构建、草稿与客户端模型；发布暂由本机脚本执行，签名私钥不进入 CI。

## 首次安装

1. 从 Releases 下载自己账号对应的 arm64 ZIP，退出旧版，解压后将应用放入可写位置（推荐 ~/Applications 或 /Applications），覆盖相同账号的旧应用。不要从 ZIP/只读磁盘镜像内部运行。
2. 旧版没有 Sparkle，因此第一次需要手动替换；此后通过菜单更新。
3. 现有账号配置不包含在安装包中。已有配置继续使用，首次配置另见 AGENT_SETUP.md。
4. 本版本没有付费 Developer ID 签名和 Apple 公证。系统评估会拒绝自动信任；仅在确认来源与下载内容后，按 macOS“系统设置 → 隐私与安全性”里的逐应用允许流程操作。不同系统版本提示可能不同；遇到无法允许的情况停止并收集原始提示，不能承诺免交互安装。
5. 不要全局关闭 Gatekeeper、不要移除系统整体安全策略。Sparkle 签名保证更新来源，不等价于 Apple 公证。

## 发布步骤

1. 编辑 config/release.json 的 version 与递增整数 build；不改变两个 Bundle ID、账号标识或 feedBaseURL。
2. 写 docs/releases/<version>.txt。完成测试并提交，将该源码提交推送到 GitHub。
3. 在本机执行：

```sh
python3 scripts/release-desktop.py --notes docs/releases/0.2.0.txt
python3 scripts/release-desktop.py --publish dist/releases/0.2.0
```

默认私钥位置为 .secrets/mmemo-sparkle.key，要求 0600。它是 base64 编码的 Ed25519 seed。公钥在 config/release.json；脚本发布前验证二者匹配。必须在密码管理器/安全离线介质备份这一个私钥；不要在聊天、提交、日志或 Release 中展示私钥。丢失密钥会使现有临时签名客户端无法继续信任新更新，需手动重新安装带新公钥的基础版。

脚本生成两个干净应用，保留 Sparkle 官方签名的辅助组件，对主应用临时签名；验证应用签名、归档签名、清单签名、私有文件排除。发布顺序为：标签和 Release → 上传全部资源 → 发布 Release → 匿名下载比对 SHA-256 → 原子更新 gh-pages 分支两个清单 → Pages 部署。发布后检查 Pages 状态并实际下载两个线上清单验证签名，不能把“请求部署成功”当作已经上线。

GitHub 授权使用现有 Git 凭据或 GH_TOKEN/GITHUB_TOKEN，只在内存中使用。不要将凭据写进脚本。重复发布只能接受完全相同的资产，不覆盖已发布包；修改代码必须增加版本和构建号。

## 开发与隔离验收

`./run.sh --build` 与 `./dev-pair.sh` 都是开发构建，更新入口禁用，不连接正式更新源。

```sh
python3 tests/prepare-update-qa.py
python3 -m http.server 18766 --bind 127.0.0.1 --directory artifacts/private/update-qa
```

启动 artifacts/private/update-qa/2 下的两个应用。它们使用独立 Bundle ID、独立 mmemo/update-qa/<account> 数据目录且不连接业务服务器。通过 tests/update-command.py 可控制检查、模拟忙碌和查询状态；IPC 只编译进 QA 应用，不进入发布包。GUI 安装确认仍由标准 Sparkle 窗口执行。不要把 QA 包上传为正式 Release。

至少验证：两种应用 2→3 真替换并重启、后台提醒、手动检查、已是最新、忙碌拒绝退出、中文及多行和引用草稿恢复、账号/数据/配置不变、坏签名拒绝、断网错误、开发构建不自动更新。测试进程及文件仅用于隔离验收，不能替代第二台真实机器的首次安装验收。

## 故障恢复

- 下载或签名失败不替换正在运行的应用。
- 发布上传失败时保留旧清单，修复并重试同一发布；不能覆盖不同内容的既有资产。
- 有缺陷的版本先从两个清单撤下并重新签名，阻止尚未更新的用户继续安装；已安装用户不会自动降级，发布更高 build 的修复版。
- 本期不迁移本地数据格式，不删除配置和待办；后续格式升级必须另设迁移与备份验收。
- 不保证未公证软件在每一版 macOS 上都能无提示自动重启；若系统阻断，保留安装包和日志，改用手动安装或正式 Developer ID + 公证。

Apple 关于未公证应用的官方说明：https://support.apple.com/102445 。Sparkle 发布与签名说明：https://sparkle-project.org/documentation/publishing/ 。
