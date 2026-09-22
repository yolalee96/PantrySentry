/// A household member's profile.
///
/// AC 1.1.1 / AC 1.3.1 / AC 1.4.1
class AppUser {
  /// Unique ID — assigned once at creation and never changed.
  final String id;
  String name;
  final String email;
  /// One of [AvatarCatalog.options] (an emoji key), e.g. 'tomato'.
  String avatarKey;
  /// ID of the household this user currently belongs to (nullable until
  /// they've created/joined one — see Epic 1 flow).
  String? householdId;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.avatarKey,
    this.householdId,
  });

  AppUser copyWith({String? name, String? avatarKey, String? householdId}) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email,
      avatarKey: avatarKey ?? this.avatarKey,
      householdId: householdId ?? this.householdId,
    );
  }
}

/// Small curated set of avatar options (vegetable-themed, matching the
/// app's mascot style) so profile creation doesn't depend on image assets.
class AvatarCatalog {
  static const List<MapEntry<String, String>> options = [
    MapEntry('tomato', '🍅'),
    MapEntry('carrot', '🥕'),
    MapEntry('broccoli', '🥦'),
    MapEntry('corn', '🌽'),
    MapEntry('eggplant', '🍆'),
    MapEntry('pepper', '🫑'),
    MapEntry('potato', '🥔'),
    MapEntry('onion', '🧅'),
    MapEntry('garlic', '🧄'),
    MapEntry('cucumber', '🥒'),
    MapEntry('mushroom', '🍄'),
    MapEntry('avocado', '🥑'),
  ];

  static String emojiFor(String key) {
    return options
        .firstWhere((e) => e.key == key, orElse: () => options.first)
        .value;
  }
}
