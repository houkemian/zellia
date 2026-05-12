# Zellia 上下文同步文档

> 目的：供下一个 Context 在 1-2 分钟内快速理解当前开发状态与接手点。  
> 更新时间：2026-05-12（第四次）

## 1) 当前已完成的核心功能

### A. 专业级医疗报表 PDF 导出
- 后端：`GET /reports/clinical-summary`
  - 文件：`backend/app/routers/reports.py`
  - 支持：`days`、`target_user_id`
  - 返回：用药依从性、平均血压/心率、血压/血糖历史列表
- 前端：
  - API：`mobile/lib/services/api_service.dart` -> `getClinicalSummaryReport(...)`
  - PDF：`mobile/lib/services/pdf_service.dart`
    - 使用 `PdfGoogleFonts.notoSansSCRegular/Bold` 解决中文字体
  - 入口：`mobile/lib/screens/today_screen.dart` AppBar 导出按钮（`Icons.picture_as_pdf`）

### B. 异常体征与漏服预警（推送）
- 数据模型：
  - `backend/app/models.py` 新增 `DeviceToken`
- Token 上报接口：
  - `POST /notifications/device-token`
  - 文件：`backend/app/routers/notifications.py`
- 异常体征实时推送：
  - 文件：`backend/app/routers/vitals.py`
  - 血压/血糖录入后立即阈值判断并通知关联 caregiver
- 漏服定时任务：
  - 文件：`backend/app/services/notification_service.py`
  - 任务：`check_missed_medications(db)`（每小时）
- 调度注册：
  - 文件：`backend/app/main.py`
  - APScheduler job: `missed-medications`

### C. 家庭健康周报 Weekly Digest（邮件）
- 周报模板：
  - 文件：`backend/templates/weekly_digest.html`
- 周报服务：
  - 文件：`backend/app/services/weekly_digest_service.py`
  - 流程：查询已绑定关系 -> 聚合近7天 -> Jinja2渲染 -> SMTP并发发送
  - 健壮性：单封失败隔离，不中断批次
- 复用聚合：
  - `backend/app/routers/reports.py` 新增 `build_clinical_summary(db, user_id, days)`
- 周报订阅字段：
  - `backend/app/models.py` 中 `FamilyLink.receive_weekly_report`
- 订阅开关接口：
  - `PUT /family/links/{link_id}/weekly-report`
  - 文件：`backend/app/routers/family.py`
- 前端开关 UI：
  - 文件：`mobile/lib/screens/family_screen.dart`
  - 守护者端已绑定家人卡片三点菜单内含周报开关

### D. 用户个人资料（Profile）
- 数据模型：`backend/app/models.py` 中 `User` 新增 `nickname`、`email`、`avatar_url`
- 运行时迁移：`backend/app/dependencies.py` -> `_ensure_user_profile_columns(db)`（同时在 `auth.py` 各入口调用）
- 接口：
  - `GET /auth/me` → 返回当前用户昵称/邮箱/头像
  - `PUT /auth/me` → 更新昵称/邮箱/头像（邮箱前端只读，不允许用户修改）
- 前端：
  - DTO：`mobile/lib/services/api_service.dart` -> `CurrentUserProfileDto` + `getCurrentUserProfile()` / `updateCurrentUserProfile()`
  - 入口：`mobile/lib/screens/family_screen.dart` 顶部个人信息头部 → 铅笔图标跳转 `_ProfileSettingsScreen`
  - 昵称可编辑，邮箱只读（`readOnly: true, enabled: false`），无头像链接字段

### E. 家庭账号关联页全面重构（family_screen.dart）
- **文案适配更广泛家庭关系**（不限"长辈/子女"，夫妻/平辈均适用）：
  - 上半卡片：`让家人守护我`
  - 下半卡片：`我要守护家人`、列表标题：`我关注的家人`
  - 邀请码输入提示：`家人邀请码` / `给 TA 写个备注`
- **顶部个人信息头部**：
  - CircleAvatar（半径34）+ 昵称（24sp 粗体）+ 邮箱 + 修改资料图标
  - 浅绿色背景 + 阴影与下方功能卡片区分层级
  - 当前查看状态行：用 `RichText` 高亮家人名字（深绿色加粗）；正在查看他人时右侧出现 `⇄ 切回我的` 胶囊按钮（`AnimatedSwitcher` 动画）
