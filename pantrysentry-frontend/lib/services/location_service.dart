import 'package:geolocator/geolocator.dart';

/// Result of asking for the user's location (Epic 7, AC 7.1.2–7.1.4).
class LocationResult {
  const LocationResult.found(this.latitude, this.longitude) : problem = null;
  const LocationResult.failed(this.problem)
      : latitude = null,
        longitude = null;

  final double? latitude;
  final double? longitude;
  /// Why there's no location, in words the user can act on — null on success.
  final String? problem;

  bool get ok => problem == null;
}

/// Thin wrapper around geolocator. Works on web (browser location prompt),
/// Android and iOS.
class LocationService {
  /// AC 7.1.2 — asks for permission only if it hasn't been decided yet;
  /// AC 7.1.3 — if it's already granted, goes straight to the location;
  /// AC 7.1.4 — any failure comes back as an explanation, so the screen
  /// can offer the "search by area" box instead.
  static Future<LocationResult> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.failed(
            'Location is turned off on this device. Turn it on, or search by area instead.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult.failed(
            'Location permission was not given. You can search by area instead.');
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failed(
            'Location access is blocked for this app. Allow it in your browser or phone settings, '
            'or search by area instead.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
      );
      return LocationResult.found(position.latitude, position.longitude);
    } catch (_) {
      return const LocationResult.failed(
          'We couldn\'t get your location right now. Try again, or search by area instead.');
    }
  }
}
