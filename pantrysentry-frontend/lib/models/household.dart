import 'app_user.dart';

/// Matches schema.sql `team_members.role` — ADMIN or MEMBER only, no
/// separate "owner" concept. Whoever creates the household is its
/// first ADMIN.
enum MembershipRole { admin, member }

/// Matches schema.sql `team_members.status`.
enum MembershipStatus { active, inactive }

/// A shared household/kitchen group. Matches schema.sql `teams`.
///
/// AC 1.2.1 / AC 1.2.2 / AC 3.4.1 / AC 3.5.1
class Household {
  /// Unique ID — also doubles as the join/invite code (AC 3.4.1).
  final String id;
  String name;
  final DateTime createdAt;

  Household({
    required this.id,
    required this.name,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// A household member paired with their role/status — what
/// `HouseholdRepository.getMembers` returns, mirroring a
/// `team_members` join `users` query.
class HouseholdMember {
  final AppUser user;
  final MembershipRole role;
  final MembershipStatus status;

  HouseholdMember({required this.user, required this.role, required this.status});
}
