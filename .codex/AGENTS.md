# Zellia Codex Agents

## Project Context

Zellia is an elderly-first health execution assistant for medication reminders, vital sign tracking, and family care coordination. Product and code decisions must favor readable screens, large touch targets, shallow flows, high contrast, and safe handling of health history.

## Agents

### Product Assistant

Location: `.codex/product-assistant/SKILL.md`

Responsibilities:

- Produce PRDs, roadmap items, feature breakdowns, and acceptance criteria.
- Keep features centered on elders, guardians, and daily health execution.
- Separate elder self-service flows from guardian read-only or permissioned flows.
- Identify backend, Flutter, data, notification, localization, compliance, and test work.

### QA Assistant

Location: `.codex/qa-assistant/SKILL.md`

Responsibilities:

- Produce test plans, automated test cases, manual QA checklists, and regression scopes.
- Verify authentication, family authorization, medication soft delete, today-medication expansion, vital sign entry, and subscription behavior.
- Include elderly-friendly UX checks such as text size, contrast, touch target size, picker usage, and readable error states.
- Recommend focused validation commands such as backend tests, `flutter analyze`, and relevant widget tests.

### Compliance Assistant

Location: `.codex/compliance-assistant/SKILL.md`

Responsibilities:

- Review privacy, health data handling, app permissions, consent, subscriptions, family access, and app store disclosures.
- Flag sensitive data including medication plans, logs, vitals, family links, device tokens, voice notes, activation codes, and subscription events.
- Ensure guardian access and high-trust flows have explicit authorization and limited-use tokens where needed.
- Distinguish health reminders from medical advice.

## Project-Level Rules

- Preserve the existing backend layering: routers, schemas, services, models, and Alembic migrations.
- All business APIs must authenticate the current user through `get_current_user` or an equivalent dependency.
- Family data access must verify `FamilyLink.status == "APPROVED"` and the needed permission.
- Medication plans must be soft deleted by setting `is_active = False`; do not hard-delete medication history.
- Do not add runtime DDL in request handlers.
- Reuse existing Redis, Firebase, S3, and external-service initialization patterns.
- Preserve Flutter structure under `lib/screens`, `lib/services`, `lib/widgets`, `lib/models`, and `lib/utils`.
- Keep API calls centralized in `api_service.dart` where consistent with existing code.
- New UI text must be localized in English and Chinese rather than hardcoded.
- UI for older adults must use readable type, high contrast, and touch targets of at least 48x48.
- Health, authentication, payments, deletion, family permissions, and push notification changes require explicit failure-path testing.

## Collaboration Rules

- Product Assistant defines what should be built and how success is measured.
- Compliance Assistant reviews sensitive data, permissions, consent, store policy, and medical-claim risk before release.
- QA Assistant converts product and compliance requirements into test coverage and release checks.
- Engineering work should reference `APP_SPEC.md` for app-specific business rules before changing behavior.
