Zellia (岁月安) - 项目现状同步 PRD（2026-04-24）

## 1. 项目定位与目标

- 产品名称：Zellia（岁月安）
- 核心受众：60 岁以上长辈、慢病管理人群及其家属/照护者
- 目标：将“服药执行 + 体征记录 + 家庭协同”简化为可持续完成的日常动作

## 2. Git 仓库信息

- 项目 Git 地址已更新为：`https://github.com/houkemian/zellia.git`

## 3. 当前技术架构

- 后端：Python + FastAPI + SQLAlchemy
- 数据层：PostgreSQL + Redis（健康检查与缓存依赖）
- 前端：Flutter（移动端）
- 认证：JWT（OAuth2 Password）

## 4. 核心数据模型（已实现）

- `users`：`id`, `username(20)`, `hashed_password`, `nickname`, `email(nullable)`, `avatar_url`, `is_active`, `is_proxy`, `invite_code`, `activation_code`, `activation_expires_at`
- `medication_plans`：`id`, `user_id`, `name`, `dosage`, `start_date`, `end_date`, `times_a_day`, `is_active`
- `medication_logs`：`id`, `plan_id`, `user_id`, `taken_date`, `taken_time`, `is_taken`, `checked_at`
- `blood_pressure_records`：`id`, `user_id`, `systolic`, `diastolic`, `heart_rate`, `measured_at`
- `blood_sugar_records`：`id`, `user_id`, `level`, `condition`, `measured_at`
- `family_links`：`id`, `elder_id`, `caregiver_id`, `status`, `permissions`

## 5. 已上线业务能力

### 5.1 认证与会话

- 注册、登录接口可用（`/auth/register`, `/auth/login`）
- 移动端完成 Token 本地持久化
- API 层统一处理 401：触发登出并回到登录态

### 5.2 用药管理

- 支持创建、查询、停药（软删除）
- 今日用药接口支持计划展开（`times_a_day` 拆分为独立待办）
- 支持用药打卡与取消打卡
- 打卡记录包含 `checked_at` 时间，前端已展示
- 允许家属在授权后以只读模式查看长辈今日用药（`target_user_id`）

### 5.3 生命体征

- 已完成血压/血糖新增、分页查询、删除接口
- 查询接口支持 `page/page_size` 分页参数
- 查询接口支持在家庭授权场景下按 `target_user_id` 查看长辈数据
- 前端已完成：
  - 血压录入弹窗（收缩压/舒张压/心率可选）
  - 血糖录入弹窗（数值 + 场景）
  - 历史记录弹窗（按日期分组 + 无限滚动分页 + 左滑删除）
  - 今日摘要展示（当天最近一条）

### 5.4 亲情账号协同（新功能）

- 长辈可获取邀请码（`/family/invite-code`）
- 子女可通过邀请码申请绑定（`/family/apply`）
- 长辈可查看待审核申请并同意/拒绝（`/family/requests`, `/family/requests/{link_id}/decision`）
- 子女可查看已通过关联的长辈列表（`/family/approved-elders`）
- 前端新增“亲情账号关联”页面，并支持一键切换“查看谁的数据”

### 5.5 代注册（系统自动分配 ID）与代重置密码

- 子女可在“为家人新建账号”中仅输入昵称，后端自动生成系统账号（`zellia_` + 4~6 位数字）
- 代注册接口返回 `username + activation_code`，前端以高对比/大字号卡片展示，便于截图或抄写
- 长辈登录页支持“我有亲情激活码”三步向导，激活后自动通过亲情绑定并直接登录
- 激活成功后弹窗明确提示系统登录账号，降低遗忘风险
- 已授权子女可对系统账号执行“帮他重置密码”（临时密码）

### 5.6 动态二维码扫码守护（新增）

- 与静态邀请码并存，支持 3 分钟时效动态 token 扫码绑定
- 后端 Redis 承载一次性 token：`token -> elder_user_id`，TTL=180 秒
- 扫码绑定默认创建 `PENDING` 关系，仍需长辈审核
- 前端支持：
  - 长辈端展示动态二维码 + 倒计时 + 刷新
  - 守护者端全屏扫码 + 备注输入 + 绑定提交
- 线上故障排查增强：后端记录 Redis 地址前缀与异常类型日志（用于 503 定位）

### 5.7 运行与健康检查

- 提供 `/health`：返回 DB 与 Redis 可用性状态
- `docker-compose` 已包含 backend + postgres + redis 完整联调环境

## 6. API 清单（当前实现）

- Auth
  - `POST /auth/register`
  - `POST /auth/login`
  - `POST /auth/proxy-register`
  - `POST /auth/activate`
  - （兼容隐藏路由：`/register`, `/login`）
- Medications
  - `POST /medications/plan`
  - `GET /medications/plan`
  - `DELETE /medications/plan/{plan_id}`
  - `GET /medications/today`
  - `POST /medications/{plan_id}/log`
- Vitals
  - `POST /vitals/bp`
  - `GET /vitals/bp`
  - `DELETE /vitals/bp/{record_id}`
  - `POST /vitals/bs`
  - `GET /vitals/bs`
  - `DELETE /vitals/bs/{record_id}`
- Family
  - `GET /family/invite-code`
  - `GET /family/qr-token`
  - `POST /family/apply`
  - `POST /family/scan-qr`
  - `GET /family/requests`
  - `POST /family/requests/{link_id}/decision`
  - `GET /family/approved-elders`
  - `POST /family/reset-elder-password`
- System
  - `GET /health`

## 7. 与旧 PRD 相比的关键同步点

- 生命体征模块不再“待开发”，已进入可用状态（含历史与删除）
- 新增“亲情账号”全链路功能（邀请码、申请、审核、已关联、代看）
- 用药与体征查询已支持 `target_user_id` 家庭授权视角
- 文档中的 Git 仓库地址已更新为新地址
- 亲情代注册模式已升级为“系统自动账号（zellia_xxxx）+ 激活码”闭环
- 增加“代重置密码”接口，解决系统账号无邮箱找回问题
