import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../data/repository.dart' show AuthException;
import '../../widgets/validated_text_field.dart';
import '../../widgets/app_logo.dart';
import 'sign_in_screen.dart';

/// Reached via the link in the password-reset email:
/// https://<app-url>/#/reset-password?token=... — main.dart reads the
/// token from the URL on startup and routes here directly. Not reachable
/// from anywhere else in the app's normal navigation.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.appState, required this.token});
  final AppState appState;
  final String token;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _submitting = false;
  bool _done = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.appState.resetPassword(
        token: widget.token,
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _done = true;
      });
    } on AuthException catch (e) {
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = 'Something went wrong: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _done ? _buildDone(context) : _buildForm(context),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        children: [
          const SizedBox(height: 16),
          const AppLogo(),
          const SizedBox(height: 20),
          Text('Choose a new password', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Enter a new password for your account below.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 28),
          ValidatedTextField(
            label: 'New password',
            controller: _passwordController,
            autofocus: true,
            obscureText: true,
            validator: ValidatedTextField.newPassword(),
          ),
          const SizedBox(height: 16),
          ValidatedTextField(
            label: 'Confirm new password',
            controller: _confirmPasswordController,
            obscureText: true,
            validator: ValidatedTextField.confirmPassword(_passwordController),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Reset password'),
          ),
        ],
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
        const SizedBox(height: 16),
        Text('Password updated', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'You can now sign in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => SignInScreen(appState: widget.appState)),
          ),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}
