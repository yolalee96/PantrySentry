import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../state/app_state.dart';

/// AC 3.4.1 — generate an invite code to share with a family member.
/// The household's own unique ID doubles as the invite code (kept simple
/// for iteration 1; a friend-facing deep link could wrap this later).
class InviteScreen extends StatelessWidget {
  const InviteScreen({super.key, required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final household = appState.currentHousehold;
    return Scaffold(
      appBar: AppBar(title: const Text('Invite a member')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share this code with a family member. When they enter it on '
                'the "Join existing" tab, they\'ll get access to ${household?.name ?? 'your household'}.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.6),
                ),
                child: Column(
                  children: [
                    Text(
                      'INVITE CODE', 
                      style: TextStyle(
                        color: Colors.grey.shade700, 
                        fontSize: 14, 
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                        )
                    ),
                    const SizedBox(height: 8),
                    Text(
                      household?.id ?? '',
                      style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, letterSpacing: 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: household?.id ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invite code copied')),
                  );
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
