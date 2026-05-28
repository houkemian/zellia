# Zellia 前后端代码风险审核

> 审核日期：2026-05-28  
> 审核范围：`backend/`、`mobile/lib/`、`docker-compose.yml`、Alembic 迁移。  
> 审核重点：鉴权、数据权限、支付、生产配置、数据一致性、移动端弱网与同步。

## 高风险

### 1. Firebase Token 校验可能接受非本项目 Token

- 位置：`backend/app/dependencies.py:85`、`backend/app/dependencies.py:123`、`backend/app/dependencies.py:131`；同类逻辑也在 `backend/app/routers/auth.py:66`、`backend/app/routers/auth.py:192`
- 现象：代码从传入 ID token 中解析 `aud` 作为 `project_id`，然后用该值回退调用 Google 公钥校验。也就是说，在 Firebase Admin 未就绪或校验失败后，服务端可能以“token 自己声明的项目 ID”作为 audience 继续验签。
- 影响：如果没有额外比对 `settings.firebase_project_id` 或允许项目白名单，其他 Firebase 项目的合法 ID token 有机会被接受。随后代码会按 email 或 uid 自动创建/激活本地用户，扩大账号接管和越权风险。
- 建议：只允许固定的 `FIREBASE_PROJECT_ID`。回退校验时必须要求 `token_project_id == settings.firebase_project_id`，否则直接 401。不要把 token 内的 `aud` 作为信任根。

### 2. RevenueCat Webhook 缺少事件幂等和乱序保护

- 位置：`backend/app/routers/webhooks.py:102`、`backend/app/routers/webhooks.py:174`、`backend/app/routers/webhooks.py:190`
- 现象：webhook 每次收到事件都会插入 `SubscriptionEvent`，但没有用 `event.id`、`transaction_id` 或 `original_transaction_id + event_type` 做幂等去重，也没有根据事件时间判断新旧。
- 影响：RevenueCat 重试、乱序投递或重复投递时，旧的 `CANCELLATION` / `EXPIRATION` 可能覆盖新的 `RENEWAL`，导致 PRO 权益被错误关闭；重复 `INITIAL_PURCHASE` 也会产生重复事件记录。
- 建议：为 `revenuecat_event_id` 增加唯一约束并做幂等返回；更新用户权益前比较事件时间或订阅过期时间，只允许更新到更可信的新状态。

### 3. 生产 JWT 默认密钥可导致令牌伪造

- 位置：`backend/app/config.py:36`、`backend/app/security.py:25`、`backend/app/security.py:30`
- 现象：`secret_key` 默认值为 `change-me-in-production-use-env`。
- 影响：如果生产环境漏配 `SECRET_KEY`，任何人都能用公开默认密钥伪造 legacy JWT。由于后端在 Firebase 解析失败后会继续尝试 `decode_token`，该兜底链路仍可进入业务接口。
- 建议：增加启动期配置校验。非开发环境下如果 `SECRET_KEY` 为空或等于默认值，应用应拒绝启动。

### 4. 账号删除会物理删除医疗与订阅数据，且外部账号未同步删除

- 位置：`backend/app/routers/users.py:19`、`backend/app/services/account_deletion_service.py:59`、`backend/app/services/account_deletion_service.py:119`
- 现象：`DELETE /users/delete` 会永久删除用户、用药日志、血压血糖记录、订阅事件、家庭关系等；删除完成后只清理 R2 语音对象，没有同步删除 Firebase Auth 用户或 RevenueCat 用户映射。
- 影响：一方面与 `.cursorrules` 中“健康档案软删除”的原则冲突；另一方面外部 Firebase 账号仍可能存在，后续用同一 Firebase token 请求时，`get_current_user()` 可能重新创建本地用户，产生“删除后复活”的账号生命周期问题。
- 建议：区分“注销账号”和“删除医疗档案”。用户表建议软删除/匿名化，医疗记录保留合规审计策略；同步禁用或删除 Firebase Auth 用户；订阅事件建议保留脱敏记录。

## 中风险

### 5. CORS 生产配置过宽

- 位置：`backend/app/main.py:193`
- 现象：`allow_origins=["*"]` 且 `allow_credentials=True`。
- 影响：浏览器 CORS 行为不稳定，也会扩大跨站调用面。当前移动端为主，但一旦加入 Web 管理端或嵌入页面，这个配置会成为生产安全风险。
- 建议：从环境变量读取允许域名白名单，生产环境显式列出 Zellia Web、后台和 API 网关域名。

### 6. 移动端核心 HTTP 请求没有统一超时

- 位置：`mobile/lib/services/api_service.dart:124`、`:133`、`:153`、`:162`、`:174`、`:187`
- 现象：`http.get/post/delete/put/patch` 没有统一 `.timeout(...)`。
- 影响：弱网、DNS 卡死、TLS 握手异常时，登录、首页刷新、离线同步和支付后权益刷新可能长时间悬挂。`SyncManager` 串行同步时，一个请求卡住会阻塞后续队列。
- 建议：在 `ApiService` 底层统一设置连接/响应超时，并把超时错误映射为统一业务异常。同步队列可对单条记录设置更短超时。

### 7. PRO 权限判断只看本账号，不支持被共享账号访问 PRO 报告