- **我关注的家人**：
  - 移至顶部个人信息头部下方单独展示
  - 自定义卡片替代嵌套 Card+ListTile，`InkWell` + 圆角边框
  - 正在查看的家人：头像变深绿、右侧显示"查看中"绿色标签
  - 三点菜单（`⋮`）收纳：每周健康邮件 Switch + 取消关注（红色）
- **让家人守护我**：
  - 待审核申请、我的守护者（已授权）：无数据时整块隐藏
  - 邀请码上方增加引导说明文字（"家人扫码后将看到您的身份为：[昵称]"）
- **我要守护家人**：
  - 申请绑定按钮改为全宽、图标+文字（`FilledButton.icon`，高 56px，深绿色）
  - 弹窗从 `AlertDialog` 改为 `showModalBottomSheet`：拖动条 + 引导文案 + 大字邀请码输入框 + 备注输入框 + 取消/提交双按钮

### F. 代注册重构为“系统自动账号”模式（2026-04-24，激活链路 2026-05 已接 Firebase）
- 后端模型变更（`backend/app/models.py`）：
  - `users.username` 收敛为 `String(20)`；新增 `is_proxy: bool`
  - 保留 `activation_code`、`activation_expires_at` 以承载激活流程
- 认证路由（`backend/app/routers/auth.py`）：
  - `POST /auth/proxy-register` 入参改为 `{nickname, elder_alias?}`
  - 自动生成唯一账号：`zellia_` + 4~6 位数字
  - 返回 `{elder_user_id, username, activation_code}`
  - `POST /auth/activate/validate`：服务端校验激活码（非仅客户端长度校验）
  - `POST /auth/activate`：设密码、清激活码、将关联 `FamilyLink` 置 `APPROVED`；优先返回 `firebase_custom_token`（Custom Auth），若 Admin 无法签发则返回 `access_token`（JWT 兜底，见 **H**）
  - Admin 可用时：先 `create_user(uid=username)` 再 `create_custom_token`，便于 Firebase 控制台可见用户
- 家庭路由（`backend/app/routers/family.py`）：
  - 新增 `POST /family/reset-elder-password`
  - 限制：仅与目标长辈存在 `APPROVED` 关系的 caregiver 可调用
  - `approved-elders` 返回新增 `elder_is_proxy`（前端菜单分支判断）
- Flutter API 层（`mobile/lib/services/api_service.dart`）：
  - `proxyRegisterElder(...)` 改为仅昵称主输入
  - `validateActivationCode(...)`、`activateElderAccount(...)`（解析 `firebase_custom_token` / `access_token`）；JWT 兜底时 `setLegacyJwt` / `restoreLegacyJwt` / `clearLegacyJwt`（`SharedPreferences`）
  - 新增 `resetElderPassword(...)`
- 家庭页（`mobile/lib/screens/family_screen.dart`）：
  - “为家人新建账号”流程改为仅输入昵称
  - 成功卡片展示“登录账号 + 激活码”（均为大字号）
  - 已绑定家人三点菜单中，对 `elder_is_proxy=true` 增加“帮他重置密码”
- 登录/激活页（`mobile/lib/screens/login_screen.dart`）：
  - 主登录：Firebase 邮箱（需验证）+ Google/Microsoft；`main.dart` 以 `FirebaseAuth.currentUser` 或 legacy JWT 判定已登录
  - 亲情激活向导 Step3：`signInWithCustomToken` 或写入 legacy JWT；成功弹窗 `_FamilyActivationSuccessDialog`（渐变顶栏、可复制账号、SnackBar）

### G. 动态二维码扫码守护（2026-04-24）
- 后端（`backend/app/routers/family.py`）：
  - 新增 `GET /family/qr-token`：生成 `zellia://bind?token=<uuid>`，Redis TTL=180 秒
  - 新增 `POST /family/scan-qr`：校验并一次性删除 token，创建/复用 `FamilyLink`（`PENDING`）
  - Redis 连接增强：`rediss://` 兼容、socket 超时配置
  - 新增错误日志：记录 `redis_prefix(scheme://host:port)` + `error_type`（用于线上 503 排查）
