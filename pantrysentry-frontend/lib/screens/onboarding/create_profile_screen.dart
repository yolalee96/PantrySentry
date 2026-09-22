import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../data/repository.dart' show AuthException;
import '../../widgets/validated_text_field.dart';
import '../../widgets/avatar_picker.dart';
import '../../widgets/app_logo.dart';
import 'create_or_join_household_screen.dart';
import 'sign_in_screen.dart';

/// AC 1.1.1 — enter name + pick avatar, save profile.
/// Extended with email/password/confirm-password per team decision (the
/// prototype's "Create account" screen) — see [SignInScreen] for the
/// matching "Welcome back" screen and forgot-password flow.
class CreateProfileScreen extends StatefulWidget {
  const CreateProfileScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _avatarKey;
  bool _avatarTouched = false;
  bool _submitting = false;
  String? _submitError;

  Future<void> _submit() async {
    setState(() {
      _avatarTouched = true;
      _submitError = null;
    });
    final formValid = _formKey.currentState!.validate();
    if (!formValid || _avatarKey == null) return;

    setState(() => _submitting = true);
    try {
      await widget.appState.signUp(
        name: _nameController.text.trim(),
        avatarKey: _avatarKey!,
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => CreateOrJoinHouseholdScreen(appState: widget.appState),
      ));
    } on AuthException catch (e) {
      setState(() {
        _submitting = false;
        _submitError = e.message;
      });
    } catch (e) {
      setState(() {
        _submitting = false;
        _submitError = 'Something went wrong: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 16),
                const AppLogo(),
                const SizedBox(height: 20),
                Text('Create account', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  'Join your household and start reducing food waste.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 28),
                ValidatedTextField(
                  label: 'Display name',
                  controller: _nameController,
                  autofocus: true,
                  validator: ValidatedTextField.requiredWithMaxLength('your name', 50),
                ),
                const SizedBox(height: 16),
                ValidatedTextField(
                  label: 'Email',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: ValidatedTextField.email(),
                ),
                const SizedBox(height: 16),
                ValidatedTextField(
                  label: 'Password',
                  controller: _passwordController,
                  obscureText: true,
                  validator: ValidatedTextField.newPassword(),
                ),
                const SizedBox(height: 16),
                ValidatedTextField(
                  label: 'Confirm password',
                  controller: _confirmPasswordController,
                  obscureText: true,
                  validator: ValidatedTextField.confirmPassword(_passwordController),
                ),
                const SizedBox(height: 20),
                AvatarPicker(
                  selectedKey: _avatarKey,
                  showError: _avatarTouched && _avatarKey == null,
                  onSelected: (key) => setState(() {
                    _avatarKey = key;
                    _avatarTouched = true;
                  }),
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create account'),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                              builder: (_) => SignInScreen(appState: widget.appState),
                            )),
                    child: const Text('Already have an account? Sign in'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
