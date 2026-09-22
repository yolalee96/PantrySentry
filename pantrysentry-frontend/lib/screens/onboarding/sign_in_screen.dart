import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../data/repository.dart' show AuthException;
import '../../widgets/validated_text_field.dart';
import '../../widgets/app_logo.dart';
import '../home/home_screen.dart';
import '../onboarding/create_or_join_household_screen.dart';
import 'create_profile_screen.dart';
import 'forgot_password_screen.dart';

/// "Welcome back" sign-in screen from the prototype, plus a Forgot
/// password link (AC: password reset request — see [ForgotPasswordScreen]).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.appState.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      final hasHousehold = widget.appState.currentHousehold != null;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => hasHousehold
            ? HomeScreen(appState: widget.appState)
            : CreateOrJoinHouseholdScreen(appState: widget.appState),
      ));
    } on AuthException catch (e) {
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      // Belt-and-braces: catch anything AuthException didn't anticipate
      // too, so a surprise error type can never leave this screen stuck
      // on its loading spinner forever.
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
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 16),
                const AppLogo(),
                const SizedBox(height: 20),
                Text('Welcome back', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  'Sign in to manage your household food.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 28),
                ValidatedTextField(
                  label: 'Email',
                  controller: _emailController,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  validator: ValidatedTextField.email(),
                ),
                const SizedBox(height: 16),
                ValidatedTextField(
                  label: 'Password',
                  controller: _passwordController,
                  obscureText: true,
                  validator: ValidatedTextField.required('your password'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ForgotPasswordScreen(appState: widget.appState),
                            )),
                    child: const Text('Forgot password?'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  // Changed color of Sign in button for better visibility.
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 34, 142, 38),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  // Yola
                  
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                              builder: (_) => CreateProfileScreen(appState: widget.appState),
                            )),
                    child: const Text('New to Pantry Buddy? Create account'),
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
