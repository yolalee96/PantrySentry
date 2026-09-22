import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../models/app_user.dart';
import '../../models/household.dart';
import '../household/invite_screen.dart';
import '../household/activity_log_screen.dart';
import '../household/pending_requests_screen.dart';
import '../household/switch_household_screen.dart';
import '../onboarding/create_profile_screen.dart';
import 'edit_profile_screen.dart';

/// AC 1.3.1 — view profile: name, avatar, household name, and the
/// household's member list (Epic 1 DOD).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.appState});
  final AppState appState;

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You\'ll need to sign in again to get back to your household.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await appState.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => CreateProfileScreen(appState: appState)),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final user = appState.currentUser;
          final household = appState.currentHousehold;
          if (user == null) return const SizedBox.shrink();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                      child: Text(AvatarCatalog.emojiFor(user.avatarKey),
                          style: const TextStyle(fontSize: 36)),
                    ),
                    const SizedBox(height: 12),
                    Text(user.name, style: Theme.of(context).textTheme.titleLarge),
                    Text(household?.name ?? '', style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('User ID: ${user.id}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500)),    
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EditProfileScreen(appState: appState),
                  )),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit profile', style: TextStyle(fontSize: 15.5)),
                ),
              ),
              const SizedBox(height: 28),
              Text('Household', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.swap_horiz),
                      title: const Text('Switch household'),
                      subtitle: appState.myHouseholds.length > 1
                          ? Text('${appState.myHouseholds.length} households')
                          : null,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SwitchHouseholdScreen(appState: appState),
                      )),
                    ),
                    const Divider(height: 1),
                    ...appState.householdMembers.map((member) => ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                            child: Text(AvatarCatalog.emojiFor(member.user.avatarKey)),
                          ),
                          title: Text(member.user.name),
                          subtitle: Text(member.role == MembershipRole.admin ? 'Admin' : 'Member'),
                          trailing: member.user.id == user.id
                              ? const Chip(label: Text('You'), visualDensity: VisualDensity.compact)
                              : null,
                        )),
                    ListTile(
                      leading: const Icon(Icons.person_add_alt_outlined),
                      title: const Text('Invite a member'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => InviteScreen(appState: appState),
                      )),
                    ),
                    if (appState.isAdmin)
                      ListTile(
                        leading: const Icon(Icons.pending_actions_outlined),
                        title: const Text('Pending requests'),
                        trailing: appState.pendingRequests.isEmpty
                            ? null
                            : Chip(
                                label: Text('${appState.pendingRequests.length}'),
                                visualDensity: VisualDensity.compact,
                              ),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PendingRequestsScreen(appState: appState),
                        )),
                      ),
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('Recent activity'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ActivityLogScreen(appState: appState),
                      )),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmSignOut(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out', style: TextStyle(fontSize: 15.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
