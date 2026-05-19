# Zellia（岁月安）项目技术分析报告

> 分析日期：2026-05-18  
> 分析范围：后端 (FastAPI) + 前端 (Flutter) + 部署配置

---

## 一、项目概览

Zellia 是一款面向 60 岁以上中老年人的家庭协同健康管理工具，核心功能涵盖用药打卡、血压/血糖记录、亲情账号协同、健康周报推送。技术栈为 Python FastAPI + PostgreSQL + Redis + Flutter，已进入 MVP+ 可用阶段。

---

## 二、接口性能风险

### 2.1 ~~漏服检查定时任务存在 N+1 查询~~ ✅ 已修复 (2026-05-18)

**文件**: `backend/app/services/notification_service.py`

已将逐个 `db.get(User, plan.user_id)` 改为批量加载 `user_map`，并将 `MedicationLog` 查询从逐 slot 检查改为一次批量 `taken_slots` 集合查找。

修复要点：
- `user_ids = list({plan.user_id for plan in plans})` → 批量加载 User 到 `user_map`
- `select(MedicationLog.plan_id, MedicationLog.taken_time).where(...)` → 一次查询构建 `taken_slots` 集合
- 循环体内仅做 `user_map.get()` 和 `(plan.id, slot_time) in taken_slots` 的 O(1) 查找

---

### 2.2 ~~临床摘要接口无分页、全量加载~~ ✅ 已修复 (2026-05-18)

**文件**: `backend/app/routers/reports.py`

改动要点：
- **聚合统计下推到 DB 层**：`AVG(systolic/diastolic/heart_rate)` + `SUM(CASE ...)` 替代 Python 层逐行计算，单个查询返回汇总值
- **记录列表分页**：新增 `record_page`（默认 1）和 `record_page_size`（默认 50，上限 100）参数，列表查询加入 `LIMIT/OFFSET`
- **响应结构增强**：`blood_pressure_summary` 和 `blood_sugar_summary` 新增 `total_count`；新增 `record_pagination` 字段告知当前页信息
- **血糖异常检测也在 DB 层统一**：`CASE WHEN level < 3.9 OR (fasting AND > 6.1) OR (non-fasting AND > 7.8)`

---

### 2.3 ~~Redis 连接未复用~~ ✅ 已修复 (2026-05-18)

**文件**: `backend/app/redis_client.py`（新增）、`backend/app/main.py`、`backend/app/routers/family.py`、`backend/app/routers/medications.py`

新增 `redis_client.py` 提供线程安全的缓存客户端工厂 `get_redis()`，基于 `(url, timeout_params)` 元组缓存 `Redis` 实例，底层连接池自动复用。所有历史裸 `Redis.from_url()` 调用点已替换为 `get_redis()`，健康检查改用 `ping_redis()`，应用关闭时通过 `close_redis_clients()` 清理。

---

### 2.4 用药计划字符串解析重复计算（低危）

**文件**: `backend/app/routers/medications.py` 第 274 行

```python
slots = [s for s in (x.strip() for x in plan.times_a_day.split(",")) if s]
```

每次请求 `GET /medications/today` 都对所有活跃计划的 `times_a_day`（如 `"08:00,12:00,18:00"`）进行字符串拆分和解析。`today` 接口是 App 首页核心接口，调用频率极高。可考虑在模型层缓存解析结果（添加 `cached_slots` 属性或 DB 计算列）。

---

### 2.5 ~~血压/血糖分页查询缺少总数字段~~ ✅ 已修复

**文件**: `backend/app/routers/vitals.py`、`backend/app/schemas/vital.py`、`mobile/lib/services/api_service.dart`、`mobile/lib/screens/today_screen.dart`

`GET /vitals/bp` 与 `GET /vitals/bs` 现返回 `{ items, total, page, page_size }`。移动端历史列表用 `total` 判断 `_hasMore`（`_records.length < total`），不再依赖「本页条数是否等于 page_size」。

---

### 2.6 ~~健康检查端点每次创建 Redis 连接~~ ✅ 已修复

**文件**: `backend/app/redis_client.py`、`backend/app/main.py`

`GET /health` 经 `ping_redis()` 使用与业务相同的 `get_redis()` 缓存客户端（连接池复用），不再为健康检查单独 `Redis.from_url()` 或使用独立超时参数另建连接池。定时任务锁、用药戳冷却等调用点亦统一为默认 `get_redis()`。

---

### 2.7 缺失关键数据库复合索引

| 表 | 当前查询模式 | 缺失索引 |
|---|---|---|
| `family_links` | `WHERE caregiver_id=X AND elder_id=Y AND status='APPROVED'` | `(caregiver_id, elder_id, status)` |
| `medication_logs` | `WHERE user_id=X AND taken_date=Y AND plan_id IN (...)` | `(user_id, taken_date, plan_id)` |
| `device_tokens` | `JOIN family_links ON caregiver_id` | `family_links(caregiver_id, status)` 的覆盖索引 |

