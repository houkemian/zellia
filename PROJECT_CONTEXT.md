# Zellia 项目上下文入口

> 面向接手本仓库的 AI / 开发者。最后整理：2026-06-17。  
> 强制开发规则见 `AGENTS.md`；本文档用于快速理解产品、架构、关键路径和当前风险。

## 1. 项目定位

Zellia（岁月安）是面向 60 岁以上长辈、慢病管理人群及其家庭照护者的极简健康执行助手。产品核心不是做泛健康数据仓库，而是把每天需要完成的健康动作拆成简单、可坚持、可被家人协同的流程：

- 按时服药并打卡。
- 快速记录血压、血糖等体征。
- 家属在授权后查看、提醒、协助和复盘。
- 复诊前生成周报、临床摘要或 PDF 材料。

产品阶段可按 MVP+ / 早期 Beta 理解：核心闭环已具备，但真实上线前仍需持续加固安全、弱网、权限、数据生命周期和付费一致性。

## 2. 用户与产品原则

主要角色：

- 长辈 / 慢病管理者：每天打开后只需要知道“现在该做什么”。
- 家属 / 守护者：关注执行状态、异常提醒、账号兜底和复诊材料。
- 医生或复诊场景：通常不登录产品，但会消费导出的报告。

体验原则：

- 银发优先：大字号、高对比、大触控区域、低层级。
- 首页优先服务“今日动作”，不要变成复杂控制台。
- 日期、时间、频次优先使用选择器、滚轮、标签，不让用户手填复杂字符串。
- 家属视角必须明确“正在查看谁”“是否只读”“能否管理”。
- 基础健康执行免费，PRO 更适合承载家庭安心、报告、周报、亲情语音、挂件等增值能力。

## 3. 技术架构

后端：

- 目录：`backend/`
- 框架：Python 3.10+、FastAPI、SQLAlchemy、Pydantic / Pydantic Settings。
- 数据库：PostgreSQL 为主，SQLite 仅作开发兼容。
- 迁移：Alembic。不要在请求路径新增运行时 DDL。
- 缓存/临时状态：Redis，用于二维码 token、调度锁、冷却等。
- 认证：Firebase Auth 为主，legacy JWT 兜底。
- 推送：Firebase Cloud Messaging。
- 支付：RevenueCat webhook、PRO 家庭共享。
- 文件/快照：R2/S3 相关服务用于周报冻结、语音或快照类对象。

移动端：

- 目录：`mobile/`
- 框架：Flutter / Dart。
- 网络：`http`，集中在 `mobile/lib/services/api_service.dart`。
- 会话：Firebase current user 优先，legacy JWT 使用 `shared_preferences` 兜底。
- 本地能力：SQLite、离线同步、本地通知、HomeWidget、亲情语音、FCM。
- 国际化：已有 ARB 体系，新增 UI 文案应同步中英本地化，避免硬编码中文。

部署：

- `docker-compose.yml` 包含 backend、Postgres、Redis。
- `/health` 用于 DB / Redis 健康检查。
- 生产环境必须显式配置 `ZELLIA_ENV=production`、强 `SECRET_KEY`、固定 `FIREBASE_PROJECT_ID`、`DATABASE_URL`、`REDIS_URL` 和 Firebase Admin 凭证。

## 4. 关键目录

- `backend/app/main.py`：FastAPI app、中间件、调度任务、路由注册、健康检查。
- `backend/app/models.py`：核心 SQLAlchemy 模型。
- `backend/app/config.py`：环境变量、生产配置校验。
- `backend/app/dependencies.py`：当前用户解析、Firebase ID Token / legacy JWT 鉴权、PRO 状态。
- `backend/app/routers/`：业务接口。
- `backend/app/services/`：通知、周报、R2、快照、订阅等服务。
- `backend/alembic/`：数据库迁移。
- `mobile/lib/main.dart`：Flutter 启动、Firebase 初始化、登录态判断。
- `mobile/lib/services/api_service.dart`：统一 API 客户端、鉴权 header、DTO。
- `mobile/lib/screens/today_screen.dart`：首页核心体验。
- `mobile/lib/screens/family_screen.dart`：家庭协同、绑定、PRO 共享、资料入口。
- `mobile/lib/screens/login_screen.dart`：Firebase 登录、注册、亲情激活。
- `mobile/lib/screens/paywall_screen.dart`：PRO 付费墙。
- `mobile/lib/l10n/`：中英文文案。

## 5. 核心数据模型

以 `backend/app/models.py` 为准，主要实体包括：

- `users`：账号、昵称、邮箱、头像、系统代注册、激活码、会员状态、亲情语音等。
- `medication_plans`：用药计划；`times_a_day` 是逗号分隔时间字符串；`is_active` 用于停药/软删除。
- `medication_logs`：服药打卡记录；按 `plan_id`、`taken_date`、`taken_time` 记录具体时点。
- `blood_pressure_records`：血压与心率记录。
- `blood_sugar_records`：血糖记录。
- `family_links`：长辈与守护者关系、授权状态、权限、备注、周报开关。
- `device_tokens`：推送 token。
- `subscription_events`、`pro_shares`：RevenueCat 订阅事件和 PRO 家庭共享。

重要约束：