- 前端：
  - `mobile/lib/services/api_service.dart`：新增 `getFamilyQrToken()`、`scanFamilyQr(...)`
  - `mobile/lib/screens/family_screen.dart`：
    - 邀请码区新增“二维码”按钮，弹窗显示动态二维码 + 倒计时 + 刷新
    - 守护操作区新增扫码按钮，扫码后可填写备注并发起绑定
  - 新增 `mobile/lib/screens/qr_scanner_screen.dart` 全屏扫码页（`mobile_scanner`）
  - 权限：
    - Android `CAMERA` 权限已添加
    - iOS `NSCameraUsageDescription` 已添加

### H. Firebase Admin、会话与 Docker 凭证（2026-05）
- **客户端会话**：`mobile/lib/main.dart` — `FirebaseAuth.instance.currentUser` 或 `ApiService.hasLegacySession`（亲情激活 JWT 兜底）；`ApiService._headers` Bearer 优先 Firebase ID Token，否则 legacy JWT；401 时 `clearLegacyJwt` + `signOut`。
- **后端鉴权**：`backend/app/dependencies.py` — `get_current_user` 先解析 Firebase ID Token 映射 `User`（email / `username == firebase uid`），失败再解码旧 JWT。
- **Admin 单点初始化**：`backend/app/firebase_app.py` — `ensure_firebase_app_ready()` / `load_firebase_service_account_certificate()`  
  - 凭证优先级：`FIREBASE_CREDENTIALS_JSON`（整段 JSON，适合 K8s/Docker Secret）→ `GOOGLE_APPLICATION_CREDENTIALS`（容器内路径）→ `FIREBASE_CREDENTIALS_PATH` / settings（多候选路径：`/run/secrets/<basename>`、`BACKEND_ROOT/<basename>` 等）  
  - **Docker**：`WORKDIR /app` 镜像内**不存在**宿主机 `/home/ubuntu/...`；须 **volume 挂载到容器路径** 或 **`FIREBASE_CREDENTIALS_JSON`**，否则日志会提示 host 路径在容器内不可见。
- **配置加载**：`backend/app/config.py` — `BACKEND_ROOT` 下 `backend/.env` 优先于 cwd `.env`，避免 systemd/容器 cwd 与仓库根不一致导致读不到 `FIREBASE_*`。
- **推送复用**：`backend/app/services/notification_service.py` — `_try_init_firebase()` 调用 `ensure_firebase_app_ready()`。
- **Dockerfile**：`/app` 下运行说明注释（Firebase 路径须在容器内可见）。

## 2) 近期关键文件（优先阅读顺序）

1. `backend/app/models.py`
2. `backend/app/config.py`（含 `BACKEND_ROOT`、`.env` 解析）
3. `backend/app/firebase_app.py`（Admin 初始化与凭证解析）
4. `backend/app/routers/auth.py`
5. `backend/app/dependencies.py`（Bearer：Firebase / JWT）
6. `backend/app/schemas/auth.py`
7. `backend/app/routers/family.py`
8. `backend/app/routers/reports.py`
9. `backend/app/routers/vitals.py`
10. `backend/app/routers/notifications.py`
11. `backend/app/services/notification_service.py`
12. `backend/app/services/weekly_digest_service.py`
13. `mobile/lib/main.dart`
14. `mobile/lib/services/api_service.dart`
15. `mobile/lib/screens/login_screen.dart`
16. `mobile/lib/screens/family_screen.dart`
17. `mobile/lib/screens/today_screen.dart`
18. `mobile/lib/l10n/app_zh.arb` / `app_en.arb`

## 3) 运行配置（必须检查）

### 后端环境变量（建议在 `backend/.env`，与进程 cwd 无关）
- `DATABASE_URL`（使用 PostgreSQL）
- `REDIS_URL`
- **Firebase Admin（推送 + 校验 ID Token + 亲情码 Custom Token，至少配一种）**
  - `FIREBASE_CREDENTIALS_PATH`：**容器/进程内可读**的 service account JSON 路径（Docker 勿填宿主机 `/home/...` 除非已挂载）
  - 或 `FIREBASE_CREDENTIALS_JSON`：整段 JSON 字符串（适合 Secret 注入）
  - 或 `GOOGLE_APPLICATION_CREDENTIALS`：标准 GCP 凭证文件路径（容器内）
  - 可选：`FIREBASE_PROJECT_ID` / `GOOGLE_CLOUD_PROJECT`