`schema_bootstrap.py` 中已为 `blood_pressure_records` 和 `blood_sugar_records` 创建了 `(user_id, measured_at DESC)` 索引，但上述关键查询路径缺乏覆盖。

---

### 2.8 PyInstrument 全量 Profiling 开关（高危配置）

**文件**: `backend/app/main.py` 第 76-99 行

```python
class PyInstrumentProfilerMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if settings.enable_slow_request_profiling:
            profiler = Profiler(async_mode="enabled")
            profiler.start()  # 每个请求启动 profiler
```

代码注释已指出 "heavily slows serialize_response under load" 且默认关闭 — 这是正确的。但该中间件在**所有环境**均注册（第 170 行 `app.add_middleware(PyInstrumentProfilerMiddleware)`），即使 profiling 关闭，仍有一个 `perf_counter()` 调用和阈值比较。虽开销极小，值得在文档中强调**生产环境不要开启** `ENABLE_SLOW_REQUEST_PROFILING=true`。

---

## 三、程序崩溃 / 稳定性风险

### 3.1 ~~APScheduler 多 Worker 重复执行~~ ✅ 已修复 (2026-05-18)

**文件**: `backend/app/main.py`

通过 Redis 分布式锁 (`SETNX`) 防止多 worker 重复执行定时任务。每个 job 在执行前尝试获取锁：
- `_run_missed_medications_job` → 锁 `scheduler:lock:missed_medications`，TTL=3500s（略短于 1 小时间隔）
- `_run_weekly_summary_job` → 锁 `scheduler:lock:weekly_summary`，TTL=3600s（覆盖周报发送窗口）

Redis 不可用时降级为直接执行（宁可重复也不漏报），并通过 WARNING 日志记录。

---

### 3.2 ~~调试后门未做环境隔离~~ ✅ 已删除 (2026-05-18)

**文件**: `backend/app/routers/auth.py`

已移除 `DEBUG_USERNAME = "a"` / `DEBUG_PASSWORD = "a"` 常量定义及 `login()` 函数中自动创建 `a/a` 测试账号的代码块（原第 216-230 行）。login 路径现在仅做标准用户名-密码验证，不再存在任何硬编码后门。

---

### 3.3 JWT 密钥默认值泄漏风险（中危）

**文件**: `backend/app/config.py` 第 33 行

```python
secret_key: str = "change-me-in-production-use-env"
```

如果部署时忘记在 `.env` 中覆盖 `SECRET_KEY`，所有 JWT 令牌将使用硬编码的默认密钥签发。任何人都可以伪造有效的 JWT 令牌。

---

### 3.4 CORS 配置过于宽松（中危）

**文件**: `backend/app/main.py` 第 172-178 行

```python
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True)
```

`allow_origins=["*"]` + `allow_credentials=True` 组合是违反 CORS 规范的危险配置，浏览器会拒绝此组合。同时允许任意来源携带凭据存在 CSRF 风险。

---

### 3.5 ~~运行时 DDL 的并发风险~~ ✅ 已修复

**文件**: `backend/alembic/`、`backend/app/db_migrate.py`、`backend/app/models.py`；已删除 `schema_bootstrap.py`

- 新增 Alembic 初始迁移 `d4cf556a873d_initial_schema`（与 `models.py` 一致，含体征复合索引）。
- 应用启动时执行 `alembic upgrade head`，不再 `create_all` + 请求路径内 `ALTER TABLE`。
- 已移除 `auth` / `family` / `medications` / `reminders` / `dependencies` / `webhooks` / `clinical_snapshot_service` 中全部运行时 DDL。
- **已有库升级**：若表结构已与当前模型一致，部署前执行一次 `cd backend && alembic stamp head`；新库由启动迁移自动建表。

---

### 3.6 ~~Flutter 端 Timer 泄漏风险~~ ✅ 已修复 (2026-05-18)

**文件**: `mobile/lib/screens/today_screen.dart`

Timer 改为按需启动（仅冷却期内运行），新增 `_stopCooldownTicker()` / `_syncCooldownTicker()` / `_onCooldownTick(Timer)` 三个方法管理完整生命周期。`dispose()` 兜底取消，回调内 `!mounted` 时自取消，冷却期满自动停止。

---

### 3.7 Flutter 端异常处理不完整（中危）

**文件**: `mobile/lib/services/api_service.dart` 第 197-200 行

```dart
Future<void> _handleUnauthorized(http.Response response) async {
    if (response.statusCode == 401) {
        await clearLegacyJwt();
        onUnauthorized?.call();
    }
}
```

`_handleUnauthorized` 仅处理 401。对于 500/503/网络超时等错误，直接抛出异常给调用方。如果调用方（如 `today_screen.dart` 的 `_refreshMedications()`）未包裹 try-catch，将导致未捕获异常传播到 Flutter 框架层，可能触发应用的红色错误屏幕。

