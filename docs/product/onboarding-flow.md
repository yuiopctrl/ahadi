# Onboarding Flow

The web onboarding flow is mobile-first and has five steps:

1. Choose Package
2. Organization
3. Administrator Profile
4. First Event
5. Review and Create

Package limits are loaded from the database through `/api/v1/plans`; they are not hardcoded in the web UI. Draft onboarding data is persisted across refresh, but OTP, PIN, and tokens are not stored in custom application storage.

After successful onboarding, the app refreshes context, selects the new tenant, and routes to the created event overview.
