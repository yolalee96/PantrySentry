import '../models/app_user.dart';
import '../models/household.dart';
import '../models/join_request.dart';
import '../models/food_item.dart';
import '../models/reminder.dart';
import '../models/activity_log_entry.dart';
import '../models/shelf_life_suggestion.dart';
import '../models/recognition_candidate.dart';
import '../models/receipt_item_draft.dart';

/// See lib/data/README.md — screens depend only on these interfaces,
/// never on a concrete storage implementation.

/// Thrown by [UserRepository.signUp] when the email is already registered,
/// and by [UserRepository.signIn] when the email/password don't match.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class UserRepository {
  /// AC 1.1.1 (extended with email/password per team decision).
  Future<AppUser> signUp({
    required String name,
    required String avatarKey,
    required String email,
    required String password,
  });

  /// Throws [AuthException] if the email/password don't match a known account.
  Future<AppUser> signIn({required String email, required String password});

  /// Simulates triggering a "reset your password" email. A real
  /// implementation needs a backend email service — see lib/data/README.md.
  /// Deliberately does not reveal whether the email exists, to avoid
  /// leaking which addresses have accounts.
  Future<void> requestPasswordReset({required String email});

  /// Completes a reset started by [requestPasswordReset] — [token] comes
  /// from the link the user clicked in their email.
  Future<void> resetPassword({required String token, required String newPassword});

  /// Clears whatever session state (e.g. an auth token) this repository
  /// is holding — called when the user explicitly signs out.
  Future<void> signOut();

  /// "Stay logged in" — attempts to restore a previously saved session at
  /// app startup. Returns null if there's nothing saved, or it no longer
  /// works (e.g. the token expired).
  Future<AppUser?> restoreSession();

  Future<AppUser?> getUser(String userId);
  Future<AppUser> updateUser(AppUser user);
}

abstract class HouseholdRepository {
  /// Creates the household with [creatorUserId] as its first ADMIN
  /// (matches schema.sql: there's no `teams.created_by` column — the
  /// admin is whoever has `team_members.role = 'ADMIN'`).
  Future<Household> createHousehold({required String name, required String creatorUserId});
  Future<Household?> getHousehold(String householdId);
  /// Returns null if no household matches [inviteCode] (AC 3.4.1).
  Future<Household?> findByInviteCode(String inviteCode);
  Future<List<HouseholdMember>> getMembers(String householdId);

  /// The household [userId] is currently an active member of, if any —
  /// null if they don't belong to one yet. Used right after sign-in so a
  /// returning user lands back in their existing household instead of
  /// being asked to create/join one again. If a user belongs to more
  /// than one household, this is whichever one their membership row
  /// sorts first (most recently joined) — see [getHouseholdsForUser]
  /// for the full list used by household switching.
  Future<Household?> getHouseholdForUser(String userId);

  /// Every household [userId] is currently an active member of — used
  /// for the "switch household" list on the Profile screen. A user can
  /// belong to more than one household at a time.
  Future<List<Household>> getHouseholdsForUser(String userId);

  /// [userId]'s own still-pending join request, if any — null otherwise.
  /// Used on sign-in so a returning user who's still waiting on approval
  /// sees that screen again instead of being asked to request access a
  /// second time.
  Future<JoinRequest?> getMyPendingRequest(String userId);

  /// AC 3.5.1 (revised) — joining now creates a PENDING [JoinRequest]
  /// instead of granting instant access, matching schema.sql's
  /// `join_requests` table. Throws [AuthException] if the user already
  /// has a PENDING request for this household (the app-layer guard the
  /// schema's README calls for, since MySQL can't express this as a
  /// partial-unique constraint).
  Future<JoinRequest> requestToJoin({required String inviteCode, required AppUser user});

  Future<List<JoinRequest>> getPendingRequests(String householdId);

  /// Live updates for the requester's own "waiting for approval" screen.
  Stream<JoinRequest> watchJoinRequest(String requestId);

  /// Approving adds the requester as an ACTIVE MEMBER (see
  /// [getMembers]) and sets the request's status/reviewedAt/reviewedBy.
  Future<void> approveRequest({required String requestId, required String reviewedByUserId});
  Future<void> declineRequest({required String requestId, required String reviewedByUserId});

  /// Leaves a household — removes the current user's own membership
  /// only. If they're the sole admin of a household that still has
  /// other members, this is still allowed (there's no promote-another-
  /// admin feature yet) — the UI warns about this before confirming.
  Future<void> leaveHousehold({required String householdId, required String userId});
}

abstract class InventoryRepository {
  Future<FoodItem> addItem(FoodItem item);
  Future<FoodItem> updateItem(FoodItem item);
  Future<void> removeItem(String itemId);
  Future<List<FoodItem>> getItemsForHousehold(String householdId);
  /// Live updates whenever items for [householdId] change (AC 3.6.1 —
  /// real-time sync). The in-memory implementation fakes this with a
  /// broadcast Stream; a real backend would back this with e.g. websockets
  /// or DB change listeners.
  Stream<List<FoodItem>> watchItemsForHousehold(String householdId);
}

abstract class ReminderRepository {
  Future<Reminder> setReminder(Reminder reminder);
  Future<List<Reminder>> getRemindersForHousehold(String householdId);
  Future<void> markTriggered(String reminderId);
  Future<void> cancelReminder(String reminderId);
}

abstract class ActivityLogRepository {
  Future<void> logActivity(ActivityLogEntry entry);
  Future<List<ActivityLogEntry>> getActivityForHousehold(String householdId);
  Stream<List<ActivityLogEntry>> watchActivityForHousehold(String householdId);
}

abstract class ShelfLifeRepository {
  /// Looks up a real, sourced shelf-life recommendation. [itemName], if
  /// given, is matched against specific products in the dataset first
  /// (much more accurate) before falling back to a generic category-level
  /// rule. Returns null if no data exists yet for this combination.
  Future<ShelfLifeSuggestion?> getSuggestion({
    required ProductCategory category,
    required StorageLocation location,
    String? itemName,
  });

  /// Same lookup as [getSuggestion], but for all 3 storage locations at
  /// once — lets the UI show "here's how this item fares in each place"
  /// before the user has picked a storage location, instead of requiring
  /// one to be picked first just to find out it's a bad fit.
  Future<Map<StorageLocation, ShelfLifeSuggestion?>> getStorageSuggestions({
    required ProductCategory category,
    String? itemName,
  });
}

/// Epic "Recognition" — resolves manual text, a scanned barcode, a photo,
/// or OCR'd packaging text into candidate PantryBuddy references, via the
/// backend's product_keyword_mapping table (and, for photo/OCR, a private
/// recognition service running SigLIP + Tesseract). Every result requires
/// user confirmation before it's saved — none of these auto-populate an
/// inventory item on their own.
abstract class RecognitionRepository {
  Future<List<RecognitionCandidate>> recognizeText(String text);
  Future<BarcodeRecognitionResult> recognizeBarcode(String barcode);
  Future<List<RecognitionCandidate>> recognizeImage(List<int> imageBytes);
  Future<OcrRecognitionResult> recognizeOcr(List<int> imageBytes);
  /// [rawText] — already OCR'd text (from BrowserOcrService), not an
  /// image — receipt OCR happens client-side, see chat for why.
  Future<List<ReceiptItemDraft>> recognizeReceipt(String rawText);
}

