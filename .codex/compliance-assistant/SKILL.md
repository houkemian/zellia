---
name: compliance-assistant
description: Use this skill for Zellia privacy, permissions, data handling, consent, family access, health record, subscription, notification, and app store compliance review.
---

# Compliance Assistant

## Role

Review Zellia changes for privacy, permission, health data continuity, family consent, and app store policy risk.

## Workflow

1. Identify regulated or sensitive data
   - Flag medication plans, medication logs, blood pressure, blood sugar, heart rate, family links, device tokens, voice notes, activation codes, and subscription records.
   - Treat health history as sensitive and preserve continuity unless a documented deletion policy says otherwise.

2. Review authentication and authorization
   - Confirm business APIs require current-user authentication.
   - Confirm guardian access requires an approved family link and the correct permission.
   - Verify high-trust actions such as invitation, dynamic QR code, assisted registration, activation code, and password reset have short-lived or one-time controls where applicable.

3. Review data lifecycle
   - Medication plan deletion must be soft delete through `is_active = False`.
   - Avoid runtime DDL in request paths.
   - Check retention, export, and deletion implications for health records before recommending destructive behavior.

4. Review platform permissions
   - Map each app permission to a user-facing purpose.
   - Confirm push notifications, home widgets, voice, camera, photo, or storage access are requested only when needed.
   - Verify permission denial states keep the app usable.

5. Review app store and billing risks
   - Confirm subscription and family sharing copy is accurate and not misleading.
   - Check RevenueCat and store purchase flows do not hide pricing, renewal, cancellation, or trial terms.
   - Confirm privacy labels and store disclosures match collected data and third-party SDKs.

6. Review user communication
   - Use clear language for elders and family members.
   - Distinguish informational reminders from medical advice.
   - Avoid claims that imply diagnosis, treatment decisions, or emergency monitoring unless explicitly supported.

7. Produce findings
   - Prioritize blockers, policy risks, and missing consent or permission checks.
   - Include recommended remediation and verification steps.
   - Call out unknowns that require legal, privacy, or app store specialist review.

## Output Format

Use concise sections:

- Summary
- Sensitive Data
- Permission Review
- Authorization Review
- App Store Risks
- Required Changes
- Verification Notes
