Zellia (岁月安) - 产品功能与技术同步文档
Git 仓库地址: https://github.com/houkemian/zellia.git
1. 项目概览

    产品名称: Zellia - 岁月安

    核心受众: 60岁以上中老年人、慢病管理群体及其家属。

    核心价值: 消除长辈对复杂APP的恐惧，将繁琐的医嘱（用药、监测）转化为极其简单的“打钩”和“录入”动作。

2. 设计原则 (UI/UX 规范)

Cursor 在生成前端代码时必须遵循以下准则：

    极简主义: 拒绝深层嵌套，主要功能必须在 1-2 次点击内触达。

    高可读性:

        正文字号不得低于 18pt，标题字号 24pt 以上。

        高对比度色彩（推荐深蓝/深绿配纯白背景）。

    防误触: 按钮高度不低于 56px，卡片间距适中。

    输入优化:

        严禁让用户手动输入日期/时间字符串。

        必须调用原生 showDatePicker 和 showTimePicker。

        血压、血糖数值尽量使用滚轮或大号数字键盘。

3. 技术栈

    后端: Python 3.10+, FastAPI, SQLAlchemy, PostgreSQL。

    前端: Flutter (Dart), http 库, shared_preferences, intl。

    认证: 基于 JWT 的 OAuth2 密码模式。

4. 数据库模型 (Database Schema)

请 Cursor 在检查 models.py 时确保字段一致：

    Users: id, username(系统账号/邮箱登录), hashed_password, nickname, email(nullable), avatar_url, is_active, is_proxy, invite_code, activation_code, activation_expires_at

    MedicationPlans (用药计划):

        id, user_id, name, dosage, start_date, end_date

        times_a_day: 存储为逗号分隔字符串 (例如 "08:00,12:00,18:00")

        is_active: 默认为 True (用于软删除)。

    MedicationLogs (服药记录):

        id, plan_id, user_id, taken_date, taken_time, is_taken, checked_at

    BloodPressureRecords:

        id, user_id, systolic, diastolic, heart_rate, measured_at

    BloodSugarRecords:

        id, user_id, level, condition (空腹/餐后), measured_at

    FamilyLinks (亲情账号关联):

        id, elder_id, caregiver_id, status, permissions, elder_alias, caregiver_alias, receive_weekly_report

5. 核心业务逻辑实现
A. 用药排班算法 (重点)

    逻辑: 当用户访问“今日”页面时，后端不只是查询数据库，而是实时计算。

    实现: 筛选所有 is_active=True 且 start_date <= 今天 <= end_date 的计划。将 times_a_day 拆分，每个时间点生成一个独立的 TodayMedicationItem 返回给前端。

    打卡: 前端点击打钩时，向后端发送 {plan_id, date, time, is_taken}。

B. 软删除策略

    逻辑: 长辈点击“停药”或“删除”时，禁止调用 db.delete()。

    实现: 将 is_active 字段更新为 False。确保该记录在历史统计中可见，但在今日待办中消失。

6. 接口规范 (API Endpoints)

所有业务接口需带 Authorization: Bearer <token> 头部。

    /auth/register, /auth/login （兼容隐藏路由 /register, /login）

    /auth/me (GET) - 获取当前用户 nickname/email/avatar_url

    /auth/me (PUT) - 更新用户昵称/邮箱/头像

    /auth/proxy-register (POST) - 子女代创建长辈系统账号（自动生成 zellia_xxxx + 激活码）

    /auth/activate (POST) - 长辈使用激活码设置密码并自动激活/自动通过亲情绑定

    /medications/plan (POST/GET)

    /medications/plan/{plan_id} (DELETE, 软删除)

    /medications/today (GET)

    /medications/{plan_id}/log (POST)

    /vitals/bp (POST/GET/DELETE) - 已上线，支持分页查询与删除

    /vitals/bs (POST/GET/DELETE) - 已上线，支持分页查询与删除

    /family/invite-code (GET)

    /family/apply (POST)

    /family/requests (GET)

    /family/requests/{link_id}/decision (POST)

    /family/approved-elders (GET)

    /family/guardians (GET) - 已授权守护者列表（长辈视角）

    /family/links/{link_id}/weekly-report (PUT) - 切换周报订阅

    /family/unbind/{link_id} (DELETE) - 解绑

    /family/reset-elder-password (POST) - 已授权子女代长辈重置临时密码

    /notifications/device-token (POST) - 上报 FCM Token

    /reports/clinical-summary (GET) - 临床摘要报表（支持 target_user_id）

    /health (GET)

