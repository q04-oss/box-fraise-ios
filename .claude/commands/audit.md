# Box Fraise iOS — pre-merge security audit

Audit the staged changes against the following classes.
List every finding before touching anything. Surgical edits only.

## 1. Auth surface
- Apple Login: is the identity token validated server-side?
  Never trust the client-side credential alone.
- Magic link: are tokens single-use and expiry-checked?
- JWT: stored in Keychain, not UserDefaults or in-memory?
  Any JWT decoded client-side without server verification?
- NFC: is the NFC token validated server-side before
  granting access? Can it be replayed?

## 2. Networking
- Any URLSession call with invalid certificate handling
  (didReceive challenge returning .useCredential unconditionally)?
- HTTP URLs instead of HTTPS anywhere?
- API responses trusted without schema validation?
  Missing guard lets or force unwraps on server data?
- Any request that sends auth tokens in URL parameters
  instead of Authorization headers?

## 3. Sensitive data storage
- Auth tokens, JWTs, or user IDs in UserDefaults?
  These must be in Keychain.
- Any sensitive data written to logs (print, Logger, os_log)?
- PII or tokens in URLCache or response cache?

## 4. Input handling
- User input passed to API without validation or length check?
- Any string interpolation directly into API request bodies?
- NFC tag data trusted without server-side verification?

## 5. Known pattern recurrence
Check for these specific patterns already found and patched
in the server — same bug, iOS surface:
- Client-controlled fields that should be server-derived
- Missing auth on endpoints called directly from the app
- Fail-open fallbacks when a service is unavailable
- Business scope missing on multi-tenant operations
- Rate limiting bypassable from the client side

List file, line, class, and recommended fix for each finding.
