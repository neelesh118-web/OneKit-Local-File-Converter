import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/ads/ads.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/file_preview.dart';
import '../../engine/engine.dart';
import '../../engine/job.dart';
import '../../engine/registry.dart';
import '../convert/convert_page.dart';

enum _Sort { newest, oldest, largest, name }

/// A file manager over OneKit's output folder: browse, sort, multi-select,
/// share, delete, and feed anything straight back into another conversion.
class FilesPage extends StatefulWidget {
  const FilesPage({super.key});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

/// A file plus its stat, read once at load time. Sorting and the size total
/// used to call statSync from inside the comparator, which meant thousands of
/// syscalls on every rebuild.
class _Entry {
  const _Entry(this.file, this.size, this.modified);
  final File file;
  final int size;
  final DateTime modified;

  String get name => p.basename(file.path);
}

class _FilesPageState extends State<FilesPage> {
  List<_Entry> _files = const [];
  final Set<String> _selected = {};
  _Sort _sort = _Sort.newest;
  String _query = '';
  bool _loading = true;
  Directory? _dir;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = await ConversionEngine.outputDir();
    await dir.create(recursive: true);

    final entries = <_Entry>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      try {
        final stat = await e.stat();
        entries.add(_Entry(e, stat.size, stat.modified));
      } on FileSystemException {
        // A file removed between listing and stat is simply not shown.
        continue;
      }
    }

    if (!mounted) return;
    setState(() {
      _dir = dir;
      _files = entries;
      _totalBytes = entries.fold(0, (sum, e) => sum + e.size);
      _loading = false;
      _selected.removeWhere((path) => !entries.any((e) => e.file.path == path));
    });
  }

  int _totalBytes = 0;

  List<_Entry> get _visible {
    final q = _query.toLowerCase();
    final list = _files.where((e) => q.isEmpty || e.name.toLowerCase().contains(q)).toList();

    list.sort((a, b) => switch (_sort) {
          _Sort.newest => b.modified.compareTo(a.modified),
          _Sort.oldest => a.modified.compareTo(b.modified),
          _Sort.largest => b.size.compareTo(a.size),
          _Sort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        });
    return list;
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count file${count == 1 ? '' : 's'}?'),
        content: const Text('This permanently removes them from your device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;

    for (final path in _selected) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    _selected.clear();
    await _load();
  }

  bool get _allSelectedArePdf =>
      _selected.isNotEmpty &&
      _selected.every((path) => p.extension(path).toLowerCase() == '.pdf');

  Future<void> _shareSelected() async {
    if (_selected.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(files: [for (final path in _selected) XFile(path)]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final files = _visible;
    final selecting = _selected.isNotEmpty;

    return Column(
      children: [
        const AppBanner(),
        PageHeader(
          title: selecting ? '${_selected.length} selected' : 'Files',
          subtitle: selecting
              ? null
              : _loading
                  ? null
                  : '${_files.length} file${_files.length == 1 ? '' : 's'} · ${humanBytes(_totalBytes)}',
          onBack: selecting ? () => setState(_selected.clear) : null,
          actions: [
            if (selecting) ...[
              // Several PDFs selected is the natural way to ask for a merge.
              if (_allSelectedArePdf)
                IconButton(
                  tooltip: 'PDF tools',
                  onPressed: () => context.push('/pdf-tools', extra: _selected.toList()),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                ),
              IconButton(onPressed: _shareSelected, icon: const Icon(Icons.ios_share_rounded)),
              IconButton(onPressed: _deleteSelected, icon: const Icon(Icons.delete_outline_rounded)),
            ] else
              PopupMenuButton<_Sort>(
                icon: const Icon(Icons.sort_rounded),
                tooltip: 'Sort',
                onSelected: (s) => setState(() => _sort = s),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _Sort.newest, child: Text('Newest first')),
                  PopupMenuItem(value: _Sort.oldest, child: Text('Oldest first')),
                  PopupMenuItem(value: _Sort.largest, child: Text('Largest first')),
                  PopupMenuItem(value: _Sort.name, child: Text('Name')),
                ],
              ),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      if (_files.isNotEmpty) ...[
                        TextField(
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            hintText: 'Search files',
                            prefixIcon: Icon(Icons.search_rounded, size: 20, color: t.textFaint),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (files.isEmpty)
                        EmptyState(
                          icon: Icons.folder_outlined,
                          title: _query.isEmpty ? 'No converted files yet' : 'Nothing matches',
                          message: _query.isEmpty
                              ? 'Files you convert are saved here.\nTap one to open, share or convert it again.'
                              : 'Try a different search.',
                          action: _query.isEmpty
                              ? FilledButton(
                                  onPressed: () => context.go('/'),
                                  child: const Text('Convert a file'),
                                )
                              : null,
                        )
                      else
                        for (final e in files)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _FileRow(
                              entry: e,
                              selected: _selected.contains(e.file.path),
                              selecting: selecting,
                              onTap: () {
                                if (selecting) {
                                  setState(() => _selected.contains(e.file.path)
                                      ? _selected.remove(e.file.path)
                                      : _selected.add(e.file.path));
                                } else {
                                  _openSheet(e.file);
                                }
                              },
                              onLongPress: () => setState(() => _selected.add(e.file.path)),
                            ),
                          ),
                      const SizedBox(height: 12),
                      if (_dir != null)
                        Text(
                          'Saved in ${_dir!.path}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: t.textFaint),
                        ),
                      const SizedBox(height: 12),
                      const AppBanner(),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _openSheet(File file) async {
    final format = FormatRegistry.byExt(p.extension(file.path));
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                p.basename(file.path),
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Preview here'),
              onTap: () {
                Navigator.pop(ctx);
                PreviewSheet.show(context, file.path, format: format);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Open in another app'),
              onTap: () {
                Navigator.pop(ctx);
                OpenFilex.open(file.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(ctx);
                SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
              },
            ),
            if (format?.ext == 'pdf')
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded),
                title: const Text('PDF tools'),
                subtitle: Text(
                  'Merge, split, rotate or compress',
                  style: TextStyle(fontSize: 12.5, color: context.tokens.textFaint),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/pdf-tools', extra: [file.path]);
                },
              ),
            if (format != null)
              ListTile(
                leading: const Icon(Icons.autorenew_rounded),
                title: const Text('Convert again'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/convert', extra: ConvertArgs(paths: [file.path]));
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(ctx);
                await file.delete();
                await _load();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.entry,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  final _Entry entry;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? t.surface : Colors.transparent,
          border: Border.all(color: selected ? t.accent : t.border, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
        ),
        child: Row(
          children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 22,
                  color: selected ? t.accent : t.textFaint,
                ),
              ),
            FilePreview(
              path: entry.file.path,
              size: 40,
            ),
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
                    '${humanBytes(entry.size)} · ${_when(entry.modified)}',
                    style: TextStyle(fontSize: 11.5, color: t.textFaint),
                  ),
                ],
              ),
            ),
            if (!selecting) Icon(Icons.chevron_right_rounded, size: 20, color: t.textFaint),
          ],
        ),
      ),
    );
  }

  static String _when(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}
