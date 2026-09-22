/// Matches schema.sql `join_requests.status`.
enum JoinRequestStatus { pending, approved, declined }

/// A request from a user to join a household — matches schema.sql
/// `join_requests`. An ADMIN of the target household must approve or
/// decline it (see AC 3.5.1, revised per team decision: joining now
/// requires admin approval rather than being instant).
class JoinRequest {
  final String id;
  final String householdId;
  final String householdName; // denormalised for display on the requester's "waiting" screen
  final String userId;
  final String userName; // denormalised for display in the admin's approval list
  final String userAvatarKey;
  JoinRequestStatus status;
  final DateTime requestedAt;
  DateTime? reviewedAt;
  String? reviewedByUserId;

  JoinRequest({
    required this.id,
    required this.householdId,
    required this.householdName,
    required this.userId,
    required this.userName,
    required this.userAvatarKey,
    this.status = JoinRequestStatus.pending,
    DateTime? requestedAt,
    this.reviewedAt,
    this.reviewedByUserId,
  }) : requestedAt = requestedAt ?? DateTime.now();
}
