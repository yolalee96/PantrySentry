# Data layer — handoff notes for the DB teammate

Every screen in this app talks ONLY to the abstract classes in `repository.dart`
(`UserRepository`, `HouseholdRepository`, `InventoryRepository`,
`ReminderRepository`, `ActivityLogRepository`). No screen or widget touches
storage directly.

Right now `mock_data_store.dart` provides an **in-memory** implementation of
all five interfaces (`InMemoryDataStore`), just so the app is runnable and
demoable without a real backend. It resets every time the app restarts.

This app's models now deliberately mirror your `schema.sql` shape (see the
mapping table below), so wiring in the real MySQL backend should mostly be
"translate this interface method into the equivalent query" rather than
redesigning anything.

## What you need to do
Create a new file (e.g. `sql_data_store.dart` or `rest_data_store.dart`)
with a class that implements the same five abstract interfaces, backed by
whatever storage/API you build. Then in `main.dart`, swap this line:

```dart
final dataStore = InMemoryDataStore();
```

for:

```dart
final dataStore = YourDataStore();
```

That's the only line that needs to change — nothing in `screens/` or
`state/` should need to be touched.

## Model <-> schema.sql mapping
| App model | Table | Notes |
| --- | --- | --- |
| `AppUser` | `users` | `avatarKey` (String, e.g. `'tomato'`) needs mapping to your `avatar_id` (INT) — there's no avatar catalog table in the schema yet, so we need a small lookup table or enum on your side. |
| `Household` | `teams` | `Household.id` also doubles as the invite code shown in `InviteScreen` — fine to just stringify `team_id`. |
| `HouseholdMember` (`role`, `status`) | `team_members` | `MembershipRole.admin/member` <-> `ADMIN`/`MEMBER`. `MembershipStatus.active/inactive` <-> `ACTIVE`/`INACTIVE`. |
| `JoinRequest` | `join_requests` | `JoinRequestStatus.pending/approved/declined` <-> `PENDING`/`APPROVED`/`DECLINED`. The "one PENDING request per (team, user)" check in `InMemoryDataStore.requestToJoin` is the same app-layer guard your README calls for — keep it in your implementation too. |
| `ProductCategory` | `product_categories` | Enum values are the 16 seeded categories (last synced against `insert_static_data.sql` — note "Household Items" doesn't exist in the real data; category_ids 9/10 are intentionally skipped). Item **name** is still free text in the app for now (not wired to `products`/`barcode`) — see "Product catalog" below. |
| `StorageLocation` | `storage_types` | `fridge/freezer/pantry` <-> `FRIDGE`/`FREEZER`/`PANTRY`. |
| `FoodItem` | `inventory_items` | Simplified: no `product_id` FK yet (see below), no `production_date`/`expiry_date_source`/`checkout_date` yet — add these if/when the app switches to the product catalog. |
| `ItemDisposition` (`consumed/discarded`) | `inventory_items.status` | Maps to `CONSUMED`/`DISCARDED`. **No `DONATED` yet** — the app dropped the Donate option since your schema's status enum doesn't have it. If you add `DONATED` to the enum later, re-add `ItemDisposition.donated` in `food_item.dart` and the button in `item_detail_screen.dart`. |
| `Reminder` | `reminders` | `triggered` (bool) maps to `status = 'TRIGGERED'`; the app doesn't yet support `CANCELLED` — add a `cancelReminder()` method to `ReminderRepository` when that's needed. |
| `ActivityLogEntry` | `inventory_transactions` (+ join events) | Loosely mapped — the app's activity feed is a simpler read-only log; your real transactions table has richer audit fields (`discard_reason`, etc.) you may want to surface later. |
| *(not yet modeled)* | `notification_recipients` | Multi-user per-reminder read state isn't implemented client-side yet — reminders currently just fire a snackbar in the current session. Worth adding once push notifications are wired up. |

## Product catalog (not yet switched over)
Your schema normalizes items into `product_categories` + `products` (with
barcodes). The team decided to keep item entry as free text for iteration 1
rather than picking from a catalog, so `FoodItem.name` is just a String and
there's no `product_id`. If/when you want to switch:
- Add a `ProductRepository` (or extend `InventoryRepository`) with
  `searchProducts(query)` / `getProduct(id)`.
- Change `AddEditItemScreen`'s name field to a search-and-pick UI against it.
- Add `productId` to `FoodItem` (or replace `name` with it).

## Shelf-life dataset (still pending)
`services/shelf_life_service.dart` has a hardcoded lookup table keyed by
`"category|storage"` (mirroring `shelf_life_rules`'s unique
`(category_id, storage_type_id)` key) with placeholder reminder lead times
and shelf-life day ranges. Once the CSV is ready, replace the two maps in
that file with a real lookup — keep `suggestLeadTime()` and
`suggestShelfLifeDaysRange()`'s signatures the same and nothing upstream
needs to change.

## IDs
`services/id_service.dart` generates the unique household/user/etc. IDs
(`IdService.newId()`). If your backend generates its own IDs (e.g. DB
auto-increment), just have your repository implementation return that ID
(as a String) from `signUp()` / `createHousehold()` / etc. instead of one
from `IdService` — the rest of the app doesn't care where the ID came
from, only that every record has one.

## Auth
`UserRepository` covers `signUp`, `signIn`, and `requestPasswordReset`.
The mock store stores a placeholder (NOT secure) password hash in memory —
your real implementation needs proper password hashing (bcrypt/argon2, or
delegate to a managed auth provider) and an actual email service for
`requestPasswordReset`. Both throw `AuthException` on failure (wrong
password, duplicate email, etc.) — the sign-up/sign-in screens already
catch and display that.

## Join-request approval flow
Joining a household is now a two-step flow, matching `join_requests`:
`HouseholdRepository.requestToJoin()` creates a PENDING request;
`approveRequest()`/`declineRequest()` (called by an ADMIN from
`PendingRequestsScreen`) resolve it. The requester's "waiting" screen
(`AwaitingApprovalScreen`) live-updates via `watchJoinRequest(requestId)` —
your real implementation should push a status change to that stream (or
have the app poll) whenever an admin acts on the request.
