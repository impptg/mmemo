# 更新验收记录 · 2026-09-21

## 测试边界

本机 Apple 芯片 Mac 的独立 mmemo QA 副本。两种账号均使用真实 AppKit/WebKit/Sparkle 更新代码，但编译时隔离数据目录、禁用业务服务器，并增加仅 QA 存在的测试命令入口。没有覆盖日常应用，没有操作真实待办。不能据此声称已在第二台 Mac 完成首次安装。

## 已验证

- Sparkle 2.10.0 官方包 SHA-256 与固定配置一致。
- 最小临时签名、未公证应用通过标准 UI 完成版本 1→2 的替换与自动重启。
- 两种 mmemo QA 应用均经后台检查发现 0.2.1，显示“有新版本”菜单，不抢焦点。
- 手动检查打开中文更新说明、下载并验证签名；点击“安装并重启应用”后，从构建号 2 升级为 3，进程 PID 改变。
- 重启后账号、数据目录、待办及账号配置哨兵文件保持不变；中文、多行、emoji、字面量 `<script>` 文本和事项引用恢复正确。
- 模拟请求仍在进行时，安装被退出保护拒绝；清除忙碌状态后从原更新会话继续安装成功。
- 退出保存改为 WebKit 回调后，普通退出实际结束进程，双账号再次完成 2→3 更新与草稿恢复。
- 升级后手动检查显示“您使用的就是最新版”。
- 有效签名清单指向错误签名归档时，下载后明确拒绝安装；构建号 3 的原进程继续运行。
- 篡改已签名清单后，明确拒绝该清单。
- 停止隔离 HTTP 服务后，手动检查显示获取升级信息失败；当前应用继续运行。
- 草稿单元测试覆盖 Unicode/引用往返、0600 权限、非法结构/超限拒绝、拒绝后保留原文件及清空。
- 现有客户端 model/hearts 测试及 pnpm check 通过。
- 开发应用 MMemoUpdatesEnabled=false，且无 SUFeedURL。

## 未公证分发的实际限制

正式候选包的 `codesign --verify --deep --strict` 通过，但 `spctl --assess --type execute` 返回 rejected（退出码 3）。这两件事不矛盾：应用结构签名完整，不代表受 Gatekeeper 信任。

本机临时签名应用已实际完成更新重启；尚不能保证另一台 Mac 在下载带隔离标记的首个安装包时不会阻止运行。首次安装须由用户确认来源并按系统逐应用允许流程处理。没有关闭 Gatekeeper，也没有为验收批量移除隔离标记。

## 证据

本地私有验收目录：artifacts/private/update-qa/，包含 upgrade-results.json、签名清单、两个版本的实际应用与归档。私有目录不上传 GitHub。

## 发布与线上验证

- 源码提交：cd0cb2bcb11bfeb6c5f92ed6f646407c547ae960，已合入 main；标签 v0.2.0 对应同一提交。
- GitHub Desktop checks 成功：https://github.com/impptg/mmemo/actions/runs/35527493399 。
- Release 已公开：https://github.com/impptg/mmemo/releases/tag/v0.2.0 。
- 两个账号 arm64 ZIP 均匿名下载成功，下载字节的 SHA-256 与构建清单相同。
- Pages 状态 built，HTTPS 强制开启，来源 gh-pages 分支；两个线上 XML 均通过签名验证，且与发布产物逐字节相同。
- user_pptg ZIP SHA-256：d60c65d2c012c013dd3fae53b195e83ee5ba9fa7cd520ff66ffd932fee2fed3a。
- user_mm ZIP SHA-256：51d951d8011de17bbe9505f66ee9aa729690464e22aa86fb97219b1910412a3c。
- 发布包的 Bundle ID、账号、构建号 2、arm64 架构均核对通过，不含 QA 命令入口。
- 最终回调实现的双账号 2→3 重启与草稿验证记录在 final-upgrade-results.json；正常退出与草稿一致性记录在 shutdown-results.json。测试应用和本地 HTTP 服务已关闭。

## 后续用户侧验收

另一台 Mac 尚未操作。本期交付是两个账号包、线上更新源、可重复发布脚本和本机双账号真实升级证据；首次安装仍需在各自机器手动进行，并确认系统是否要求逐应用允许运行。日常旧版未被本次测试覆盖。
