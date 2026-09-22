import '../models/food_item.dart';

/// Business rules for reminders that don't belong on the model or the UI.
class ReminderService {
  /// AC 3.1.2 — a custom lead time must not push the reminder date past
  /// (or on) the item's use-by date.
  static bool isValidLeadTime({
    required int leadTimeDays,
    required DateTime useByDate,
  }) {
    if (leadTimeDays <= 0) return false;
    final reminderDate = useByDate.subtract(Duration(days: leadTimeDays));
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    return reminderDate.isAfter(todayDateOnly) ||
        reminderDate.isAtSameMomentAs(todayDateOnly);
  }

  /// AC 3.2.1 — whether a reminder's lead-time window has been reached for
  /// [item] right now (and hasn't fired yet, AC 3.2.2 is enforced by the
  /// caller checking `reminder.triggered` before calling this).
  static bool isDue({required FoodItem item, required int leadTimeDays}) {
    return item.isActive && item.daysLeft <= leadTimeDays;
  }
}