7. 当前开发进度 (Current Status)

    已完成:

        后端 FastAPI 基础框架、用户认证逻辑。

        用药计划模型与智能展开算法；漏服提醒推送（APScheduler + FCM）。

        Flutter 登录流、Token 自动持久化、用药打卡 UI、左滑删除交互。

        Vitals（血压/血糖）模块前后端全链路：录入、历史分页、删除、今日摘要、异常体征推送。

        Family 模块全链路：邀请码、绑定申请、审核、守护者视角切换（只读模式）、解绑、alias 备注。

        家庭健康周报邮件（每周日 20:00）：`receive_weekly_report` 开关 + 三点菜单 UI。

        专业 PDF 临床摘要报表导出（`pdf` 库 + Google Fonts 中文字体）。

        用户 Profile 管理：`GET/PUT /auth/me`，前端昵称编辑 + 资料页面（邮箱只读）。

        亲情账号关联页面全面重构：顶部个人信息头 / 查看状态高亮 / 切回按钮 / 底部申请绑定抽屉 / 三点菜单整合操作。

        PostgreSQL 兼容性修正：布尔类型默认值改为 `TRUE/FALSE`。

        系统健康检查 /health（DB + Redis 状态）。

    进行中 / 可继续优化:

        i18n 与文案统一（family_screen 部分辅助文案仍有硬编码中文）。

        生产环境安全收敛（调试账号 a/a 逻辑仅建议保留在开发环境）。

        体征记录删除策略是否改为软删除（当前为物理删除，需结合合规要求评估）。

        异常处理体验持续优化（网络超时、弱网重试、用户引导文案）。

        Alembic 迁移补全（当前 nickname/email/avatar_url/receive_weekly_report 等新列均为运行时兜底 ALTER）。

        代注册能力（系统自动账号模式）已上线：

            产品方案:
                子女仅填写长辈昵称，系统自动生成唯一登录账号（格式 zellia_ + 4~6 位数字）。
                同步生成 6 位激活码（72 小时有效），长辈在登录页走“我有亲情激活码”完成激活与设置密码。
                激活成功后自动将 FamilyLink 从 PENDING 升级到 APPROVED，并返回 Token 直接登录。

            已实现接口:
                POST /auth/proxy-register
                    入参: { nickname, elder_alias? }
                    出参: { elder_user_id, username, activation_code }
                POST /auth/activate
                    入参: { activation_code, new_password }
                    出参: { access_token, token_type, username }
                POST /family/reset-elder-password
                    入参: { elder_id, temp_password }
                    约束: 仅 APPROVED 关系下的 caregiver 可调用

            兜底机制:
                系统账号无邮箱找回能力，子女可通过“代重置密码”帮助长辈恢复登录。
                激活成功弹窗会明确告知“登录账号为 zellia_xxxx”，降低遗忘风险。

        动态二维码扫码守护（与静态邀请码并存）已上线：

            已实现接口:
                GET /family/qr-token
                    鉴权: 已登录用户
                    逻辑: 生成 UUID，写入 Redis，TTL=180 秒
                    出参: { qr_payload, expires_in }
                POST /family/scan-qr
                    鉴权: 已登录用户
                    入参: { token, family_alias? }
                    逻辑: Redis 校验并一次性删除 token，创建/复用 FamilyLink（PENDING）
                    出参: { success, link_id, status, elder_id, elder_username, elder_nickname }

            前端实现:
                family_screen 增加“生成动态二维码”入口与 3 分钟倒计时刷新弹窗。
                family_screen 增加“扫码”入口，新增全屏扫码页 qr_scanner_screen（mobile_scanner）。
                扫码识别 zellia://bind?token= 后输入备注并提交绑定申请。

            当前排查:
                线上仍出现 /family/qr-token 的 503，已补后端 Redis 错误日志：
                记录 Redis 地址前缀（scheme://host:port）与异常类型（error_type），用于快速定位配置/网络/TLS 问题。

        扫码守护流程（通过扫码快速发起并完成家庭守护关系绑定）。
            注：以下为早期草案，当前实现以 `/family/qr-token` + `/family/scan-qr` 为准。

            产品目标:
                用扫码替代手动输入邀请码，减少输入错误并提升绑定成功率与操作速度。
                支持近场场景（同一空间）快速互联，覆盖夫妻互查、平辈互查、子女守护等关系。

            接口草案:
                GET /family/guardian-qr
                    出参: { qr_payload, expires_at, nonce }
                POST /family/guardian-scan
                    入参: { qr_payload, relation_alias? }
                    出参: { link_id, status, requires_approval }
                POST /family/guardian-scan/{link_id}/confirm
                    入参: { approved, permissions }
                    出参: { link_id, status, permissions }
                安全建议:
                    二维码短时效(例如 60-120 秒)、一次性 nonce、防重放签名校验。

            风险点:
                安全风险: 截图转发/重放攻击导致误绑定，需要时效+签名+二次确认。
                误操作风险: 面对面扫码过快可能误绑错误对象，需明显展示“将绑定到谁”确认页。
                兼容性风险: 低端机摄像头识别与弱网场景下扫码失败率，需要降级到手动邀请码流程。