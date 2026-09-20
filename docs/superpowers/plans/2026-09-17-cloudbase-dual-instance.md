# CloudBase 双账号联调实施

已批准：user_pptg 固定青蛙、user_mm 固定小浣熊；独立本地实例共享云端待办。

1. 核验两个真实应用用户登录返回的 UID；凭据只读本机受限文件。
2. 版本化迁移：共享成员、待办；SELECT RLS + 受成员校验的事务 RPC，禁止普通用户直接修改成员及写待办表。
3. desktop/Cloud.swift：URLSession 登录/会话刷新、分页读取、事务提交；TaskStore 仅作缓存；创建者 UID 不随我/对方变化。
4. desktop/main.swift：接通登录、轮询、勾选/AI 写入；run.sh + dev-pair.sh：独立 bundle、配置、偏好及位置，账号可辨识。
5. 验证：真实 A/B CRUD、创建者稳定、事务回滚、未登录拒绝、身份隔离、已有 UI/存储测试和构建，启动双实例。模型先只做最小一次联调。
