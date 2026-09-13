import 'dart:io';

import 'package:flutter/material.dart';

import '../../engine/format.dart';
import '../preview/preview_service.dart';
import '../theme/app_theme.dart';
import 'brand.dart';

/// Shows what a file actually looks like, falling back to a format badge when
/// nothing can be rendered.
///
/// Used at two sizes: a small square in lists, and a larger panel on the
/// convert and result screens.
class FilePreview extends StatefulWidget {
  const FilePreview({
    super.key,
    required this.path,
    this.format,
    this.size = 46,
    this.expanded = false,
    this.filled = false,
  });

  final String path;
  final FileFormat? format;

  /// Edge length when shown as a thumbnail.
  final double size;

  /// Render as a large panel with text and listing previews, rather than a
  /// thumbnail square.
  final bool expanded;

  /// Passed through to the fallback badge.
  final bool filled;

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<FilePreview> {
  late Future<Preview> _future;

  @override
  void initState() {
    super.initState();
    _future = PreviewService.instance.previewOf(widget.path, format: widget.format);
  }

  @override
  void didUpdateWidget(covariant FilePreview old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _future = PreviewService.instance.previewOf(widget.path, format: widget.format);
    }
  }

  String get _ext =>
      widget.format?.ext ?? widget.path.split('.').last.toLowerCase();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Preview>(
      future: _future,
      builder: (context, snap) {
        final preview = snap.data;
        // While the thumbnail renders, hold the badge rather than a spinner —
        // a flash of loading state in a scrolling list is worse than nothing.
        if (preview == null || preview is NoPreview) {
          return widget.expanded ? _expandedFallback(context) : _badge();
        }
        return widget.expanded ? _expanded(context, preview) : _thumb(preview);
      },
    );
  }

  Widget _badge() => FormatBadge(_ext, size: widget.size, filled: widget.filled);

  Widget _thumb(Preview preview) {
    final t = context.tokens;
    if (preview is! ImagePreview) return _badge();

    return Container(
      width: widget.size,
      height: widget.size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.size * 0.28),
        border: Border.all(color: t.border),
        color: t.surfaceRaised,
      ),
      child: Image.file(
        preview.file,
        fit: BoxFit.cover,
        // The cache is sized to what is actually drawn, so a list of 4000px
        // photos does not decode 4000px bitmaps.
        cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context)).round(),
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _badge(),
      ),
    );
  }

  Widget _expandedFallback(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 150,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FormatBadge(_ext, size: 52),
          const SizedBox(height: 10),
          Text(
            'No preview for this format',
            style: TextStyle(fontSize: 12.5, color: t.textFaint),
          ),
        ],
      ),
    );
  }

  Widget _expanded(BuildContext context, Preview preview) {
    final t = context.tokens;

    return switch (preview) {
      ImagePreview(:final file) => ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 260, minHeight: 120),
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Image.file(
              file,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _expandedFallback(context),
            ),
          ),
        ),
      TextPreview(:final text, :final truncated) => Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            color: t.surface,
          ),
          child: SingleChildScrollView(
            child: Text(
              truncated ? '$text\n…' : text,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: t.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ListingPreview(:final entries, :final total) => Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            color: t.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total item${total == 1 ? '' : 's'} inside',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            e,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: t.textFaint),
                          ),
                        ),
                      if (total > entries.length)
                        Text(
                          '+ ${total - entries.length} more',
                          style: TextStyle(fontSize: 12, color: t.textFaint),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      NoPreview() => _expandedFallback(context),
    };
  }
}

/// Full-screen viewer for a converted file, so an exotic output is still
/// something you can look at without another app installed.
class PreviewSheet extends StatelessWidget {
  const PreviewSheet({super.key, required this.path, this.format});

  final String path;
  final FileFormat? format;

  static Future<void> show(BuildContext context, String path, {FileFormat? format}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PreviewSheet(path: path, format: format),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = path.split(Platform.pathSeparator).last;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            FilePreview(path: path, format: format, expanded: true),
            const SizedBox(height: 10),
            Text(
              'Rendered on this device.',
              style: TextStyle(fontSize: 12, color: t.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}
