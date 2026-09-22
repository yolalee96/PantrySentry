import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../data/repository.dart' show AuthException;
import '../../widgets/validated_text_field.dart';
import '../home/home_screen.dart';
import 'awaiting_approval_screen.dart';

/// AC 1.2.1 / AC 1.2.2 — create a household.
/// AC 3.5.1 (revised) — or request to join one via an invite code, shown
/// as a second tab. Joining now requires admin approval (matches
/// schema.sql's join_requests table) instead of being instant — see
/// [AwaitingApprovalScreen].
///
/// [isAddingAdditionalHousehold] distinguishes the normal onboarding
/// entry point (user has no household yet — reached as the app's root
/// screen) from being pushed on top of an existing household (from
/// Profile > Switch household > "Join another"). In the latter case,
/// success returns to the household the user was already using instead
/// of navigating away into a new Home/waiting screen.
class CreateOrJoinHouseholdScreen extends StatefulWidget {
  const CreateOrJoinHouseholdScreen({
    super.key,
    required this.appState,
    this.isAddingAdditionalHousehold = false,
  });
  final AppState appState;
  final bool isAddingAdditionalHousehold;

  @override
  State<CreateOrJoinHouseholdScreen> createState() =>
      _CreateOrJoinHouseholdScreenState();
}

class _CreateOrJoinHouseholdScreenState
    extends State<CreateOrJoinHouseholdScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _createFormKey = GlobalKey<FormState>();
  final _joinFormKey = GlobalKey<FormState>();
  final _householdNameController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  bool _submitting = false;
  String? _joinError;
  String? _createError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> _createHousehold() async {
    if (!_createFormKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _createError = null;
    });
    try {
      await widget.appState.createHousehold(name: _householdNameController.text.trim());
      if (!mounted) return;
      if (widget.isAddingAdditionalHousehold) {
        // currentHousehold is already switched to the new one by
        // createHousehold() — just return to the app's root rather than
        // pushing a second Home screen on top of this navigation stack.
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(appState: widget.appState)),
        );
      }
    } catch (e) {
      setState(() {
        _submitting = false;
        _createError = e is AuthException ? e.message : 'Something went wrong: $e';
      });
    }
  }

  Future<void> _requestToJoin() async {
    if (!_joinFormKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _joinError = null;
    });
    try {
      await widget.appState.requestToJoinHousehold(
        inviteCode: _inviteCodeController.text.trim(),
        blockAppWhilePending: !widget.isAddingAdditionalHousehold,
      );
      if (!mounted) return;
      if (widget.isAddingAdditionalHousehold) {
        // Don't send them into the blocking "awaiting approval" screen —
        // they still have their current household to use meanwhile.
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Request sent — waiting for that household\'s admin to approve it.'),
        ));
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AwaitingApprovalScreen(appState: widget.appState)),
        );
      }
    } on AuthException catch (e) {
      setState(() {
        _submitting = false;
        _joinError = e.message;
      });
    } catch (e) {
      setState(() {
        _submitting = false;
        _joinError = 'Something went wrong: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your household'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Create new'), Tab(text: 'Join existing')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCreateTab(context),
          _buildJoinTab(context),
        ],
      ),
    );
  }

  Widget _buildCreateTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _createFormKey,
        child: ListView(
          children: [
            Text(
              'Give your shared kitchen a name so your household can find it. '
              'You\'ll be its admin.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ValidatedTextField(
              label: 'Household name',
              hintText: 'e.g. The Tan Family Kitchen',
              controller: _householdNameController,
              validator: ValidatedTextField.requiredWithMaxLength('a household name', 40),
            ),
            if (_createError != null) ...[
              const SizedBox(height: 10),
              Text(_createError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _submitting ? null : _createHousehold,
              child: _submitting
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create household'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _joinFormKey,
        child: ListView(
          children: [
            Text(
              'Enter the invite code a household member shared with you. '
              'An admin will need to approve your request.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ValidatedTextField(
              label: 'Invite code',
              hintText: 'e.g. HH-7K2QX9',
              controller: _inviteCodeController,
              validator: ValidatedTextField.required('the invite code'),
            ),
            if (_joinError != null) ...[
              const SizedBox(height: 10),
              Text(_joinError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _submitting ? null : _requestToJoin,
              child: _submitting
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Request to join'),
            ),
          ],
        ),
      ),
    );
  }
}
