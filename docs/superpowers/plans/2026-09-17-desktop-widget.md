# mmemo 桌面悬浮工具实施计划

目标：右侧常驻青蛙，单击展开单张毛玻璃待办面板；真实 macOS 窗口。
已确认：用户选择实际清单，要求桌面右侧青蛙入口。界面参考左上卡片。

- [x] 用 AppKit NSPanel + WebKit 复用网页表现和已有 APNG；独立青蛙与面板窗口，不创建全屏透明遮罩。
- [x] 单张卡片，添加、编辑、完成、删除及撤销，日期使用原生输入；初始为空，不填充虚假任务或同步状态。
- [x] Application Support 原子写入 JSON；加载失败显式报错，不覆盖旧数据。
- [x] 右侧贴边上下拖动、记住位置、多屏范围约束、点击外部和 Esc 收起，菜单栏提供打开与退出。
- [x] 最小自动检查覆盖任务验证、日期格式和数据损坏；编译应用并用 Computer Use 验证真实桌面交互。

实现文件：desktop/main.swift（窗口/持久化）、desktop/web/index.html、desktop/web/app.js、desktop/web/model.js、desktop/web/style.css；run.sh 构建并启动 dist/mmemo.app。
本轮边界：本机可用；不冒充已接通双人同步，不自动申请通知权限或开机启动。
