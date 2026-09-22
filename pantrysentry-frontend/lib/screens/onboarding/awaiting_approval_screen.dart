import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../models/join_request.dart';
import '../home/home_screen.dart';
import 'create_or_join_household_screen.dart';

/// Shown after [AppState.requestToJoinHousehold] while status is still
/// PENDING. Live-updates via [AppState.pendingMyJoinRequest] — the moment
/// an admin approves or declines, this screen reacts automatically.
class AwaitingApprovalScreen extends StatelessWidget {
  const AwaitingApprovalScreen({super.key, required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            final request = appState.pendingMyJoinRequest;

            // Approved while this screen was showing — move on to Home.
            if (request == null && appState.hasHousehold) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => HomeScreen(appState: appState)),
                );
              });
              return const Center(child: CircularProgressIndicator());
            }

            // Declined.
            if (request == null || request.status == JoinRequestStatus.declined) {
              return _buildDeclined(context);
            }

            return _buildWaiting(context, request);
          },
        ),
      ),
    );
  }

  Widget _buildWaiting(BuildContext context, JoinRequest request) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text('Waiting for approval', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Your request to join ${request.householdName} has been sent. '
            'An admin needs to approve it before you can get in — this page '
            'will update automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildDeclined(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.block_outlined, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text('Request declined', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'The household admin declined your request to join.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => CreateOrJoinHouseholdScreen(appState: appState)),
            ),
            child: const Text('Try a different household'),
          ),
        ],
      ),
    );
  }
}
