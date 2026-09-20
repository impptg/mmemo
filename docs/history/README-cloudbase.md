# mmemo

macOS 桌面悬浮待办。屏幕右侧的小青蛙是独立透明窗口，点击展开原生毛玻璃面板。

## 运行

双击 `dist/mmemo.app`。源码重新构建并打开：

```sh
./run.sh
```

需要 macOS、Apple Command Line Tools（`swiftc`）。没有 npm 安装步骤，也没有 Electron 或服务器。
本机已验证：Apple Silicon / macOS 26；最低构建目标 macOS 13，其他系统版本尚未实测。
修改源码后请先从菜单栏退出旧版，再运行脚本。仅构建：`./run.sh --build`。

## 使用

- 单击右侧青蛙展开 / 收起；上下拖动青蛙，松手后贴回所在屏幕右侧，记住高度。
- 底部直接与 AI 对话：如“明天下午三点整理周报”“把周报改到四点”“周报做完了”。输入框默认一行，随内容自动增高至最多三行，超出后内部滚动。Enter 发送，Shift+Enter 换行，中文输入法选词不会提交。
- 点击事项前的勾选框直接完成或重新打开事项，保存成功后更新清单；勾选不会插入 token。新增、其他修改和删除仍通过对话处理。
- 单击事项会在输入框插入浅绿色事项标签；Cmd+单击增减多选。引用作为完整 token 编辑、退格删除，发送时携带事项 ID，同名事项也能区分。失败或停止保留草稿，成功后清空；引用本身不会修改事项。
- 多行输入上方各行使用完整宽度，仅末行给发送按钮留位；最多显示三行，超出后滚动。
- 发送期间显示处理状态并禁止重复提交；失败保留输入。所有变更经本地校验并成功保存后，才显示操作回执。
- 顶部筛选按钮仅显示未完成；Esc、点击青蛙或点击面板外收起。
- 到期未完成的数量显示在青蛙角标上；没有请求系统通知权限。
- 菜单栏勾选图标提供展开、打开数据目录和退出。

当前交付是接入真实 AI 的**本机版**。参考图中的双人头像、待对方确认、实时同步尚未接入，不会显示虚假的协作或同步成功。没有开机自启动，也没有系统通知推送。

## 数据

实际事项：`~/Library/Application Support/mmemo/todos.json`。
上次有效版本：同目录 `todos.backup.json`。每次保存采用原子写入；加载错误时禁止覆盖并提示检查文件。窗口位置保存在 `local.mmemo.desktop` 偏好中。

网页界面仅加载应用内资源，禁止远程导航和网页网络连接。原生 Swift 使用 HTTPS 调用模型，事项与对话发送至配置的模型服务。事项和回复使用 `textContent` 渲染，不把模型输出当作 HTML。

## AI 配置

已按用户选择复用本机 d-sre-agent 的默认模型 `deepseek-v4-flash`，使用其配置中的模型网关。配置副本保存在 `~/Library/Application Support/mmemo/ai.json`，权限 `0600`；包含 `name`、`model`、`api_base`、`api_key`，不打包到应用或网页中。以后修改 d-sre-agent 配置不会自动同步这份副本。

模型仅能通过受校验的工具新增、修改和删除待办，不能执行脚本。日期、目标 ID、重复修改与整批数据在写入前验证，保留原有原子保存和备份机制。当前对话上下文只在本次应用运行期间保留；待办会持久化。CloudBase 管理连接已配置，但应用云端同步与系统提醒尚未实现。

## 验证

```sh
node tests/model.test.cjs
node tests/hearts.test.cjs
swiftc -parse-as-library tests/composer.swift -o /tmp/mmemo-composer-check -framework AppKit -framework WebKit
/tmp/mmemo-composer-check
swiftc desktop/Store.swift desktop/AI.swift tests/assistant-check.swift -o /tmp/mmemo-ai-check
/tmp/mmemo-ai-check
# 可选：4 次真实模型请求，使用独立临时数据目录
# /tmp/mmemo-ai-check --live
swiftc desktop/Store.swift tests/storage.swift -o /tmp/mmemo-storage-check
/tmp/mmemo-storage-check
./run.sh --build
codesign --verify --deep --strict dist/mmemo.app
```

`design/` 保留原有网页原型；`desktop/` 是真实桌面实现。视觉和桌面交互检查见 `design-qa.md`。截图中的事项仅为验收数据，交付时已清理。

爱心气泡是统一的未读通知，TODO 到期或对方点击右上角爱心都会触发。lv0 无通知，首次触发为 lv1；未查看每 2 分钟升一级，对方每点击一次再加一级，最高 lv10。lv1–lv10 的间隔依次为 25、20、15、10、7、4、2、1、0.6、0.3 秒；每批分别为 1、1、1、2、2、2、3、3、3、4 颗，同时最多 12 颗，满额时跳过新增，等待旧气泡消失。点击悬浮头像清零，不改变 TODO 完成状态；同一到期时间不会重复触发。通知等级、开始时间和接收去重记录按账号持久化，重启后继续；接收爱心后确认云端收件不会自动清掉本机未读通知。系统开启减少动态效果时显示静态爱心。应用运行时通过现有约 3 秒轮询接收，离线发送失败会提示，已发送的爱心等待对方下次上线接收。

