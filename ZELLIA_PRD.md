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

    后端: Python 3.10+, FastAPI, SQLAlchemy, SQLite。

    前端: Flutter (Dart), http 库, shared_preferences, intl。

    认证: 基于 JWT 的 OAuth2 密码模式。

4. 数据库模型 (Database Schema)

请 Cursor 在检查 models.py 时确保字段一致：

    Users: id, username, hashed_password, invite_code

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

        id, elder_id, caregiver_id, status, permissions

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

    /health (GET)

7. 当前开发进度 (Current Status)

    已完成:

        后端 FastAPI 基础框架、用户认证逻辑。

        用药计划模型与智能展开算法。

        Flutter 登录流、Token 自动持久化、用药打卡 UI、左滑删除交互。

        Vitals（血压/血糖）模块前后端全链路：录入、历史分页、删除、今日摘要。

        Family（亲情账号）模块前后端全链路：邀请码、绑定申请、审核、查看已关联长辈。

        家属查看长辈健康数据（只读模式）：用药与体征接口支持 target_user_id。

        系统健康检查 /health（DB + Redis 状态）。

    进行中 / 可继续优化:

        i18n 与文案统一（Family 页面和部分提示仍有硬编码中文）。

        生产环境安全收敛（调试账号 a/a 逻辑仅建议保留在开发环境）。

        体征记录删除策略是否改为软删除（当前为物理删除，需结合合规要求评估）。

        异常处理体验持续优化（网络超时、弱网重试、用户引导文案）。