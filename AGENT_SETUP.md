# mmemo：让 Agent 一句话完成配置

把下面一句话发给可以操作本机文件和终端的 Agent（如 Codex）。密码和 API Key 放在本机私有文件中，只把文件路径告诉 Agent。

> 请读取 https://github.com/impptg/mmemo/blob/main/AGENT_SETUP.md，帮我安装并配置 mmemo：使用账号 user_mm，从本机私有文件 `<配置文件绝对路径>` 读取服务地址、密码和模型设置，保留已有待办与其他账号配置，完成登录和模型连通性验证后启动该账号的 App；不要输出密码、Key 或令牌。

已有安装时可使用：

> 请按照 mmemo 仓库中的 AGENT_SETUP.md，从 `<配置文件绝对路径>` 更新 user_mm 的账号密码和模型配置，保留未指定的字段与已有数据，验证后重启这个账号的 App。

## 给用户：私有配置文件

在仓库外创建 JSON 文件，权限设为 `0600`。以下只是模板，尖括号内容必须替换为真实值；不要提交填好的文件。

```json
{
  "username": "user_mm",
  "baseURL": "https://<你的 mmemo 服务地址>",
  "password": "<已有账号的登录密码>",
  "ai": {
    "name": "<模型显示名称>",
    "model": "<服务商提供的准确模型 ID>",
    "api_base": "https://<兼容 OpenAI Chat Completions 的 API 根地址>/v1",
    "api_key": "<模型 API Key>"
  }
}
```

`baseURL` 是 mmemo 后端地址；`ai.api_base` 是模型服务地址，两者不同。程序会在模型地址后自动追加 `/chat/completions`，不要重复填写该路径。是否需要 `/v1` 取决于服务商。账号密码也不是模型 API Key。

更新配置时可以只提供要修改的字段，`username` 必须保留。没有提供的字段沿用已有值；首次安装必须补齐必填项。不确定服务地址或密码时向服务管理员获取，不要猜测。

## 给 Agent：以当前代码为准执行

### 1. 检查安装与输入

- macOS 13 或以上，具备 Xcode Command Line Tools（`swiftc`）、Python 3 和 Git。只构建桌面端不需要 Node、pnpm 或 Docker。
- 已有仓库时检查工作区并保留用户改动；首次安装克隆 `https://github.com/impptg/mmemo.git`。不要覆盖已有目录。
- 读取 `apps/desktop/Store.swift`、`Cloud.swift`、`AI.swift` 和 `main.swift`，核对配置字段和账号映射；版本变化时以代码为准。
- 只读取用户指定的私有文件或该账号已有配置。不打印其内容，不把密码放进命令行参数、日志、提交信息或聊天回复。缺少首次安装必需信息时，只询问缺失项。

目前代码仅支持以下两个固定身份，不能通过修改 JSON 注册新用户：

| username | uid | 角色 |
| --- | --- | --- |
| `user_pptg` | `2100541450115510274` | 青蛙 |
| `user_mm` | `2100541456125558785` | 浣熊 |

服务端账号必须已经存在。本流程配置的是客户端登录密码，不会修改服务端密码。`apps/server/src/bootstrap.ts` 只初始化缺失账号，重复运行不会重置已有密码；用户要求注册任意账号或重置服务端密码时，应说明当前限制，另行处理服务端流程。

### 2. 写入该账号配置

先退出目标账号的 App，避免覆盖或继续使用旧配置；不要退出其他账号。配置目录为：

```text
~/Library/Application Support/mmemo/development/<username>/
```

目录权限 `0700`，配置文件权限 `0600`。使用程序内 JSON 序列化与原子替换写入，临时文件从创建起就设为 `0600`，不要通过拼接含密码的 shell 命令写文件。修改已有文件前在仓库外保存同等权限的备份。

