import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'data/api_data_store.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'screens/onboarding/create_profile_screen.dart';
import 'screens/onboarding/create_or_join_household_screen.dart';
import 'screens/onboarding/awaiting_approval_screen.dart';
import 'screens/onboarding/reset_password_screen.dart';
import 'screens/home/home_screen.dart';

void main() {
  runApp(PantryBuddyApp());
}

/// If the current URL is a password-reset link (from the email — see
/// util/email.js on the backend), returns its token. Handles both
/// Flutter web's default hash-based URLs
/// (https://app.com/#/reset-password?token=xyz) and path-based ones
/// (https://app.com/reset-password?token=xyz, if usePathUrlStrategy() is
/// ever enabled) — checks the plain query string first, then falls back
/// to parsing the URL fragment's own query string. Returns null on any
/// other platform (Uri.base isn't a meaningful browser address there).
String? _extractResetTokenFromUrl() {
  if (!kIsWeb) return null;
  final uri = Uri.base;
  if (uri.queryParameters['token'] != null) return uri.queryParameters['token'];

  final fragment = uri.fragment; // e.g. "/reset-password?token=xyz"
  final qIndex = fragment.indexOf('?');
  if (qIndex == -1) return null;
  final params = Uri.splitQueryString(fragment.substring(qIndex + 1));
  return params['token'];
}

class PantryBuddyApp extends StatefulWidget {
  PantryBuddyApp({super.key});

  // Real backend (see the separate pantrybuddy-backend project and
  // lib/data/api_config.dart for the URL it points at). To go back to
  // the old no-backend mock for quick UI testing, swap this for
  // `InMemoryDataStore()` from data/mock_data_store.dart instead.
  final ApiDataStore dataStore = ApiDataStore();

  @override
  State<PantryBuddyApp> createState() => _PantryBuddyAppState();
}

class _PantryBuddyAppState extends State<PantryBuddyApp> {
  late final AppState _appState;
  Timer? _reminderTimer;
  bool _restoringSession = true; // "stay logged in" — brief check at startup before showing sign-in

  @override
  void initState() {
    super.initState();
    _appState = AppState(
      userRepo: widget.dataStore,
      householdRepo: widget.dataStore,
      inventoryRepo: widget.dataStore,
      reminderRepo: widget.dataStore,
      activityRepo: widget.dataStore,
      shelfLifeRepo: widget.dataStore,
      recognitionRepo: widget.dataStore,
    );
    // Skip session restore entirely if this is a password-reset link —
    // that flow doesn't need (and shouldn't wait on) a saved session.
    if (_extractResetTokenFromUrl() != null) {
      _restoringSession = false;
    } else {
      _appState.tryRestoreSession().then((_) {
        if (mounted) setState(() => _restoringSession = false);
      });
    }
    // AC 3.2.1 — periodically checks for due reminders. A real deployment
    // would use a platform notification package (e.g. flutter_local_notifications)
    // to fire an actual push/local notification here; for iteration 1 this
    // surfaces a snackbar as a stand-in so the reminder flow is demoable.
    _reminderTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final due = await _appState.checkDueReminders();
      if (due.isNotEmpty && mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('${due.length} item(s) nearing their expiry — check Reminders')),
        );
      }
    });
  }

  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void dispose() {
    _reminderTimer?.cancel();
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      title: 'PantryBuddy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: ListenableBuilder(
        listenable: _appState,
        builder: (context, _) {
          if (_restoringSession) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final resetToken = _extractResetTokenFromUrl();
          if (resetToken != null) {
            return ResetPasswordScreen(appState: _appState, token: resetToken);
          }
          if (!_appState.hasProfile) {
            return CreateProfileScreen(appState: _appState);
          }
          if (_appState.isAwaitingApproval) {
            return AwaitingApprovalScreen(appState: _appState);
          }
          if (!_appState.hasHousehold) {
            return CreateOrJoinHouseholdScreen(appState: _appState);
          }
          return HomeScreen(appState: _appState);
        },
      ),
    );
  }
}
