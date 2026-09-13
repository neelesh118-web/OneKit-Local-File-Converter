import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../engine/format.dart';

/// Grid of possible target formats, grouped by family and filterable.
///
/// Same-family targets come first because that is what people reach for; the
/// cross-family routes (MP4 to MP3, PDF to PNG) follow underneath.
class TargetPicker extends StatefulWidget {
  const TargetPicker({
    super.key,
    required this.source,
    required this.targets,
    required this.selected,
    required this.onSelected,
  });

  final FileFormat source;
  final List<FileFormat> targets;
  final FileFormat? selected;
  final ValueChanged<FileFormat> onSelected;

  @override
  State<TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<TargetPicker> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Popularity ranking: formats users convert to most often.
  /// Lower number = more popular. Unlisted formats get 999.
  static const _popularity = {
    'jpg': 1, 'jpeg': 2, 'png': 3, 'pdf': 4, 'mp3': 5,
    'mp4': 6, 'webp': 7, 'gif': 8, 'txt': 9, 'html': 10,
    'docx': 11, 'csv': 12, 'json': 13, 'wav': 14, 'flac': 15,
    'zip': 16, 'webm': 17, 'tiff': 18, 'bmp': 19, 'svg': 20,
    'mkv': 21, 'avi': 22, 'mov': 23, 'aac': 24, 'ogg': 25,
    'md': 26, 'xml': 27, 'yaml': 28, 'rtf': 29, 'epub': 30,
  };

  List<MapEntry<Family, List<FileFormat>>> get _groups {
    final q = _query.toLowerCase().trim();
    final filtered = q.isEmpty
        ? widget.targets
        : widget.targets
            .where((f) => f.ext.contains(q) || f.name.toLowerCase().contains(q))
            .toList();

    final byFamily = <Family, List<FileFormat>>{};
    for (final f in filtered) {
      byFamily.putIfAbsent(f.family, () => []).add(f);
    }

    // Sort each family's formats by popularity.
    for (final entry in byFamily.entries) {
      entry.value.sort((a, b) {
        final pa = _popularity[a.ext] ?? 999;
        final pb = _popularity[b.ext] ?? 999;
        return pa.compareTo(pb);
      });
    }

    final ordered = byFamily.entries.toList()
      ..sort((a, b) {
        // The source's own family always sits at the top.
        if (a.key == widget.source.family) return -1;
        if (b.key == widget.source.family) return 1;
        return a.key.label.compareTo(b.key.label);
      });
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final groups = _groups;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: TextField(
            controller: _controller,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search formats',
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: t.textFaint),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Text(
                    'No format matches "$_query"',
                    style: TextStyle(color: t.textFaint, fontSize: 14),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: groups.length,
                  itemBuilder: (context, i) {
                    final group = groups[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
                          child: Row(
                            children: [
                              Text(
                                group.key.label.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  letterSpacing: 1.6,
                                  fontWeight: FontWeight.w700,
                                  color: t.textFaint,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${group.value.length}',
                                style: TextStyle(fontSize: 11.5, color: t.textFaint),
                              ),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final f in group.value)
                              _TargetChip(
                                format: f,
                                selected: widget.selected?.ext == f.ext,
                                onTap: () => widget.onSelected(f),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({required this.format, required this.selected, required this.onTap});

  final FileFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: '${format.upper}, ${format.name}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? t.accent : t.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
            border: Border.all(color: selected ? t.accent : t.border, width: selected ? 1.6 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                format.upper,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: selected ? t.onAccent : t.textPrimary,
                ),
              ),
              if (format.lossy) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.compress_rounded,
                  size: 13,
                  color: selected ? t.onAccent.withValues(alpha: 0.7) : t.textFaint,
                ),
              ],
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_rounded, size: 15, color: t.onAccent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
