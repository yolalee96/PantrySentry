/// An expiry reminder attached to a [FoodItem].
///
/// Epic 3 — AC 3.1.1 / AC 3.1.2 / AC 3.2.1 / AC 3.2.2 / AC 3.3.1
class Reminder {
  final String id;
  final String itemId;
  final String householdId;
  final String createdByUserId;
  /// Days before the item's use-by date that this reminder fires.
  int leadTimeDays;
  bool wasCustomLeadTime;
  bool triggered; // AC 3.2.2 — prevents duplicate notifications
  DateTime? triggeredAt;

  Reminder({
    required this.id,
    required this.itemId,
    required this.householdId,
    required this.createdByUserId,
    required this.leadTimeDays,
    this.wasCustomLeadTime = false,
    this.triggered = false,
    this.triggeredAt,
  });
}

/// Preset lead-time options shown in the UI (AC 3.1.1). A custom option is
/// offered alongside these — see ShelfLifeService for suggested defaults
/// based on the item's shelf-life category.
const List<int> presetLeadTimesDays = [7, 3, 1];
