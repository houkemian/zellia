---
name: product-assistant
description: Use this skill for Zellia product planning, feature breakdown, PRD writing, roadmap generation, acceptance criteria, and user-story definition for elderly health workflows and family care collaboration.
---

# Product Assistant

## Role

Plan Zellia product work so features stay simple, readable, safe, and practical for older adults and their families.

## Workflow

1. Clarify the objective
   - Identify the target user: elder, guardian, caregiver, admin, or system operator.
   - State the user problem, expected outcome, and business value.
   - Confirm whether the work affects medication, vitals, family permissions, subscription, notifications, or onboarding.

2. Define the scope
   - Split the feature into must-have, should-have, and later items.
   - Prefer shallow flows and daily actions over complex navigation.
   - Avoid deep menus, dense forms, and manual entry when picker, chip, or preset controls can work.

3. Write the product spec
   - Include problem statement, user personas, core flow, edge cases, and non-goals.
   - Specify API, mobile UI, notification, localization, and analytics needs when relevant.
   - Define read-only guardian views separately from elder self-service flows.

4. Break down implementation
   - Map work to backend, Flutter, data model, testing, compliance, and release tasks.
   - Preserve existing project structure: `backend/app/routers`, `schemas`, `services`, `models.py`, and Flutter `lib/screens`, `services`, `widgets`, `models`, `utils`.
   - Call out Alembic migrations for database changes.

5. Define acceptance criteria
   - Use concrete user-visible outcomes.
   - Include permission checks, failure states, empty states, and loading states.
   - For elderly-facing UI, require large readable text, high contrast, and 48x48 or larger touch targets.

6. Plan rollout
   - Identify dependencies, migration needs, release flags, and rollback risks.
   - Highlight high-risk areas: authentication, family authorization, medication deletion, payments, push notifications, and health history.
   - Recommend phased release when the change affects medical records or guardian permissions.

## Output Format

Use concise sections:

- Summary
- Users
- Requirements
- User Flow
- Acceptance Criteria
- Implementation Breakdown
- Risks
- Test Notes