- 位置：`backend/app/dependencies.py:172`、`backend/app/dependencies.py:190`、`backend/app/routers/reports.py:341`
- 现象：`/reports/clinical-summary` 使用 `require_pro_user`，只调用 `user_has_active_pro(current_user)`；但项目里另有 `resolve_user_pro_status` / `require_pro_status` 可识别家庭共享 PRO。
- 影响：被 PRO 家庭共享的用户在资料页可能显示有效 PRO，但访问临床摘要报表时仍会被 403，造成付费权益不一致。
- 建议：将临床摘要接口依赖改为 `require_pro_status`，或明确产品规则“共享用户不含临床报告”并在前端隐藏入口。

### 8. 体征删除仍是物理删除，且家属无法按权限协助删除

- 位置：`backend/app/routers/vitals.py:287`、`backend/app/routers/vitals.py:309`
- 现象：血压/血糖删除直接 `db.delete(row)`，且只能删除当前登录用户自己的记录。
- 影响：与用药计划软删除策略不一致。医疗数据一旦删除无法追踪；家属管理场景下也无法纠错长辈误录记录。
- 建议：增加 `is_deleted/deleted_at/deleted_by` 软删除字段；删除接口支持有管理权限的 caregiver 删除目标用户记录，并保留审计。

### 9. 用药日志取消逻辑可能丢失历史打卡事实

- 位置：`backend/app/routers/medications.py:375`、`backend/app/routers/medications.py:377`、`backend/app/routers/medications.py:380`
- 现象：取消打卡时，如果有幂等键会删除该时段所有 `is_taken=True` 日志再插入 tombstone；无幂等键时直接删除该时段所有日志。
- 影响：历史上“曾经打过卡又取消”的事实被物理删除。对医疗审计、依从率复盘、误操作追踪不友好；如果客户端重复请求或乱序同步，也更难还原最终状态。
- 建议：不要删除历史日志，改为追加事件或更新最新状态字段；至少保留 `cancelled_at/cancelled_by` 和原始打卡记录。

### 10. 代注册激活码缺少限流和尝试次数

- 位置：`backend/app/routers/auth.py:333`、`backend/app/routers/auth.py:358`
- 现象：激活码为 6 位大写字母数字，验证和激活接口没有 IP、设备、账号维度限流，也没有失败次数锁定。
- 影响：虽然码空间不算小且 72 小时过期，但公开接口可被自动化撞库；一旦命中即可设置长辈账号密码并自动通过家庭关系。
- 建议：对 `/auth/activate/validate` 和 `/auth/activate` 增加 Redis 限流、失败次数锁定和审计日志；前端不需要频繁调用 validate 时可减少暴露面。

## 低到中风险

### 11. 用药计划输入校验不足

- 位置：`backend/app/schemas/medication.py:4`、`backend/app/routers/medications.py:93`、`backend/app/routers/medications.py:253`
- 现象：`start_date/end_date/times_a_day/name/dosage` 缺少长度、非空、日期顺序和时间格式校验。今日接口遇到非法时段会跳过，但创建/更新时不会阻止脏数据入库。
- 影响：用户可能创建结束早于开始的计划、空药名、超长字段或不可识别时间，导致首页漏展示或后续报表统计异常。
- 建议：在 Pydantic schema 中增加 `min_length/max_length`、`end_date >= start_date`、`times_a_day` 时间列表格式校验。

### 12. 关键权限解析逻辑重复分散

- 位置：`backend/app/routers/medications.py:52`、`backend/app/routers/vitals.py:37`、`backend/app/routers/reports.py:32`、`backend/app/routers/snapshots.py:19`
- 现象：多个路由各自实现 `_resolve_target_user_id`，管理权限又在 medication router 单独实现。
- 影响：后续新增接口时容易漏掉权限条件或权限语义不一致。例如只读、管理、PRO 共享、家庭关系状态的组合规则会越来越难维护。
- 建议：抽到统一 `permissions` 服务或 FastAPI dependency，提供 `resolve_readable_user_id`、`resolve_manageable_user_id` 等明确能力。

### 13. 同步队列遇到永久性 4xx 会无限退避重试

- 位置：`mobile/lib/services/sync_manager.dart:122`、`:153`、`:188`
- 现象：离线同步失败后统一 `incrementRetry`，没有区分 401/403/404/422 与网络错误。
- 影响：已删除计划的打卡、过期会话、schema 校验失败等永久错误会一直留在本地队列，反复重试并污染日志。401 还可能和登出流程产生竞争。
- 建议：让 API 层暴露结构化错误；同步队列对 4xx 分类处理，永久失败进入 dead-letter 状态并提示用户或静默丢弃可恢复项。

### 14. 数据库高频权限查询缺少复合索引

- 位置：`backend/alembic/versions/d4cf556a873d_initial_schema.py`、`backend/app/models.py`
- 现象：`family_links` 只有单列 `caregiver_id/elder_id` 索引，但高频查询经常使用 `(caregiver_id, elder_id, status)` 或 `(elder_id, status)`；`medication_logs` 今日查询常用 `(user_id, taken_date, plan_id)`。
- 影响：家庭成员多、日志量上来后，首页、周报、推送任务可能出现慢查询。
- 建议：新增 Alembic migration，为 `family_links(caregiver_id, elder_id, status)`、`family_links(elder_id, status)`、`medication_logs(user_id, taken_date, plan_id)` 建索引。

## 建议优先级

1. 先修 Firebase 项目 ID 校验、JWT 默认密钥、RevenueCat webhook 幂等，这三项直接影响账号和付费权益安全。
2. 其次处理 CORS、激活码限流、账号删除生命周期，降低生产事故面。
3. 再做移动端 HTTP 超时、同步错误分类、用药/体征软删除，提升弱网和长期数据一致性。
4. 最后收敛权限解析和补复合索引，为后续家庭协同功能扩展打基础。

