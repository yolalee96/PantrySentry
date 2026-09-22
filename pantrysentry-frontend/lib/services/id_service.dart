import 'dart:math';

/// Generates unique, human-shareable IDs — used for both household IDs
/// (which double as invite codes, see AC 3.4.1) and user IDs.
///
/// This is a lightweight, dependency-free generator so iteration 1 doesn't
/// need an extra pub package. If the DB teammate's backend assigns its own
/// IDs (e.g. server-generated UUIDs), those can be used instead — nothing
/// else in the app assumes a particular ID format.
class IdService {
  static final Random _random = Random.secure();
  static const _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no O/0/I/1

  /// Returns something like "HH-7K2QX9". [prefix] is only for readability
  /// while debugging (e.g. 'hh', 'usr') — no part of the data model
  /// requires a particular ID format or length.
  static String newId(String prefix) {
    final code = List.generate(
        6, (_) => _chars[_random.nextInt(_chars.length)]).join();
    return '${prefix.toUpperCase()}-$code';
  }
}
