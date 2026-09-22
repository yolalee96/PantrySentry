import 'dart:async';

import '../models/app_user.dart';
import '../models/household.dart';
import '../models/join_request.dart';
import '../models/food_item.dart';
import '../models/reminder.dart';
import '../models/activity_log_entry.dart';
import '../models/shelf_life_suggestion.dart';
import '../services/id_service.dart';
import '../services/shelf_life_service.dart';
import 'repository.dart';

/// TEMPORARY in-memory implementation of every repository interface.
/// Resets on app restart. Exists purely so the UI is runnable/demoable
/// before the real database is wired in — see lib/data/README.md for the
/// handoff instructions.
class InMemoryDataStore
    implements
        UserRepository,
        HouseholdRepository,
        InventoryRepository,
        ReminderRepository,
        ActivityLogRepository,
        ShelfLifeRepository {
  final Map<String, AppUser> _users = {};
  // Credentials are kept separate from AppUser on purpose — a real backend
  // would never return a password hash as part of a normal profile object.
  // NOTE: this "hash" is a placeholder for demo purposes only, it is NOT
  // secure. The real backend must use a proper password hashing scheme
  // (e.g. bcrypt/argon2) — see lib/data/README.md.
  final Map<String, String> _passwordHashByEmail = {};
  final Map<String, Household> _households = {};
  // (householdId, userId) -> membership. Mirrors team_members' composite PK.
  final Map<String, Map<String, HouseholdMember>> _membersByHousehold = {};
  final Map<String, JoinRequest> _joinRequests = {};
  final Map<String, StreamController<JoinRequest>> _joinRequestStreams = {};
  final Map<String, FoodItem> _items = {};
  final Map<String, Reminder> _reminders = {};
  final List<ActivityLogEntry> _activity = [];

  final Map<String, StreamController<List<FoodItem>>> _itemStreams = {};
  final Map<String, StreamController<List<ActivityLogEntry>>>
      _activityStreams = {};

  // ---------------- UserRepository ----------------

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  String _placeholderHash(String password) => 'hash:${password.length}:$password';

  @override
  Future<AppUser> signUp({
    required String name,
    required String avatarKey,
    required String email,
    required String password,
  }) async {
    final normalized = _normalizeEmail(email);
    if (_passwordHashByEmail.containsKey(normalized)) {
      throw AuthException('An account already exists for that email.');
    }
    final user = AppUser(
      id: IdService.newId('usr'),
      name: name,
      email: normalized,
      avatarKey: avatarKey,
    );
    _users[user.id] = user;
    _passwordHashByEmail[normalized] = _placeholderHash(password);
    return user;
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    final normalized = _normalizeEmail(email);
    final storedHash = _passwordHashByEmail[normalized];
    if (storedHash == null || storedHash != _placeholderHash(password)) {
      throw AuthException('Incorrect email or password.');
    }
    final user = _users.values.firstWhere((u) => u.email == normalized);
    return user;
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    // TODO(db-team): send a real reset email via the backend's email
    // service. The mock store intentionally does nothing observable here,
    // matching the security practice of not confirming whether an email
    // is registered.
    return;
  }

  @override
  Future<void> resetPassword({required String token, required String newPassword}) async {
    // No real backend to reset a password against — mock store only.
    return;
  }

  @override
  Future<void> signOut() async {
    // Nothing to clear — the in-memory mock never held a token, only the
    // real ApiDataStore does. Kept here for interface consistency.
  }

  @override
  Future<AppUser?> restoreSession() async {
    // The mock store never persists anything — nothing to restore.
    return null;
  }

  @override
  Future<AppUser?> getUser(String userId) async => _users[userId];

  @override
  Future<AppUser> updateUser(AppUser user) async {
    _users[user.id] = user;
    return user;
  }

  // ---------------- HouseholdRepository ----------------

  @override
  Future<Household> createHousehold({required String name, required String creatorUserId}) async {
    final household = Household(id: IdService.newId('hh'), name: name);
    _households[household.id] = household;
    final creator = _users[creatorUserId];
    if (creator != null) {
      _membersByHousehold[household.id] = {
        creatorUserId: HouseholdMember(
          user: creator,
          role: MembershipRole.admin,
          status: MembershipStatus.active,
        ),
      };
    }
    return household;
  }

  @override
  Future<Household?> getHousehold(String householdId) async =>
      _households[householdId];

  @override
  Future<Household?> findByInviteCode(String inviteCode) async {
    // The household's own ID doubles as its invite code (AC 3.4.1).
    return _households[inviteCode.trim().toUpperCase()];
  }

  @override
  Future<List<HouseholdMember>> getMembers(String householdId) async {
    return _membersByHousehold[householdId]?.values.toList() ?? [];
  }

  @override
  Future<Household?> getHouseholdForUser(String userId) async {
    for (final entry in _membersByHousehold.entries) {
      if (entry.value.containsKey(userId)) {
        return _households[entry.key];
      }
    }
    return null;
  }

  @override
  Future<List<Household>> getHouseholdsForUser(String userId) async {
    final result = <Household>[];
    for (final entry in _membersByHousehold.entries) {
      if (entry.value.containsKey(userId)) {
        final h = _households[entry.key];
        if (h != null) result.add(h);
      }
    }
    return result;
  }

  @override
  Future<JoinRequest?> getMyPendingRequest(String userId) async {
    final matches = _joinRequests.values
        .where((r) => r.userId == userId && r.status == JoinRequestStatus.pending)
        .toList();
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<JoinRequest> requestToJoin({required String inviteCode, required AppUser user}) async {
    final household = await findByInviteCode(inviteCode);
    if (household == null) {
      throw AuthException('No household found for that invite code.');
    }
    final alreadyMember = _membersByHousehold[household.id]?.containsKey(user.id) ?? false;
    if (alreadyMember) {
      throw AuthException('You\'re already a member of this household.');
    }
    final existingPending = _joinRequests.values.any((r) =>
        r.householdId == household.id &&
        r.userId == user.id &&
        r.status == JoinRequestStatus.pending);
    if (existingPending) {
      throw AuthException('You already have a pending request for this household.');
    }
    final request = JoinRequest(
      id: IdService.newId('jr'),
      householdId: household.id,
      householdName: household.name,
      userId: user.id,
      userName: user.name,
      userAvatarKey: user.avatarKey,
    );
    _joinRequests[request.id] = request;
    return request;
  }

  @override
  Future<List<JoinRequest>> getPendingRequests(String householdId) async {
    return _joinRequests.values
        .where((r) => r.householdId == householdId && r.status == JoinRequestStatus.pending)
        .toList();
  }

  @override
  Stream<JoinRequest> watchJoinRequest(String requestId) {
    final controller = _joinRequestStreams.putIfAbsent(
      requestId,
      () => StreamController<JoinRequest>.broadcast(),
    );
    Future.microtask(() {
      final current = _joinRequests[requestId];
      if (current != null && !controller.isClosed) controller.add(current);
    });
    return controller.stream;
  }

  void _emitJoinRequest(String requestId) {
    final controller = _joinRequestStreams[requestId];
    final request = _joinRequests[requestId];
    if (controller == null || controller.isClosed || request == null) return;
    controller.add(request);
  }

  @override
  Future<void> approveRequest({required String requestId, required String reviewedByUserId}) async {
    final request = _joinRequests[requestId];
    if (request == null || request.status != JoinRequestStatus.pending) return;
    request.status = JoinRequestStatus.approved;
    request.reviewedAt = DateTime.now();
    request.reviewedByUserId = reviewedByUserId;

    final user = _users[request.userId];
    if (user != null) {
      _membersByHousehold.putIfAbsent(request.householdId, () => {});
      _membersByHousehold[request.householdId]![request.userId] = HouseholdMember(
        user: user,
        role: MembershipRole.member,
        status: MembershipStatus.active,
      );
    }
    _emitJoinRequest(requestId);
  }

  @override
  Future<void> declineRequest({required String requestId, required String reviewedByUserId}) async {
    final request = _joinRequests[requestId];
    if (request == null || request.status != JoinRequestStatus.pending) return;
    request.status = JoinRequestStatus.declined;
    request.reviewedAt = DateTime.now();
    request.reviewedByUserId = reviewedByUserId;
    _emitJoinRequest(requestId);
  }

  @override
  Future<void> leaveHousehold({required String householdId, required String userId}) async {
    _membersByHousehold[householdId]?.remove(userId);
  }

  // ---------------- InventoryRepository ----------------

  @override
  Future<FoodItem> addItem(FoodItem item) async {
    _items[item.id] = item;
    _emitItems(item.householdId);
    return item;
  }

  @override
  Future<FoodItem> updateItem(FoodItem item) async {
    _items[item.id] = item;
    _emitItems(item.householdId);
    return item;
  }

  @override
  Future<void> removeItem(String itemId) async {
    final item = _items.remove(itemId);
    if (item != null) _emitItems(item.householdId);
  }

  @override
  Future<List<FoodItem>> getItemsForHousehold(String householdId) async {
    return _items.values.where((i) => i.householdId == householdId).toList();
  }

  @override
  Stream<List<FoodItem>> watchItemsForHousehold(String householdId) {
    final controller = _itemStreams.putIfAbsent(
      householdId,
      () => StreamController<List<FoodItem>>.broadcast(
        onListen: () {},
      ),
    );
    // Push current snapshot to new listeners.
    Future.microtask(() => _emitItems(householdId));
    return controller.stream;
  }

  void _emitItems(String householdId) {
    final controller = _itemStreams[householdId];
    if (controller == null || controller.isClosed) return;
    final list = _items.values
        .where((i) => i.householdId == householdId)
        .toList()
      ..sort((a, b) => a.useByDate.compareTo(b.useByDate));
    controller.add(list);
  }

  // ---------------- ReminderRepository ----------------

  @override
  Future<Reminder> setReminder(Reminder reminder) async {
    _reminders[reminder.id] = reminder;
    return reminder;
  }

  @override
  Future<List<Reminder>> getRemindersForHousehold(String householdId) async {
    return _reminders.values
        .where((r) => r.householdId == householdId)
        .toList();
  }

  @override
  Future<void> markTriggered(String reminderId) async {
    final reminder = _reminders[reminderId];
    if (reminder != null && !reminder.triggered) {
      reminder.triggered = true;
      reminder.triggeredAt = DateTime.now();
    }
  }

  @override
  Future<void> cancelReminder(String reminderId) async {
    _reminders.remove(reminderId);
  }

  // ---------------- ActivityLogRepository ----------------

  @override
  Future<void> logActivity(ActivityLogEntry entry) async {
    _activity.insert(0, entry);
    _emitActivity(entry.householdId);
  }

  @override
  Future<List<ActivityLogEntry>> getActivityForHousehold(
      String householdId) async {
    return _activity.where((a) => a.householdId == householdId).toList();
  }

  @override
  Stream<List<ActivityLogEntry>> watchActivityForHousehold(
      String householdId) {
    final controller = _activityStreams.putIfAbsent(
      householdId,
      () => StreamController<List<ActivityLogEntry>>.broadcast(),
    );
    Future.microtask(() => _emitActivity(householdId));
    return controller.stream;
  }

  void _emitActivity(String householdId) {
    final controller = _activityStreams[householdId];
    if (controller == null || controller.isClosed) return;
    controller.add(_activity.where((a) => a.householdId == householdId).toList());
  }

  // ---------------- ShelfLifeRepository ----------------

  @override
  Future<ShelfLifeSuggestion?> getSuggestion({
    required ProductCategory category,
    required StorageLocation location,
    String? itemName,
  }) async {
    // No real dataset in the mock store — reuse the old placeholder
    // estimates so the app still shows *something* offline/without a
    // backend. See ShelfLifeService for the real thing (ApiDataStore).
    final range = ShelfLifeService.suggestShelfLifeDaysRange(category, location);
    if (range == null) return null;
    return ShelfLifeSuggestion(
      status: ShelfLifeRuleStatus.available,
      minDays: range.$1,
      maxDays: range.$2,
      recommendedDays: (range.$1 + range.$2) / 2,
      sourceName: 'Placeholder estimate (no backend connected)',
    );
  }

  @override
  Future<Map<StorageLocation, ShelfLifeSuggestion?>> getStorageSuggestions({
    required ProductCategory category,
    String? itemName,
  }) async {
    return {
      for (final location in StorageLocation.values)
        location: await getSuggestion(category: category, location: location, itemName: itemName),
    };
  }
}
