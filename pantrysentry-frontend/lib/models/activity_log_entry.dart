/// One row in the household's shared "Recent Activity" feed.
///
/// Epic 3 — AC 3.7.1
enum ActivityAction { added, edited, removed, consumed, discarded, donated, joined }

class ActivityLogEntry {
  final String id;
  final String householdId;
  final String actingUserId;
  final String actingUserName; // denormalised for easy display in the feed
  final ActivityAction action;
  final String itemName; // or member name for 'joined' entries
  final DateTime timestamp;

  ActivityLogEntry({
    required this.id,
    required this.householdId,
    required this.actingUserId,
    required this.actingUserName,
    required this.action,
    required this.itemName,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get message {
    switch (action) {
      case ActivityAction.added:
        return '$actingUserName added $itemName';
      case ActivityAction.edited:
        return '$actingUserName updated $itemName';
      case ActivityAction.removed:
        return '$actingUserName removed $itemName';
      case ActivityAction.consumed:
        return '$actingUserName marked $itemName as consumed';
      case ActivityAction.discarded:
        return '$actingUserName marked $itemName as discarded';
      case ActivityAction.donated:
        return '$actingUserName marked $itemName as donated';
      case ActivityAction.joined:
        return '$actingUserName joined the household';
    }
  }
}
