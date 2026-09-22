import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../models/app_user.dart';
import '../../models/join_request.dart';

/// Admin-only (see [AppState.isAdmin]) — approve or decline pending
/// [JoinRequest]s for the current household.
class PendingRequestsScreen extends StatelessWidget {
  const PendingRequestsScreen({super.key, required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pending requests')),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final requests = appState.pendingRequests;
          if (requests.isEmpty) {
            return Center(
              child: Text('No pending requests.', style: TextStyle(color: Colors.grey.shade600)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _RequestCard(appState: appState, request: requests[i]),
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.appState, required this.request});
  final AppState appState;
  final JoinRequest request;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.grey.shade100,
                  child: Text(AvatarCatalog.emojiFor(request.userAvatarKey)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(request.userName, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => appState.declineJoinRequest(request),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => appState.approveJoinRequest(request),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