通知验证：`swiftc desktop/Store.swift tests/heart-state.swift -o /tmp/mmemo-heart-state && /tmp/mmemo-heart-state`；`node tests/hearts.test.cjs`；构建后运行 `sh tests/native-hearts.sh` 验证真实双账号发送、加级和头像清零。

## 分离式 AI 对话

AI 输入区位于待办面板底部，状态文字使用青蛙左侧的白色圆角气泡，小尾巴指向青蛙；宽度随文字收缩，仅保留左右留白，不显示打开图标。气泡随青蛙拖动，点击仍可查看完整回复。待办面板与气泡错开，下方空间不足时显示在青蛙上方。过程中每 5 秒轮换「有点晕碳 ...」「小脑袋转转转 ...」「正在冥思苦想 ...」；成功结束显示「大功告成了」，6 秒后隐藏。失败和停止仍归入结束，分别显示失败或停止提示。鼠标悬停暂停消失计时，移开后继续；新请求取消上一轮计时。

气泡只显示一行状态短句，完整内容保留在待办区域的消息面板。点击气泡或右上角「最新消息」可打开，返回按钮恢复待办。处理中展示真实的等待说明，结束后展示本轮回复或失败/停止说明；俏皮话不进入模型对话历史。最新内容不跨应用重启保留。

窗口与消息交互检查（不调用模型、不修改待办）：

```sh
swiftc -parse-as-library tests/message-surfaces.swift -o /tmp/mmemo-surfaces-check -framework AppKit -framework WebKit
/tmp/mmemo-surfaces-check
./tests/native-surfaces.sh
sh tests/native-checkbox.sh
```


## CloudBase 双账号开发（2026-09-17 已接通）

运行 `./dev-pair.sh` 构建并打开两个独立 App；只准备不启动用 `./dev-pair.sh --prepare`。

- `user_pptg` 固定青蛙，`user_mm` 固定小浣熊；待办可指定一人或两人参与，按参与人显示一个或两个头像；两人任务任意一人勾选即整体完成。输入“我们一起买菜”可创建两人待办，引用事项后说“改成两个人一起”可调整参与人。创建者 UID 独立保存且不可修改。
- 双实例连接 CloudBase PostgreSQL 的 `mmemo-development` 空间；首次打开为空，不导入个人实例的历史数据。
- 每 3 秒轮询，打开面板及写入后立即刷新，失败指数退避到 30 秒。是轮询同步，不是实时推送。
- 每个实例独立 bundle ID、会话、窗口偏好、提醒已读记录和 `~/Library/Application Support/mmemo/development/<username>/` 数据目录。普通 `./run.sh` 仍为原有本机模式。
- 账号密码来自仓库外的 `cloudbase-development-users.json`，实例配置与 session 文件权限为 0600；不在 App 包中放密码、模型密钥或管理凭据。开发启动脚本为现有两个固定账号服务，不是完整登录设置界面。
- 数据读取使用用户令牌和 RLS；写入只通过成员校验的 `mmemo_apply` 事务函数，单批最多 20 条，普通用户不能直接写成员表或待办表。
- 不同字段只提交实际改动，同字段按服务器提交顺序生效。网络中断时不自动重试写入；提交结果不明会提示先核对。
- 连接/同步状态保留给辅助阅读，不占用可见的账号状态行。小浣熊侧边入口使用透明眨眼 APNG（来源：`impptg/ppicasso` 提交 `394f4834e475599a3c76e62bc88fba2a89f440b5`，`raccoon-edge-blink-ui.apng`）；青蛙沿用现有动效。

已实测：两账号登录与共享 CRUD、事务失败回滚、创建者不可伪造、匿名访问及直接写表拒绝；两端真实 AppDelegate + WebKit 的定时同步、勾选写回、固定头像与草稿保留。一次真实 AI 新增 -> A 提交 -> B 读取通过，单次模型请求、并发 1、约 5 秒；验收待办已清理。两人参与人校验、共享完成状态、原生双头像和真实 AI“两人一起”创建也已验证（单次请求约 4 秒，测试待办已清理）。离线恢复/会话刷新代码已接入，但尚未做断网与令牌自然过期的长时间测试。

```sh
swiftc -parse-as-library desktop/Store.swift desktop/AI.swift desktop/Cloud.swift tests/cloud-check.swift -o /tmp/mmemo-cloud-check
/tmp/mmemo-cloud-check
sh tests/native-cloud.sh
```

这两个检查会向开发空间临时写入专用测试待办并清理，不调用模型；请在双实例退出后运行，避免测试进程和应用共用会话文件。
