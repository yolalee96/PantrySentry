import 'package:flutter/material.dart';
import '../models/app_user.dart';

/// Grid of selectable vegetable-mascot avatars (AC 1.1.1). Renders a red
/// prompt underneath if nothing is selected yet and [showError] is true —
/// used to keep avatar selection consistent with the rest of the form
/// validation style even though it isn't a text field.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({
    super.key,
    required this.selectedKey,
    required this.onSelected,
    this.showError = false,
  });

  final String? selectedKey;
  final ValueChanged<String> onSelected;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose an avatar', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(
              color: showError ? Colors.red : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: AvatarCatalog.options.map((entry) {
              final isSelected = entry.key == selectedKey;
              return GestureDetector(
                onTap: () => onSelected(entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                        : Colors.grey.shade100,
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade300,
                      width: isSelected ? 2.5 : 1,
                    ),
                  ),
                  child: Text(entry.value, style: const TextStyle(fontSize: 26)),
                ),
              );
            }).toList(),
          ),
        ),
        if (showError)
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Please pick an avatar',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
