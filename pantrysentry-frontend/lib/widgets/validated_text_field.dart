import 'package:flutter/material.dart';

/// A TextFormField pre-wired so invalid/empty input turns the box red and
/// shows an inline message, matching the app-wide requirement that every
/// profile/household/item form field validate this way.
///
/// Must be used inside a [Form]. Call `formKey.currentState!.validate()`
/// on submit to force all fields to reveal their error state at once, even
/// ones the user hasn't touched yet.
class ValidatedTextField extends StatefulWidget {
  const ValidatedTextField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.hintText,
    this.autofocus = false,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? hintText;
  final bool autofocus;
  final bool obscureText;

  /// Common "required" validator — reused across every form in the app.
  static String? Function(String?) required(String fieldName) {
    return (value) {
      if (value == null || value.trim().isEmpty) {
        return 'Please fill in $fieldName';
      }
      return null;
    };
  }

  /// Required (rejects empty and whitespace-only input, same as
  /// [required]) + must not exceed [maxLength] characters.
  static String? Function(String?) requiredWithMaxLength(String fieldName, int maxLength) {
    return (value) {
      final trimmed = (value ?? '').trim();
      if (trimmed.isEmpty) return 'Please fill in $fieldName';
      if (trimmed.length > maxLength) return '$fieldName must be $maxLength characters or fewer';
      return null;
    };
  }

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Required + must look like a valid email address.
  static String? Function(String?) email() {
    return (value) {
      final trimmed = (value ?? '').trim();
      if (trimmed.isEmpty) return 'Please fill in your email';
      if (!_emailPattern.hasMatch(trimmed)) return 'Enter a valid email address';
      return null;
    };
  }

  /// Required + minimum length for a new password.
  static String? Function(String?) newPassword({int minLength = 8}) {
    return (value) {
      final v = value ?? '';
      if (v.isEmpty) return 'Please create a password';
      if (v.length < minLength) return 'Use at least $minLength characters';
      return null;
    };
  }

  /// Required + must match [passwordController]'s current text.
  static String? Function(String?) confirmPassword(
      TextEditingController passwordController) {
    return (value) {
      if ((value ?? '').isEmpty) return 'Please confirm your password';
      if (value != passwordController.text) return 'Passwords don\'t match';
      return null;
    };
  }

  @override
  State<ValidatedTextField> createState() => _ValidatedTextFieldState();
}

class _ValidatedTextFieldState extends State<ValidatedTextField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      obscureText: widget.obscureText && _obscured,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        suffixIcon: widget.obscureText
            ? IconButton(
                icon: Icon(_obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscured = !_obscured),
              )
            : null,
      ),
      validator: widget.validator ?? ValidatedTextField.required(widget.label.toLowerCase()),
    );
  }
}