- 用药计划删除必须软删除：设置 `is_active=False`，不要 `db.delete()`。
- 家庭成员访问必须校验 `FamilyLink.status == "APPROVED"` 以及对应权限。
- 医疗历史数据删除策略要谨慎；体征删除、日志取消、账号注销如要改动，需要评估连续性和审计。

## 6. 核心业务流程

今日用药：

- `GET /medications/today` 是首页核心接口。
- 后端按当前日期筛选 `is_active=True` 且 `start_date <= today <= end_date` 的计划。
- 拆分 `times_a_day`，将一天多次服药展开为独立待办项。
- 批量关联当天 `medication_logs`，返回每个时点是否已打卡。
- 支持授权家属通过 `target_user_id` 查看。

用药打卡：

- 前端发送 `plan_id`、日期、时间和状态。
- 取消打卡目前涉及历史事实保留风险，修改时要避免破坏依从率和审计。

体征记录：

- 血压、血糖支持新增、分页查询和删除。
- 异常血压/血糖录入后会触发守护者通知链路。
- 后续更推荐软删除或隐藏策略，而不是直接物理删除。

家庭协同：

- 支持邀请码、动态二维码、绑定申请、审核、解绑、家属视角查看。
- 动态二维码 token 存在 Redis，短期有效且一次性消费。
- 代注册会生成系统账号 `zellia_xxxx` 和激活码；激活后可自动建立授权关系。
- 已授权家属可为系统账号长辈重置临时密码。

报告与周报：

- 周报用于家属复盘。
- 临床摘要 / PDF 用于复诊沟通。
- 这些能力适合作为 PRO 价值，但前后端必须保持权益一致。

PRO：

- RevenueCat 承载购买和 webhook。
- `pro_shares` 支持家庭共享，付费主账号可分配共享名额。
- 需要区分本人订阅、被家庭共享、免费用户的可用权益。

## 7. API 概览

常见接口组：

- Auth：`/auth/register`、`/auth/login`、`/auth/me`、`/auth/firebase-login`、`/auth/proxy-register`、`/auth/activate`、`/auth/activate/validate`。
- Medications：`/medications/plan`、`/medications/plan/{plan_id}`、`/medications/today`、`/medications/{plan_id}/log`。
- Vitals：`/vitals/bp`、`/vitals/bs`。
- Family：`/family/invite-code`、`/family/qr-token`、`/family/scan-qr`、`/family/apply`、`/family/requests`、`/family/approved-elders`、`/family/guardians`、`/family/reset-elder-password`。
- Notifications：`/notifications/device-token`。
- Reports：`/reports/clinical-summary`、周报相关接口。
- PRO：`/pro/shares...`。
- System：`/health`。

所有业务接口都应通过 `get_current_user` 或等价依赖校验当前用户。

## 8. 当前已知风险

上线与安全优先级最高：

- Firebase Token 只能接受固定 `FIREBASE_PROJECT_ID`，不要信任 token 自身声明的项目 ID。
- 生产环境必须禁止默认或弱 `SECRET_KEY`。
- RevenueCat webhook 需要幂等和乱序保护，避免旧事件覆盖新权益。
- 激活码验证与激活需要限流、失败次数控制和审计。
- CORS 生产环境应使用显式白名单。

数据与权限：

- 体征删除、账号删除、用药日志取消仍有医疗历史丢失风险。
- 权限解析逻辑分散在多个 router，长期应收敛到统一 dependency / permission service。
- 家属只读、管理权限、PRO 共享和目标用户解析要重点测失败路径。

移动端：

- `TodayScreen` 和 `ApiService` 职责较重，后续维护建议逐步拆分。
- 核心 HTTP 请求应统一超时和结构化错误。
- 离线同步需要区分永久 4xx 和可重试网络错误。
- 硬编码中文文案仍需继续迁移到 l10n。

性能与数据库：

- 高频查询建议补复合索引，例如 `family_links(caregiver_id, elder_id, status)`、`family_links(elder_id, status)`、`medication_logs(user_id, taken_date, plan_id)`。
- 生产环境不要开启全量慢请求 profiling。

## 9. 验证建议

后端改动：

- 优先运行相关 API / service 测试。
- 至少做导入或启动级验证。
- 涉及数据库结构必须新增 Alembic migration。
- 涉及认证、家庭授权、支付、删除、推送必须验证失败路径。

移动端改动：

- 优先运行 `flutter analyze`。
- 对 Today、Family、Login、Paywall、Report 等关键路径运行相关 widget / unit tests。
- 改 UI 时检查银发友好约束：字号、触控区域、文案、只读状态、低层级。

常用命令示例：

```bash
uv run pytest
uv run ruff check backend
cd mobile && flutter analyze
cd mobile && flutter test
```

## 10. 文档策略

- `AGENTS.md`：仓库级强约束规则，AI 修改代码前必须遵守。
- `PROJECT_CONTEXT.md`：项目入口和当前全貌，给接手 AI 先读。
- `docs/Android发布最终审核-2026-06-01.md`：Android 发布前检查记录，保留为发布专项参考。

旧 PRD、阶段性分析、上下文同步、默认模板 README 和重复认证摘要已被本文件吸收或移除，不再作为事实来源维护。
