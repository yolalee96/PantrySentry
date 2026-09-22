# PantryBuddy Backend API

## Overview

This is the backend API for PantryBuddy, a household food-inventory
application. It sits between the Flutter client application and the
MySQL-compatible relational database (schema defined in `schema.sql` /
`insert_static_data.sql`), exposing a REST interface that the client
consumes instead of accessing the database directly.

**Responsibilities of this layer:**
- Authenticating users and authorising every subsequent request
- Enforcing household-membership and admin-role access control
- Implementing the application's business logic (e.g. matching a
  user-entered item name against the shelf-life reference dataset,
  computing suggested expiry dates)
- Mediating all reads and writes to the database — the client never
  connects to the database directly

**Stack:** Node.js, Express, `mysql2` (parameterised queries throughout —
no raw string-interpolated SQL), `jsonwebtoken`, `bcryptjs`, `nodemailer`.

## Authentication & Authorisation

Every request except `/health`, `/auth/signup`, `/auth/signin`, and
`/auth/forgot-password` requires a valid **JSON Web Token**, issued at
sign-up/sign-in and sent as `Authorization: Bearer <token>`. Tokens are
signed with a server-held secret (`JWT_SECRET`) and expire after 24
hours. Passwords are never stored in plain text - they're hashed with
`bcrypt` before being written to the database.

Authentication alone is not treated as sufficient authorisation. Every
household-scoped route separately verifies that the requesting user is
an active member of that specific household before allowing access, and
admin-only actions (e.g. approving a join request) separately verify the
requester holds the `ADMIN` role for that household. The identity used
for any "who did this" field (item creator, join-request reviewer, etc.)
is always taken from the verified token, never from the request body -
so a request cannot claim to be acting on behalf of a different user.

Password resets use a signed, time-limited (30-minute) token rather than
a database-stored reset code. The token embeds a fragment of the
password hash at the time it was issued; if the password changes before
the token is used, that fragment no longer matches and the token is
rejected — giving one-time-use behaviour without needing separate
storage for reset tokens.

## Getting Started

1. Install Node.js 18+.
2. `cd pantrybuddy-backend && npm install`
3. Copy `.env.example` to `.env` and fill in database credentials, a
   `JWT_SECRET`, and (optionally) Gmail credentials for password-reset
   email — see "Email delivery" below.
4. `npm start` - the server listens on `http://localhost:4000` by
   default.

Verify it's running and connected to the database:
```bash
curl http://localhost:4000/health
```

### Deployment

The backend is structured to run as a Vercel serverless function
(`api/index.js` re-exports the same Express app used by local
development in `src/server.js`, so no code differs between the two
environments). It can equally be deployed to any Node-hosting platform
(Render, Railway, Fly.io) by setting the same environment variables.

### Email delivery

Password-reset emails are sent via Gmail SMTP (through
[Nodemailer](https://nodemailer.com)), authenticated with a Google
**App Password** rather than a normal account password. This requires
`GMAIL_USER`, `GMAIL_APP_PASSWORD`, and `FRONTEND_URL` to be set. If
they're not configured, the server does not fail — it logs the reset
link to the console instead, so the rest of the system remains testable
without email configured.

## API Surface

All request/response bodies are JSON. IDs are returned as strings (even
though they are `BIGINT` in MySQL) to match the client's data models.

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/auth/signup` | `{name, email, password, avatarKey}` → 409 if email already registered |
| POST | `/auth/signin` | `{email, password}` → 401 if incorrect |
| POST | `/auth/forgot-password` | `{email}` → always 200 (does not reveal whether the email is registered); sends a signed reset link by email |
| POST | `/auth/reset-password` | `{token, newPassword}` → completes a reset; rejects an already-used or expired token |
| GET/PATCH | `/users/:id` | PATCH restricted to the authenticated user's own profile |
| POST | `/households` | `{name}` — creator is recorded as ADMIN (from the verified token, not the request body) |
| GET | `/households/:id` | Requires household membership |
| GET | `/households/by-invite/:code` | Public to any authenticated user (invite code = the household's numeric ID) — intentionally not membership-gated, since this is how a non-member looks up a household before requesting to join |
| GET | `/households/:id/members` | Requires household membership |
| POST | `/join-requests` | `{inviteCode}` → 409 if already a member or already pending |
| GET | `/households/:id/join-requests?status=pending` | Admin-only |
| GET | `/join-requests/:id` | Restricted to the requester who submitted it |
| POST | `/join-requests/:id/approve` \| `/decline` | Admin-only |
| GET/POST | `/households/:id/inventory-items` | POST auto-creates the matching `products` row if one doesn't already exist |
| PUT | `/inventory-items/:id` | Requires membership in the item's household |
| POST | `/inventory-items/:id/resolve` | `{disposition: 'consumed'|'discarded'}` |
| DELETE | `/inventory-items/:id` | |
| POST | `/reminders` | `{itemId, householdId, leadTimeDays}` |
| GET | `/households/:id/reminders` | |
| POST | `/reminders/:id/mark-triggered` | |
| GET | `/households/:id/activity` | Derived from `inventory_transactions` + `team_members` (see Data Model Notes) |
| GET | `/shelf-life-suggestion`, `/storage-suggestions` | Matches an item name/category against the reference dataset; falls back from product-specific to category-level guidance |

## Data Model Notes & Current Limitations

- **Activity feed is derived, not stored.** There is no dedicated
  activity-log table; `GET /households/:id/activity` is assembled from
  `inventory_transactions` (add/consume/discard events) and
  `team_members.joined_at`. Item *edits* do not currently appear in the
  feed, as there is no transaction type recorded for them.
- **No "Donate" disposition.** `inventory_items.status` supports
  `IN_STOCK/CONSUMED/EXPIRED/DISCARDED`. A donate option was considered
  during development but intentionally scoped out of this iteration
  rather than implemented against an unsupported status value; noted as
  a candidate for a future iteration pending a schema change.
- **Reminder cancellation has no route yet.** The schema supports a
  `CANCELLED` reminder status, but no endpoint currently sets it.
- **Per-user reminder read-state is unused.** The
  `notification_recipients` table exists in the schema but is not yet
  read from or written to.
- **Avatar catalogue is hardcoded, not a database table.**
  `src/util/avatars.js` maps a fixed 12-item list to match the client's
  avatar picker order. Adequate for the current scope; a proper
  `avatars` table would be a cleaner long-term approach.
- **Password-reset email relies on a single Gmail account** rather than
  a dedicated transactional email provider — an appropriate trade-off
  for this project's scale, and noted as a change a production
  deployment would make.

## Testing

Every route was exercised manually against a live MySQL instance loaded
with the project's real schema and seed data (and subsequently against
the deployed cloud database), covering both expected behaviour and
deliberate negative-path/security scenarios — including missing or
invalid tokens, cross-household access attempts, and privilege
escalation attempts (a non-admin approving a join request; a user
editing another user's profile). All such attempts were confirmed to be
correctly rejected. A detailed, itemised record of test cases and the
defects they surfaced is maintained separately in the project's Testing
Folder documentation.