- `SMTP_HOST`
- `SMTP_PORT`（默认 587）
- `SMTP_USERNAME`
- `SMTP_PASSWORD`
- `SMTP_FROM_EMAIL`
- `SMTP_USE_TLS`（默认 true）

### Flutter/Firebase
- Android：`google-services.json`
- iOS：`GoogleService-Info.plist`
- 已接入依赖：`firebase_core`、`firebase_auth`、`firebase_messaging`、`flutter_local_notifications` 等
- 会话：`ApiService` 使用 `FirebaseAuth.instance.currentUser?.getIdToken()`；亲情激活 JWT 兜底见 `SharedPreferences` key `zellia_legacy_jwt`

## 4) 当前已知风险 / 注意项

- `username` 当前兼作登录账号；`email` 字段已独立，注册时自动从 `username` 推导，但老账号需运行时迁移补齐。
- **PostgreSQL 布尔默认值**：所有运行时 `ALTER TABLE ... BOOLEAN DEFAULT` 已修正为 `TRUE/FALSE`（不再用 `1`）。
- SQLite 下 `ALTER TABLE` 迁移为运行时兜底方式，长期建议改 Alembic 迁移。
- 推送与邮件均依赖外部服务配置，配置缺失时会记录 warning 并跳过发送。
- 个人资料页邮箱设为只读（不允许用户改），避免与登录账号脱钩。
- **Docker 部署 Firebase**：`.env` 中 `FIREBASE_CREDENTIALS_PATH=/home/ubuntu/...` 在容器内无效；须挂载到如 `/app/secrets/xxx.json` 并改路径，或改用 `FIREBASE_CREDENTIALS_JSON`。
- **双会话形态**：同时存在 Firebase 用户与 legacy JWT 时，以 Firebase token 优先；登出时应同时 `signOut` + `clearLegacyJwt`（`today_screen.dart` 已处理）。

## 5) 下一个 Context 建议优先事项

1. 生产 Docker：确认 Firebase 凭证以 **volume 或 `FIREBASE_CREDENTIALS_JSON`** 注入，并核对 `backend/.env` 中路径为容器内路径。
2. 补 `backend/.env.example`（含 `FIREBASE_CREDENTIALS_JSON` / `FIREBASE_CREDENTIALS_PATH` Docker 说明、SMTP、Redis）。
3. 补 Alembic migration，替换所有运行时 `ALTER TABLE` 逻辑（已有 `nickname`、`email`、`avatar_url`、`receive_weekly_report`、`notify_missed` 等新列）。
4. 跟进线上 `/family/qr-token` 503：根据 `redis_prefix + error_type` 日志定位 Redis。
5. 代注册/亲情激活：可选审计留痕（creator、IP）；长期可评估去掉 legacy JWT，仅保留 Custom Token + Firebase。
6. 为周报/预警链路补集成测试（mock SMTP 与 FCM）；可选「手动触发周报」调试接口（仅开发环境）。

## 6) 最近提交（用于定位变更）

- `f7f4b43` fix(firebase): robust credentials path; provision Auth users; activation UI
- `bb22dca` fix(backend): load backend/.env for Firebase; centralize Admin init
- `e58def9` feat(auth): migrate family activation to Firebase Custom Auth
- `e7c836b` Migrate session auth to Firebase ID tokens and enforce verified email sign-in.
- `82ed519` Add family profile header and broaden family copy.
- `779aae0` Fix PostgreSQL boolean defaults in runtime schema updates.
- `9cd5d33` Enable Android desugaring for flutter_local_notifications AAR checks.
- `d52ffea` Add missed-dose reminder settings and caregiver poke flow.
- `98f745f` Implement alerts, push notifications, and weekly health digest delivery.
- `8586d6e` Add clinical summary report export for follow-up visits.
