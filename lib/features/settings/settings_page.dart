import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/ads/ads.dart';
import '../../core/data/history_store.dart';
import '../../core/data/settings_store.dart';
import '../../core/preview/preview_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../engine/engine.dart';
import '../../engine/job.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _cacheBytes = 0;

  @override
  void initState() {
    super.initState();
    _measureCache();
  }

  Future<void> _measureCache() async {
    final dir = await ConversionEngine.tempDir();
    var sum = 0;
    if (await dir.exists()) {
      await for (final e in dir.list(recursive: true)) {
        if (e is File) sum += await e.length();
      }
    }
    if (mounted) setState(() => _cacheBytes = sum);
  }

  Future<void> _clearCache() async {
    await PreviewService.instance.clear();
    final dir = await ConversionEngine.tempDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    await _measureCache();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Working files cleared')),
      );
    }
  }

  Future<void> _pickOutputDir(SettingsStore settings) async {
    final path = await FilePicker.getDirectoryPath();
    if (path != null) await settings.setOutputDir(path);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final t = context.tokens;

    return Column(
      children: [
        const AppBanner(),
        const PageHeader(title: 'Settings'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              const SectionTitle('Appearance'),
              Panel(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  children: [
                    _ThemeRow(settings: settings),
                    Divider(color: t.border, height: 20, indent: 12, endIndent: 12),
                    SwitchListTile.adaptive(
                      value: settings.starfieldEnabled,
                      onChanged: settings.setStarfieldEnabled,
                      title: const Text('Falling stars'),
                      subtitle: Text(
                        'The animated background. Turn it off to save battery.',
                        style: TextStyle(fontSize: 12.5, color: t.textFaint),
                      ),
                    ),
                  ],
                ),
              ),

              const SectionTitle('Conversion'),
              Panel(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Default image quality',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          '${settings.imageQuality}',
                          style: TextStyle(fontWeight: FontWeight.w700, color: t.textFaint),
                        ),
                      ],
                    ),
                    Text(
                      'Used for JPG, WebP and AVIF unless you change it per file.',
                      style: TextStyle(fontSize: 12.5, color: t.textFaint),
                    ),
                    Slider(
                      value: settings.imageQuality.toDouble(),
                      min: 10,
                      max: 100,
                      divisions: 18,
                      onChanged: (v) => settings.setImageQuality(v.round()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Panel(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: const Text('Output folder'),
                      subtitle: Text(
                        settings.outputDir ?? 'App folder in storage (default)',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: t.textFaint),
                      ),
                      trailing: settings.outputDir == null
                          ? const Icon(Icons.chevron_right_rounded)
                          : IconButton(
                              icon: const Icon(Icons.restart_alt_rounded),
                              tooltip: 'Reset to default',
                              onPressed: () => settings.setOutputDir(null),
                            ),
                      onTap: () => _pickOutputDir(settings),
                    ),
                    Divider(color: t.border, height: 4, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.cleaning_services_outlined),
                      title: const Text('Clear working files'),
                      subtitle: Text(
                        _cacheBytes == 0 ? 'Nothing to clear' : humanBytes(_cacheBytes),
                        style: TextStyle(fontSize: 12.5, color: t.textFaint),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _cacheBytes == 0 ? null : _clearCache,
                    ),
                  ],
                ),
              ),

              const SectionTitle('Privacy'),
              Panel(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 20, color: t.textSecondary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Nothing leaves this device',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(
                            'Every conversion runs on your phone. This app has no server, no account and no upload step. '
                            'Your history and settings are stored in app-private storage only.',
                            style: TextStyle(fontSize: 13, height: 1.5, color: t.textFaint),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Panel(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Clear conversion history'),
                  subtitle: Text(
                    'Removes the list. Converted files are kept.',
                    style: TextStyle(fontSize: 12.5, color: t.textFaint),
                  ),
                  onTap: () async {
                    await HistoryStore.instance.clear();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('History cleared')),
                      );
                    }
                  },
                ),
              ),

              Panel(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.bookmark_outline_rounded),
                  title: const Text('Presets'),
                  subtitle: Text(
                    'Recipes you have saved: a format plus its settings, ready in one tap.',
                    style: TextStyle(fontSize: 12.5, color: t.textFaint),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/presets'),
                ),
              ),

              const SectionTitle('Support'),
              Panel(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Send a report'),
                  subtitle: Text(
                    'Sends a failure with this device, this build and the engine\'s own output.',
                    style: TextStyle(fontSize: 12.5, color: t.textFaint),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/feedback'),
                ),
              ),
              const SizedBox(height: 10),
              const SupportCard(),
              const SizedBox(height: 10),
              Panel(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('About & licences'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/about'),
                ),
              ),
              const SizedBox(height: 10),
              const AppBanner(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.settings});
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const modes = [
      (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
      (ThemeMode.light, 'Light', Icons.light_mode_rounded),
      (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (mode, label, icon) in modes)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => settings.setThemeMode(mode),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: settings.themeMode == mode ? t.accent : Colors.transparent,
                          border: Border.all(
                            color: settings.themeMode == mode ? t.accent : t.border,
                          ),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              icon,
                              size: 19,
                              color: settings.themeMode == mode ? t.onAccent : t.textSecondary,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: settings.themeMode == mode ? t.onAccent : t.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
