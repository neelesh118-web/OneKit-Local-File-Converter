import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/ads/ads.dart';
import '../../core/data/preset_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/starfield.dart';
import 'preset_chip.dart';

/// The saved recipes, and what to do with them.
///
/// This screen does not build a recipe from scratch, and says so: a recipe is
/// made where it exists — a file, a target, and the settings that suit it —
/// which is why creating one lives in the options sheet rather than here.
/// Editing a preset in the abstract would mean inventing a file to preview the
/// choices against.
class PresetsPage extends StatelessWidget {
  const PresetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final store = context.watch<PresetStore>();
    final presets = store.presets;

    return Scaffold(
      backgroundColor: t.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Starfield(density: 0.8, speed: 0.7),
          SafeArea(
            child: Column(
              children: [
                PageHeader(title: 'Presets', onBack: () => context.pop()),
                Expanded(
                  child: presets.isEmpty
                      ? _empty(context)
                      : ListView(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            0,
                            20,
                            MediaQuery.viewPaddingOf(context).bottom + 24,
                          ),
                          children: [
                            const SizedBox(height: 6),
                            for (final preset in presets)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _PresetRow(preset: preset),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              'Presets are saved on this device only, and can be run '
                              'from Home or from the target screen. Save one from the '
                              'options sheet while you are setting a file up.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: t.textFaint,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const AppBanner(),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        EmptyState(
          icon: Icons.bookmark_border_rounded,
          title: 'No presets yet',
          message: 'A preset is a recipe you reuse: a format, plus the quality,\n'
              'resize and metadata choices that go with it.',
          action: FilledButton(
            // Home, where a file can actually be picked: the convert screen
            // without one has nothing to show.
            onPressed: () => context.go('/'),
            child: const Text('Pick a file to start'),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Set a file up the way you like it, then tap "Save as a preset" in the '
          'options sheet. It shows up on Home and above the target grid, and runs '
          'in one tap from then on.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, height: 1.45, color: t.textFaint),
        ),
        const SizedBox(height: 20),
        const AppBanner(),
      ],
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.preset});

  final ConversionPreset preset;

  Future<void> _rename(BuildContext context) async {
    final store = context.read<PresetStore>();
    final name = await askPresetName(
      context,
      title: 'Rename preset',
      suggested: preset.name,
      existing: [
        for (final p in store.presets)
          if (p.id != preset.id) p.name,
      ],
    );
    if (name == null) return;
    await store.rename(preset.id, name);
  }

  Future<void> _delete(BuildContext context) async {
    final store = context.read<PresetStore>();
    final messenger = ScaffoldMessenger.of(context);
    await store.remove(preset.id);
    messenger.showSnackBar(
      SnackBar(content: Text('Removed "${preset.name}"')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          Icon(
            preset.isOptimize ? Icons.compress_rounded : Icons.swap_horiz_rounded,
            size: 18,
            color: t.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preset.summary,
                  maxLines: 2,
                  style: TextStyle(fontSize: 12, height: 1.3, color: t.textFaint),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Preset actions',
            icon: Icon(Icons.more_horiz_rounded, size: 20, color: t.textFaint),
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  _rename(context);
                case 'delete':
                  _delete(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
