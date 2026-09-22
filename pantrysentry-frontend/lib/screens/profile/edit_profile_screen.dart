import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../widgets/validated_text_field.dart';
import '../../widgets/avatar_picker.dart';

/// AC 1.4.1 — edit name/avatar, save, reflected across the app (state is
/// a shared ChangeNotifier so every screen listening to it updates live).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late String? _avatarKey;
  bool _avatarTouched = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = widget.appState.currentUser!;
    _nameController = TextEditingController(text: user.name);
    _avatarKey = user.avatarKey;
  }

  Future<void> _submit() async {
    setState(() => _avatarTouched = true);
    final formValid = _formKey.currentState!.validate();
    if (!formValid || _avatarKey == null) return;

    setState(() => _submitting = true);
    await widget.appState.updateProfile(
      name: _nameController.text.trim(),
      avatarKey: _avatarKey,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                ValidatedTextField(
                  label: 'Your name',
                  controller: _nameController,
                  validator: ValidatedTextField.requiredWithMaxLength('your name', 50),
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
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    // Changed color of Save Changes button for better visibility.
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
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
                        : const Text('Save changes', style: TextStyle(fontSize: 15.5)),
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
