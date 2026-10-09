import 'package:flutter/material.dart';
import '../models/app_user.dart';

/// Grid of selectable vegetable-mascot avatars (AC 1.1.1). Renders a red
/// prompt underneath if nothing is selected yet and [showError] is true —
/// used to keep avatar selection consistent with the rest of the form
/// validation style even though it isn't a text field.
/// Update: Increased the number of avatars to 24, adding more variety and
/// options for users to choose from (fruits, other grocery food items),
/// and also neatly arranging avatars in a grid for users to scroll up and
/// down to browse the avatars. Also, AvatarPicker now extends StatefulWidget
/// to allow for a scrollable view of the avatars, improving the user experience
/// when selecting an avatar.
class AvatarPicker extends StatefulWidget {
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
  // Rewriting the widget to use a grid layout for the avatars, allowing 
  // avatars to be displayed in a scrollable view.
  State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose an avatar',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Scroll to browse, then tap to select.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),

        Container(
          height: 220,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.showError
                  ? Colors.red
                  : Colors.grey.shade300,
              width: widget.showError ? 2 : 1,
            ),
          ),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: GridView.builder(
              controller: _scrollController,
              primary: false,
              padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 76,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: AvatarCatalog.options.length,
              itemBuilder: (context, index) {
                final entry = AvatarCatalog.options[index];
                final isSelected = entry.key == widget.selectedKey;

                return Semantics(
                  label: '${entry.key} avatar',
                  selected: isSelected,
                  button: true,
                  child: Tooltip(
                    message: entry.key,
                    child: Material(
                      color: isSelected
                          ? primary.withValues(alpha: 0.15)
                          : Colors.grey.shade100,
                      shape: CircleBorder(
                        side: BorderSide(
                          color: isSelected
                              ? primary
                              : Colors.grey.shade300,
                          width: isSelected ? 2.5 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => widget.onSelected(entry.key),
                        child: Center(
                          child: Text(
                            entry.value,
                            style: const TextStyle(fontSize: 26),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        if (widget.showError)
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
// Yola