---

### 3.8 Firebase 认证单点故障（中危）

**文件**: `backend/app/dependencies.py` 第 127-171 行

如果 Firebase 服务不可用（或服务账号密钥过期），`get_current_user()` 将无法验证任何 Firebase 令牌。虽有 JWT 降级路径（`decode_token`），但主要认证路径依赖外部服务。

---

## 四、APP 功能建议

### 4.1 健康数据可视化（趋势图表）

当前体征模块仅展示列表和今日摘要。建议增加：
- 血压/血糖 7 天 / 30 天趋势折线图
- 用药依从率（打卡率）周/月趋势
- 异常事件时间轴标记

这将大幅提升用户（尤其是家属端）的数据感知价值。

---

### 4.2 离线模式与本地队列

考虑到老年用户可能处于弱网环境（家中 Wi-Fi 不稳定、外出时无网络），建议：
- 用药打卡、体征录入支持离线暂存（SQLite 本地队列）
- 网络恢复后自动同步
- 冲突策略：以服务器时间为准，本地记录作为补充

---

### 4.3 药物库存 / 处方续期提醒

当前用药计划仅有 `start_date` 和 `end_date`。建议增加：
- 药物总剂量 / 每日用量 → 自动计算耗尽日期
- 提前 N 天提醒「需要续方 / 购药」
- 子女端可见药物剩余天数

---

### 4.4 紧急求助 (SOS)

针对独居老人场景：
- 首页常驻 SOS 按钮
- 一键向所有已授权家属发送紧急通知（含定位信息）
- 支持预设紧急联系人电话号码自动拨打

---

### 4.5 语音交互增强

当前已支持「家属语音提醒」(family voice) 功能。可进一步扩展：
- 长辈端语音输入体征数值（「血压 135 85」→ 自动解析录入）
- 语音播报今日用药清单（适合视力不佳的老人）
- 语音确认打卡（「已服药」→ 自动标记）

---

### 4.6 用药提醒灵活度提升

当前 `times_a_day` 为固定时间点字符串。建议：
- 支持「每 N 小时」模式（如每 8 小时，适用于抗生素）
- 支持「饭前/饭后」语义化时间
- 允许家属为特定计划设置自定义提醒铃声

---

### 4.7 健康周报 PDF 一键分享

当前已有 PDF 导出能力。建议：
- 添加「分享给医生」功能（生成脱敏版 PDF + 分享链接）
- 支持 WhatsApp / 微信 / 邮件一键分享
- 医生端查看页（限时 Token 访问）

---

### 4.8 多长辈管理优化

对于同时照护父母双方的子女用户：
- 首页快速切换卡片（不必进入 family 页面）
- 聚合视图：「所有长辈今日用药总览」
- 异常体征统一预警面板

---

### 4.9 国际化补齐

PRD 已标识 `family_screen` 部分文案硬编码中文。建议：
- 完成全部用户可见文案的 i18n 提取
- 增加日语、韩语（东亚老龄化市场需求）
- 英语版本适配欧美华人社区

---

### 4.10 数据安全与合规增强

- 体征数据端到端加密（E2EE）
- 数据导出支持 GDPR/个人信息保护法合规格式
- 账户删除（真删除，非软删除）的数据清除审计日志

---

## 五、优先级摘要

| 优先级 | 类别 | 问题 | 影响 |
|--------|------|------|------|
| 🔴 高危 | 稳定性 | ~~APScheduler 多 worker 重复执行~~ ✅ 已修复 | 用户收到重复推送/周报 |
| 🔴 高危 | 安全 | ~~调试账号 `a/a` 无环境隔离~~ ✅ 已删除 | 生产环境存在后门 |
| 🔴 高危 | 性能 | ~~漏服检查 N+1 查询~~ ✅ 已修复 | 用户增长后定时任务超时 |
| 🔴 高危 | 性能 | ~~临床摘要全量加载无分页~~ ✅ 已修复 | 大数据量下 OOM |
| 🟡 中危 | 安全 | JWT 默认密钥、CORS 配置 | 令牌可伪造、CSRF 风险 |
| 🟡 中危 | 稳定性 | ~~运行时 DDL 在执行路径中~~ ✅ 已修复 | 锁表导致请求超时 |
| 🟡 中危 | 稳定性 | ~~Flutter Timer 泄漏~~ ✅ 已修复；异常处理待定 | App 崩溃/内存泄漏 |
| 🟡 中危 | 性能 | ~~Redis 连接未复用~~ ✅ 已修复 | 高并发连接数耗尽 |
| 🟢 低危 | 性能 | ~~分页接口缺 total 计数、缺失复合索引~~ ✅ 已修复 | 查询效率下降 |

---

以上分析基于当前代码库的静态审查。建议优先处理 🔴 高危项，尤其是 APScheduler 重复执行和调试账号隔离，这两个问题在生产环境中会直接造成用户可感知的故障。
