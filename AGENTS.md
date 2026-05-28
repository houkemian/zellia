# AGENTS.md

本文件根据根目录 `.cursorrules` 生成，适用于整个仓库。

## 项目定位

Zellia（岁月安）是面向 60 岁以上长辈和慢病管理家庭的极简健康执行助手。核心目标是把用药、体征记录和家庭协同拆成每天可完成的简单动作。

## 产品与体验原则

- 坚持极简主义，拒绝深层嵌套菜单。
- 面向银发用户时优先保证可读、可点、可完成。
- 正文字号不应低于 18pt，标题建议 24pt 以上。
- 按钮和关键触控区域不得小于 48x48，移动端主要按钮建议高度不低于 56px。
- 使用高对比度配色，优先深蓝、深绿与纯白或浅色背景。
- 日期、时间、频次等输入优先使用原生选择器、滚轮、标签、`DatePicker`、`TimePicker`、`ActionChip`、`InputChip`，避免让长辈手动输入复杂字符串。
- 表单应减少键盘输入，血压、血糖等数值录入应使用大号数字键盘或更易操作的控件。
- 健康历史数据要谨慎处理。用药计划删除必须采用软删除，保留历史医疗档案。

## 技术栈约束

### 后端

- Python 3.10+
- FastAPI
- SQLAlchemy
- PostgreSQL 为主要数据库，SQLite 可作为开发场景兼容
- Pydantic / Pydantic Settings
- JWT OAuth2 兼容，同时项目已接入 Firebase Auth
- Redis 用于二维码 token、调度锁等缓存/临时状态

### 移动端

- Flutter / Dart
- `http` 作为核心网络请求库
- `shared_preferences` 保存 legacy JWT 兜底会话
- `intl` 做日期时间格式化
- Firebase、FCM、RevenueCat、HomeWidget、SQLite 等能力按现有代码结构使用

## 后端开发规范

- 所有业务接口都必须通过 `get_current_user` 或等价依赖校验当前用户。
- 鉴权相关接口保留 `/auth/register`、`/auth/login`，并兼容隐藏路由 `/register`、`/login`。
- 新接口应遵循现有 `backend/app/routers`、`backend/app/schemas`、`backend/app/services` 分层。
- 数据模型以 `backend/app/models.py` 为准，迁移通过 Alembic 管理。
- 不要在请求路径中新增运行时 DDL。
- 业务异常需要返回明确的 HTTP 状态码和可理解的错误信息。
- Redis、S3、Firebase 等外部服务应复用现有客户端/初始化封装，不要在热路径重复创建客户端。
- 对家庭成员数据访问必须校验 `FamilyLink.status == "APPROVED"` 以及对应权限。

## 数据模型约束

核心实体包括：

- `users`：用户、系统账号、激活码、会员状态、家庭语音等资料。
- `medication_plans`：用药计划，`times_a_day` 使用逗号分隔时间字符串，`is_active` 用于软删除。
- `medication_logs`：服药打卡记录，按 `plan_id`、`taken_date`、`taken_time` 记录具体时点。
- `blood_pressure_records`：血压与心率记录。
- `blood_sugar_records`：血糖记录。
- `family_links`：长辈与守护者关系、授权状态、备注和亲情语音。
- `device_tokens`：推送 token。
- `pro_shares` 与 `subscription_events`：PRO 订阅和家庭共享。

用药计划删除时禁止 `db.delete()`；必须将 `is_active` 置为 `False`。

## 核心业务规则

### 今日用药

`GET /medications/today` 是首页核心接口。后端需要：

- 根据当前日期筛选 `is_active=True` 且 `start_date <= today <= end_date` 的计划。
- 拆分 `times_a_day`，将一天多次服药展开为多个独立待办项。
- 批量关联当天 `medication_logs`，返回每个时点是否已打卡。
- 支持授权家属通过 `target_user_id` 查看。

### 体征记录

- 血压、血糖接口需要支持新增、分页查询和删除。
- 异常血压/血糖录入后应触发守护者通知链路。
- 历史记录处理要考虑合规与医疗档案连续性，删除策略变更前需评估。

### 家庭协同

- 邀请码、动态二维码、代注册、激活码、代重置密码都属于高信任操作，必须做用户关系和状态校验。
- 动态二维码 token 必须短期有效并一次性消费。
- 家庭守护视角默认应是只读；管理用药计划等写操作必须检查额外权限。

## Flutter 开发规范

- 保持 `lib/screens`、`lib/services`、`lib/widgets`、`lib/models`、`lib/utils` 的既有结构。
- `api_service.dart` 统一管理网络请求、鉴权 header、401 拦截与 DTO。
- 401 必须清除本地 legacy JWT，并触发回到登录态。
- 首页 `TodayScreen` 是核心体验：用药待办、体征录入、家属视角、报表和 PRO 入口需保持低层级访问。
- 添加药物、选择日期/时间等流程应使用原生选择器和大触控控件。
- 家属查看他人数据时要明确区分只读状态，避免误操作。
- 新 UI 文案需要同步中英文本地化文件，避免新增硬编码中文。

## 质量与验证

- 后端改动优先补充或运行对应 API、服务层测试；至少运行相关静态检查或启动级验证。
- Flutter 改动优先运行 `flutter analyze` 和相关 widget/test。
- 涉及数据库结构的改动必须新增 Alembic migration。
- 涉及认证、家庭授权、支付、删除、推送的改动需要重点验证失败路径。
- 不要提交密钥、Firebase service account、`.env` 或生产凭证。

