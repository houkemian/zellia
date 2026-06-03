# Handoff

## Goal

Keep Zellia moving with the latest state captured for the next agent/session. The recent work focused on:

- Reducing Neon CU-Hours by changing Docker liveness checks so they do not probe the database.
- Adding and refining a Flutter “极简模式 / Simple mode” for the home and family screens.
- Producing project/product/risk analysis Markdown documents.
- Starting, then later removing/replacing, local Postgres setup attempts as requested.

## Current Repository State

- Branch: `main`
- Working tree: clean at the time this handoff was written.
- Latest pushed commit: `b86561a fix: simplify caregiver section in simple mode`
- Remote: `origin/main` has received all committed work through `b86561a`.

## Files Changed Recently

### Runtime / Backend

- `backend/app/main.py`
  - Added `GET /live`, which returns `{"status": "ok"}` and does not touch DB/Redis.
  - Kept `GET /health` as the deeper DB + Redis health endpoint.

- `docker-compose.yml`
  - Changed backend container healthcheck from `/health` to `/live`.
  - Reason: `/health` ran `SELECT 1` every 30 seconds, keeping Neon active and increasing CU-Hours.

### Flutter UI

- `mobile/lib/screens/today_screen.dart`
  - Added persistent local “极简模式 / Simple mode” switch using `SharedPreferences`.
  - When enabled, top-right AppBar actions hide PRO, weekly summaries, and PDF export.
  - In simple mode, only the Family care button remains on the right.
  - Passes `simpleMode` into `FamilyScreen`.

- `mobile/lib/screens/family_screen.dart`
  - Added `simpleMode` constructor argument.
  - In simple mode:
    - Settings/PRO/share/monitored-profile sections are hidden.
    - If nobody is following the current user, show only `让家人守护我`.
    - If there are approved caregivers following the current user, show only `关注我的` list.
    - The invite section and caregiver list do not appear at the same time.

### Documentation

- `AGENTS.md`
  - Generated from `.cursorrules`; repository-wide agent/development guidance.

- `PROJECT_ANALYSIS.md`
  - Technical and product project analysis.

- `CODE_RISK_REVIEW.md`
  - Frontend/backend risk review.

- `PRODUCT_STRATEGY_ANALYSIS.md`
  - Product strategy analysis.

## Decisions Made

- Use `/live` for Docker liveness only. It must not touch Neon, Redis, or any paid/external dependency.
- Keep `/health` for manual/deep monitoring. It still checks DB and Redis and will wake Neon.
- Simple mode is local-only state via `SharedPreferences`, not a backend profile setting.
- Simple mode must remain reversible from the home screen switch.
- Family page simple mode should reduce UI density rather than change backend permissions or API behavior.
- For simple family page display:
  - No approved caregivers: show `让家人守护我`.
  - Has approved caregivers: show `关注我的`.
  - Never show both in simple mode.

## Commands Run

Important commands executed recently:

```bash
git pull --rebase origin main
git stash push -m "wip-live-healthcheck-before-pull" -- backend/app/main.py docker-compose.yml
git stash pop
python3 -m py_compile backend/app/main.py
git add backend/app/main.py docker-compose.yml
git commit -m "fix: avoid database checks in container liveness probe"
git push origin main
```

```bash
dart analyze lib/screens/today_screen.dart lib/screens/family_screen.dart
dart analyze lib/screens/family_screen.dart
git add mobile/lib/screens/today_screen.dart mobile/lib/screens/family_screen.dart
git commit -m "feat: add simplified family mode"
git push origin main
git add mobile/lib/screens/family_screen.dart
git commit -m "fix: simplify caregiver section in simple mode"
git push origin main
```

Postgres-related commands:

```bash
docker run -d --name zellia-postgres \
  -e POSTGRES_USER=zellia \
  -e POSTGRES_PASSWORD=zellia_dev_password \
  -e POSTGRES_DB=zellia \
  -p 5432:5432 \
  -v zellia_postgres_zellia_data:/var/lib/postgresql/data \
  postgres:16-alpine

docker exec zellia-postgres pg_isready -U zellia -d zellia
docker exec zellia-postgres psql -U zellia -d zellia -c "SELECT current_database(), current_user;"
```

Current local Postgres info from that task:

```text
Container: zellia-postgres
Volume: zellia_postgres_zellia_data
Host: 127.0.0.1
Port: 5432
Database: zellia
User: zellia
Password: zellia_dev_password
DATABASE_URL=postgresql+psycopg://zellia:zellia_dev_password@127.0.0.1:5432/zellia
```

## Verification Notes

- `backend/app/main.py` passed `python3 -m py_compile`.
- `dart analyze` for edited Flutter files had no syntax/type errors, but exits non-zero due to existing warning/info issues.
- Existing analyzer issues include unused imports and lint warnings in `family_screen.dart`, `today_screen.dart`, and other files.
- `mobile/pubspec.lock` was accidentally modified during dependency resolution once, then restored before commits.
- Worktree was clean after the last push.

## Remaining Work / Watch Items

- If deploying the `/live` healthcheck change, rebuild/redeploy the backend container so Compose uses the new liveness endpoint.
- Confirm Neon CU-Hours after deployment. If CU-Hours still stays active, check:
  - External uptime monitors hitting `/health`.
  - Scheduler jobs and traffic patterns.
  - `/snapshots/clinical` cache misses.
  - Any gateway or cloud healthcheck configured outside `docker-compose.yml`.
- Consider adding docs/comments that `/health` is a deep check and should not be used as a frequent liveness probe against Neon.
- Simple mode UX should be manually tested on a device/emulator:
  - Toggle on/off persists across app restart.
  - Home AppBar only shows Family care when on.
  - Family page with no approved caregivers shows only `让家人守护我`.
  - Family page with approved caregivers shows only `关注我的`.
- Analyzer cleanup is still pending but not required for the completed tasks.

## Exact Next Prompt

```text
请检查当前工作区状态，并继续验证极简模式和 /live healthcheck 的部署影响。如果需要，运行 Flutter 页面级测试或提出最小修复建议。
```

