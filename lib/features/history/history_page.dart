import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ads/ads.dart';
import '../../core/data/history_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../engine/job.dart';
import '../../engine/registry.dart';

/// Every conversion this device has run, with the numbers that make the app
/// feel accountable: how long it took and how much space it saved.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _search = TextEditingController();
  List<HistoryEntry> _entries = const [];
  ({int total, int succeeded, int bytesSaved})? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    HistoryStore.instance.addListener(_load);
  }

  @override
  void dispose() {
    HistoryStore.instance.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await HistoryStore.instance.recent(filter: _search.text);
    final stats = await HistoryStore.instance.stats();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _stats = stats;
      _loading = false;
    });
  }

  Future<void> _confirmClear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This removes the list only. Your converted files stay where they are.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (yes == true) await HistoryStore.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;

    return Column(
      children: [
        PageHeader(
          title: 'History',
          subtitle: stats == null ? null : '${stats.total} conversions on this device',
          actions: [
            if (_entries.isNotEmpty)
              IconButton(
                onPressed: _confirmClear,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Clear history',
              ),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    if (stats != null && stats.total > 0) ...[
                      Row(
                        children: [
                          StatPill(
                            label: 'Converted',
                            value: '${stats.succeeded}',
                            icon: Icons.check_rounded,
                          ),
                          const SizedBox(width: 10),
                          StatPill(
                            label: 'Space saved',
                            value: humanBytes(stats.bytesSaved),
                            icon: Icons.compress_rounded,
                          ),
                          const SizedBox(width: 10),
                          StatPill(
                            label: 'Uploaded',
                            value: '0 B',
                            icon: Icons.cloud_off_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _search,
                        onChanged: (_) => _load(),
                        decoration: InputDecoration(
                          hintText: 'Search history',
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: context.tokens.textFaint,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_entries.isEmpty)
                      EmptyState(
                        icon: Icons.history_rounded,
                        title: _search.text.isEmpty ? 'No conversions yet' : 'Nothing matches',
                        message: _search.text.isEmpty
                            ? 'Everything you convert shows up here, stored\nonly on this device.'
                            : 'Try a different search.',
                        action: _search.text.isEmpty
                            ? FilledButton(
                                onPressed: () => context.go('/'),
                                child: const Text('Convert a file'),
                              )
                            : null,
                      )
                    else
                      for (final e in _entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _EntryRow(entry: e, onChanged: _load),
                        ),
                    const SizedBox(height: 12),
                    const OneKitBanner(),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onChanged});
  final HistoryEntry entry;
  final VoidCallback onChanged;

  Future<void> _actions(BuildContext context) async {
    final exists = entry.outputPath != null && File(entry.outputPath!).existsSync();
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(entry.name, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (exists) ...[
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Open'),
                onTap: () {
                  Navigator.pop(ctx);
                  OpenFilex.open(entry.outputPath!);
                },
              ),
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(ctx);
                  SharePlus.instance.share(ShareParams(files: [XFile(entry.outputPath!)]));
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.replay_rounded),
              title: Text('Convert another ${entry.fromExt.toUpperCase()}'),
              onTap: () {
                Navigator.pop(ctx);
                final target = FormatRegistry.byExt(entry.toExt);
                if (target != null) {
                  context.push('/pairs?q=${entry.fromExt}>${entry.toExt}');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Remove from history'),
              onTap: () async {
                Navigator.pop(ctx);
                await HistoryStore.instance.delete(entry.id);
                onChanged();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ok = entry.succeeded;

    return InkWell(
      onTap: () => _actions(context),
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
        ),
        child: Row(
          children: [
            FormatBadge(entry.toExt, size: 40, filled: ok),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: t.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    ok
                        ? '${entry.pairLabel} · ${humanBytes(entry.outputBytes)} · ${_ago(entry.createdAt)}'
                        : '${entry.pairLabel} · ${entry.error ?? 'Failed'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: t.textFaint),
                  ),
                ],
              ),
            ),
            Icon(Icons.more_horiz_rounded, size: 20, color: t.textFaint),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${when.day}/${when.month}/${when.year}';
  }
}
