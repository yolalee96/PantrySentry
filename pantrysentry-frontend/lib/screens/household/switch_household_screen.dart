import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../models/household.dart';
import '../onboarding/create_or_join_household_screen.dart';

/// Usability-tested request: a user can belong to more than one
/// household (e.g. their family's kitchen and a shared flat), and needs
/// a way to move between them — and to leave one — from the Profile
/// screen.
class SwitchHouseholdScreen extends StatefulWidget {
  const SwitchHouseholdScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<SwitchHouseholdScreen> createState() => _SwitchHouseholdScreenState();
}

class _SwitchHouseholdScreenState extends State<SwitchHouseholdScreen> {
  bool _busy = false;

  Future<void> _switchTo(Household household) async {
    if (household.id == widget.appState.currentHousehold?.id) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.appState.switchHousehold(household);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t switch households: $e')),
        );
      }
    }
  }

  Future<void> _confirmLeave(BuildContext context, Household household) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave "${household.name}"?'),
        content: const Text(
          'You\'ll lose access to this household\'s inventory unless someone invites you back. '
          'If you\'re the only admin, no one will be able to manage this household or approve new members after you leave.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _busy = true);
    try {
      await widget.appState.leaveHousehold(household.id);
      if (context.mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You left "${household.name}".')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t leave this household: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Switch household')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.appState,
          builder: (context, _) {
            final households = widget.appState.myHouseholds;
            final currentId = widget.appState.currentHousehold?.id;
            return Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Households you belong to',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (households.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Loading...', style: TextStyle(color: Colors.grey.shade600)),
                      )
                    else
                      Card(
                        child: Column(
                          children: households.map((h) {
                            final isCurrent = h.id == currentId;
                            return ListTile(
                              leading: Icon(
                                isCurrent ? Icons.check_circle : Icons.home_outlined,
                                color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.grey.shade500,
                              ),
                              title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: isCurrent ? const Text('Currently active') : null,
                              onTap: _busy ? null : () => _switchTo(h),
                              trailing: IconButton(
                                icon: const Icon(Icons.exit_to_app, color: Colors.red),
                                tooltip: 'Leave household',
                                onPressed: _busy ? null : () => _confirmLeave(context, h),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => CreateOrJoinHouseholdScreen(
                                  appState: widget.appState,
                                  isAddingAdditionalHousehold: true,
                                ),
                              )),
                      icon: const Icon(Icons.add),
                      label: const Text('Create or join another household'),
                    ),
                  ],
                ),
                if (_busy)
                  Container(
                    color: Colors.black.withValues(alpha: 0.15),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
