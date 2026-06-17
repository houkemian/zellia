# Zellia App Spec

## Summary

Zellia, also known as 岁月安, is a simple health execution assistant for adults over 60 and families managing chronic conditions. The core product breaks medication, vital recording, and family collaboration into daily actions that are easy to read, tap, and complete.

## Primary Users

- Elder: records medication completion and vital signs with minimal typing.
- Guardian: views authorized family health status and receives important reminders.
- Caregiver or family admin: helps with onboarding, invitations, activation, and account recovery where permitted.

## Core Features

### Medication Management

- Create and manage medication plans.
- Use `times_a_day` as comma-separated time strings.
- Show today's medication tasks through `GET /medications/today`.
- Expand each medication plan into separate daily time-point tasks.
- Mark each medication time as taken through `medication_logs`.
- Soft delete medication plans with `is_active = False`.

### Today's Home Experience

- `TodayScreen` is the primary mobile experience.
- Keep medication tasks, vital entry, guardian view, reports, and PRO access shallow and easy to reach.
- Support `target_user_id` where authorized guardian access is allowed.

### Vital Signs

- Support blood pressure, heart rate, and blood sugar records.
- Support create, paginated history query, and delete behavior as defined by backend policy.
- Abnormal vital entries should trigger guardian notification flow when supported and authorized.

### Family Collaboration

- Support family links between elders and guardians.
- Approved guardian access requires `FamilyLink.status == "APPROVED"` and appropriate permission.
- Guardian view defaults to read-only unless a feature explicitly grants management rights.
- High-trust actions include invite code, dynamic QR code, assisted registration, activation code, and assisted password reset.

### Subscriptions

- PRO subscriptions and family sharing use `pro_shares` and `subscription_events`.
- RevenueCat and store purchase flows must disclose price, renewal, cancellation, and trial terms accurately.

### Notifications and Devices

- `device_tokens` store push targets.
- Redis is used for QR code tokens, scheduling locks, and temporary state.
- Push notification failure should not block core health record creation unless the feature explicitly requires it.

## Permissions and Privacy

- Health data includes medication plans, medication logs, blood pressure, blood sugar, heart rate, and family relationship data.
- Device tokens, voice notes, activation codes, and subscription records are also sensitive.
- Dynamic QR tokens should be short-lived and one-time use.
- Permission requests should be tied to visible user intent and degrade gracefully when denied.
- App copy must avoid unsupported diagnosis, treatment, or emergency-monitoring claims.

## Backend Constraints

- Python 3.10+, FastAPI, SQLAlchemy, PostgreSQL, Pydantic, JWT OAuth2 compatibility, Firebase Auth, and Redis.
- Keep `/auth/register`, `/auth/login`, hidden `/register`, and hidden `/login` compatibility.
- New business routes must authenticate the current user.
- New endpoints should follow existing router, schema, service, and model boundaries.
- Database schema changes require Alembic migrations.
- Use clear HTTP status codes and understandable error messages.

## Flutter Constraints

- Flutter and Dart mobile app.
- Use `http` for core network requests.
- Use `shared_preferences` for legacy JWT fallback session storage.
- Use `intl` for date and time formatting.
- Keep API, auth headers, 401 handling, and DTO mapping centralized in `api_service.dart` where consistent with existing code.
- On 401, clear local legacy JWT and return to login state.
- Prefer native pickers, date/time controls, chips, and large numeric inputs over complex manual strings.
- New UI text should be localized in English and Chinese.

## Business Rules

- `GET /medications/today` filters active plans where `start_date <= today <= end_date`.
- It expands comma-separated `times_a_day` into independent tasks.
- It joins same-day `medication_logs` by plan, date, and time to determine completion.
- It supports authorized guardian viewing through `target_user_id`.
- Medication plan deletion must not use `db.delete()`.
- Family write actions require explicit permission checks beyond approved relationship status.

## Testing Notes

- Backend changes should include or run relevant API and service tests.
- Flutter changes should run `flutter analyze` and relevant widget tests when feasible.
- Authentication, family permission, payment, delete, notification, and health history changes need failure-path coverage.
- Verify elderly UX: body text at least 18pt, headings around 24pt or larger, high contrast, and touch targets of at least 48x48.
- Test localization for new strings.
- Test guardian read-only states and unauthorized `target_user_id` access.
