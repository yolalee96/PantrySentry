/// Where the PantryBuddy backend (see the separate pantrybuddy-backend
/// project) is running. Change this to match your setup:
///
/// - Testing on Chrome/Windows/macOS on the SAME machine as the backend:
///   'http://localhost:4000' (the default) works as-is.

library;
class ApiConfig {
  static const String baseUrl = 'https://pantry-buddy-phi.vercel.app';
}
