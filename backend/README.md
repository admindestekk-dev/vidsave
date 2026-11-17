# Backend authentication and purchases

Install `backend/requirements.txt` (the root requirements file is used by Render).
Set `VIDSAVE_API_KEY` and supply `GOOGLE_APPLICATION_CREDENTIALS_JSON` as a
secret environment variable containing the complete service-account JSON, not
a file path. Never commit or log it. The Firebase project defaults to the
service account's `project_id`; set `FIREBASE_PROJECT_ID` if the intended
Firebase project is different. Enable Google sign-in in Firebase Authentication.
Do not set `FIREBASE_AUTH_EMULATOR_HOST` in this backend: emulator tokens are
rejected. Give the service account access to the app in Google Play Console
and enable the Android Publisher API in its Google Cloud project.

`POST /api/auth/google` accepts `idToken`, a **Firebase Authentication ID
token**, not a Google OAuth ID token. Only verified Google-provider identities
with verified email are accepted. Existing password accounts are not
automatically linked; Firebase UID/email conflicts require account recovery.
Old profile-only Google sessions are revoked at backend initialization and
again when the account first signs in with a verified Firebase token.

`POST /api/auth/verify-purchase` requires an app bearer session and a Play
purchase token (`token`, `purchaseToken`, or `serverVerificationData`). The
backend verifies package `dev.admindestekk.vidsave` and product
`vidsave_premium_monthly` via Android Publisher. Only paid, unexpired purchases
qualify; trial and pending purchases are not granted premium. Repeated
verification uses Google's expiry, not a 30-day extension. Token hashes are
permanently bound to the first app account, including across account deletion;
linked replacement tokens inherit that ownership. A stolen token can still be
claimed by whoever submits it first: use Play obfuscated account IDs and a
recovery process if stronger purchase-to-account binding is required.

Existing legacy entitlements cannot be proven and are ignored until verified
again. The old simulated monthly subscription endpoint is disabled by default;
`VIDSAVE_ENABLE_TEST_SUBSCRIPTIONS=true` enables it only for isolated developer
environments and must never be enabled in production.

Configuration failures return `google.config_unavailable` (503), Play or
Firebase upstream failures `google.upstream_unavailable` (502), and malformed
Play responses `google.upstream_invalid` (502). Invalid or inactive purchases
are rejected; a previously claimed purchase found inactive is removed from the
account's entitlement. The database must be persistent and shared between
workers for replay protection. A stored entitlement remains valid until its
last verified expiry: refunds, cancellation, renewal and revocation are not
pushed automatically. Reverify purchases periodically or implement Google
Play real-time developer notifications for timely updates. A client must
acknowledge purchases as required by Play.
