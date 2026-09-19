import 'package:flutter/material.dart';

import '../../core/data/preset_store.dart';
import '../../core/theme/app_theme.dart';

/// A saved recipe, as it appears on Home and above the target grid.
///
/// The name is what the user chose, and the line under it is what will actually
/// happen — so a preset called "Web photos" never has to be remembered to be
/// understood, and one whose quality was edited last month says so.
class PresetChip extends StatelessWidget {
  const PresetChip({super.key, required this.preset, required this.onTap});

  final ConversionPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              preset.isOptimize ? Icons.compress_rounded : Icons.swap_horiz_rounded,
              size: 16,
              color: t.textSecondary,
            ),
            const SizedBox(width: 9),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preset.name,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  preset.summary,
                  style: TextStyle(fontSize: 11, color: t.textFaint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks the user to name a recipe.
///
/// Returns the name, or null when they backed out.
Future<String?> askPresetName(
  BuildContext context, {
  required String suggested,
  List<String> existing = const [],
  String title = 'Save as a preset',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        suggested: suggested,
        existing: existing,
        title: title,
      ),
    );

/// The dialog is a widget of its own so the field's controller lives and dies
/// with the route. Disposing it as soon as `showDialog` returned crashed the
/// dialog's own exit animation, which is still building the field.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.suggested,
    required this.existing,
    required this.title,
  });

  final String suggested;
  final List<String> existing;
  final String title;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.suggested);
  late final Set<String> _taken = {for (final n in widget.existing) n.toLowerCase()};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      title: Text(widget.title),
      content: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, _) {
          final typed = value.text.trim();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Something you will recognise in a chip',
                ),
                onSubmitted: (_) => _save(),
              ),
              // Warned about as it is typed, not after the fact: replacing
              // someone's preset is the one outcome here that is not obvious
              // from the outside.
              if (_taken.contains(typed.toLowerCase())) ...[
                const SizedBox(height: 12),
                Text(
                  'A preset called "$typed" already exists, and saving replaces '
                  'its recipe.',
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: t.textFaint),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => TextButton(
            onPressed: value.text.trim().isEmpty ? null : _save,
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}
