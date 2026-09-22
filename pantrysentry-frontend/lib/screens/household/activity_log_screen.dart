import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../utils/date_format.dart';
import '../../models/app_user.dart';

/// AC 3.7.1 — shared "Recent Activity" feed, visible to all members.
class ActivityLogScreen extends StatelessWidget {
  const ActivityLogScreen({super.key, required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recent activity')),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final log = appState.activityLog;
          if (log.isEmpty) {
            return Center(
              child: Text('No activity yet.', style: TextStyle(color: Colors.grey.shade600)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: log.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            
            // Modified the itemBuilder to display the avatars with each household member.
            itemBuilder: (context, i) {
              final entry = log[i];
              // Find the person who performed this action.
              AppUser? actor;

              for (final member in appState.householdMembers) {
                if (member.user.id == entry.actingUserId) {
                  actor = member.user;
                  break;
                }
              }

              // Use the current user's profile when this is their activity.
              final currentUser = appState.currentUser;
              if (currentUser != null &&
                currentUser.id == entry.actingUserId) {
                actor = currentUser;
              }

              final avatarKey = actor?.avatarKey;

              return ListTile(
                leading: CircleAvatar(
                radius: 22,
                backgroundColor:
                  Theme.of(context).colorScheme.primaryContainer,
                child: avatarKey != null
                  ? Text(
                    AvatarCatalog.emojiFor(avatarKey),
                    style: const TextStyle(fontSize: 24),
                  )
                  : const Icon(Icons.person_outline),
                ),
                title: Text(entry.message),
                subtitle: Text(formatRelativeTime(entry.timestamp)),
            );
            },
            // Yola
          );
        },
      ),
    );
  }
}
