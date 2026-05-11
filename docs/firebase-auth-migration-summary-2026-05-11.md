# Firebase Auth Migration Summary (2026-05-11)

This document briefly summarizes the authentication and session changes completed in this update.

## Scope

- Mobile app login/session flow (`mobile`)
- Backend auth dependency verification path (`backend`)
- Login page UX adjustments

## Key Changes

- Unified session token strategy to **Firebase ID Token**
  - Mobile request headers now use `FirebaseAuth.instance.currentUser?.getIdToken()`
  - Removed local app token persistence dependency from active auth path
  - Logout now signs out from Firebase directly
- Updated backend current-user resolution to accept Firebase ID Tokens
  - Verify Firebase token first
  - Resolve or provision local `users` record from Firebase claims (`email` / `uid` / `name`)
  - Kept legacy JWT decode as fallback for backward compatibility
- Enforced email verification for Email/Password login
  - Sign-in is blocked when `emailVerified` is false
  - Verification email is sent/re-sent automatically
  - Registration no longer auto-enters app before email verification
- Updated login UI interaction
  - Removed top "Sign in / Sign up" tab switch
  - Added link-style mode switch under the primary action button
  - Auth logic remains Firebase-based

## User-Visible Behavior Changes

- Email/password users must verify email before entering the app.
- Existing Firebase-authenticated users can restore session through Firebase current user state.
- Unauthorized API responses trigger Firebase sign-out and return to login screen.

## Notes

- Legacy helper methods (e.g., token-related compatibility methods) may still exist as no-op/fallback for compatibility.
- If desired, a follow-up cleanup can remove deprecated token exchange paths completely.