- `server.json`：字段为 `baseURL`、`username`、`password`、`uid`、`deviceId`。按上表确定 UID；已有设备保留 `deviceId`，首次生成 UUID。服务地址必须是 HTTPS，去掉末尾 `/`。
- `ai.json`：字段为 `name`、`model`、`api_base`、`api_key`。把输入的 `ai` 对象合并至原配置；地址必须是 HTTPS，模型 ID 和 Key 不能为空。
- `server-session.json`：由应用登录后生成，不能自行伪造。服务地址、账号或密码变更时，在安全备份后移除旧会话，让应用重新登录。仅改模型配置无需清除登录会话。
- 不改待办文件，不写旧的 `cloud.json` / `session.json`，不复制另一个账号的模型密钥。现有 `scripts/provision-local.py` 会配置两个账号并使用固定部署地址，不适合任意用户的单账号安装。

### 3. 构建并准备独立 App

在仓库根目录运行 `./run.sh --build`，生成 `dist/mmemo.app`。此基础包未绑定账号，不能直接作为双人同步账号版启动。

只配置一个账号时：

1. 用 `ditto` 把基础包复制到 `dist/mmemo-<username>.app`。
2. 使用 Python `plistlib` 修改复制包的 `Contents/Info.plist`：`MMemoAccount` 设为用户名，`CFBundleName` 设为 `mmemo <username>`，`CFBundleIdentifier` 设为 `local.mmemo.desktop.<username 中的下划线替换为连字符>`。
3. 修改后执行 `codesign --force --sign - <该 App 的路径>`，再执行 `codesign --verify --deep --strict <该 App 的路径>`。
4. 用 `open <该 App 的路径> --args --show` 启动目标账号。

两个账号均已配置时，可使用 `./dev-pair.sh --prepare` 构建两份独立包；`./dev-pair.sh` 会同时打开两者。不要为了使用双实例脚本而索取另一个账号的密码。

### 4. 验证并报告

- 校验 JSON 必填字段、账号/UID 对应关系、UUID、目录及文件权限、App 的 `MMemoAccount` 和签名。
- 通过可信 HTTPS 请求 `GET /health`；在内存中读取密码调用 `POST /auth/login`，请求体为 `username` 和 `password`，可设置 `x-device-id`；核对返回的 `sub` 与 UID 一致。响应令牌仅在内存中使用，不输出完整响应。
- 用获取的访问令牌调用 `GET /v1/todos`，确认读取成功，仅报告成功与否，不输出用户待办内容。不要为了安装验证创建或删除待办。
- 按 `AI.swift` 的真实请求结构验证模型：`POST <api_base>/chat/completions`、Bearer Key、`stream: false`、`respond` function tool 和强制 `tool_choice`。发送“只回复连接成功，不修改待办”，验证返回恰好一个 `respond` 调用，参数含非空 `reply` 和空数组 `changes`。不要应用返回的任何变更。普通聊天请求成功不代表工具调用兼容。
- 当前代码对 `api.deepseek.com` 自动发送 `thinking: {"type":"disabled"}`。验证时保持一致，并向用户说明：思考模式已关闭，以兼容强制工具调用，待办操作仍通过结构化工具返回。`ai.json` 没有 thinking 开关；第三方代理也不会自动命中此域名条件。
- 启动后确认目标账号的进程、登录/同步状态和模型响应。若缺少 UI 操作能力，应明确只完成哪些检查，不把 API 成功当成界面验收通过。
- 最终只报告账号、服务地址、模型名称/ID、App 路径、验证结果以及未完成项；密码、API Key 和会话令牌始终不展示。认证失败时报告状态码和脱敏原因，不擅自重置账号或关闭 TLS 验证。

## 维护参考

桌面配置实现见 `apps/desktop/{Store,Cloud,AI,main}.swift`；账号契约见 `packages/contracts/src/index.ts`；自托管后端部署见 [运维说明](docs/implementation/operations.md)。本指南不自动部署后端，也不迁移或清空现有数据。
