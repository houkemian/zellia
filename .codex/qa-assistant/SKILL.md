---
name: qa-assistant
description: Use this skill for Zellia testing strategy, test plans, manual and automated test cases, regression checklists, release QA, and validation of health, medication, family, subscription, and notification workflows.
---

# QA Assistant

## Role

Create focused test coverage for Zellia features with special attention to health history, medication adherence, guardian permissions, and elderly-friendly mobile UX.

## Workflow

1. Identify the change surface
   - Classify affected areas: backend API, database, Flutter UI, local storage, push notification, widget, subscription, or external service.
   - Note whether the change touches authentication, family authorization, deletion, payment, or medical history.

2. Build the test matrix
   - Cover happy path, empty state, invalid input, unauthorized access, expired session, network failure, and persistence.
   - Include elder self-view and authorized guardian view when `target_user_id` is supported.
   - Verify localization for new UI text in English and Chinese.

3. Define backend tests
   - Check all business APIs require `get_current_user` or an equivalent authenticated dependency.
   - Validate family access requires `FamilyLink.status == "APPROVED"` plus the needed permission.
   - For medication deletion, confirm soft delete by setting `is_active = False`; do not expect `db.delete()`.
   - For `/medications/today`, test date filtering, time expansion, log matching, and guardian access.

4. Define Flutter tests
   - Run or recommend `flutter analyze` and relevant widget tests.
   - Check touch targets are at least 48x48 and primary actions are easy to complete.
   - Confirm forms use suitable pickers, chips, date/time controls, or large numeric input instead of complex strings.
   - Ensure 401 clears legacy JWT and returns to login state.

5. Define manual QA
   - Test on small and large mobile viewports.
   - Verify readable text, high contrast, no clipped labels, and no accidental write actions in guardian read-only views.
   - Confirm notification behavior after abnormal blood pressure or blood sugar entry.

6. Report results
   - Lead with blocking issues and reproduction steps.
   - Include environment, build version, account role, test data, and expected versus actual result.
   - Separate verified behavior from assumptions or untested risks.

## Output Format

Use concise sections:

- Scope
- Test Matrix
- Automated Tests
- Manual QA Checklist
- Edge Cases
- Regression Risks
- Release Recommendation
