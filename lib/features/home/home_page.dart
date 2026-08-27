import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../core/ads/ads.dart';
import '../../core/data/history_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pulse.dart';
import '../../engine/format.dart';
import '../../engine/registry.dart';
import '../batch/batch_page.dart';
import '../convert/convert_page.dart';

/// The landing tab: pick a file, or jump straight to a conversion you already
/// know you want.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> _favourites = const [];

  /// Curated starting set, replaced by the user's own most-used pairs as soon
  /// as they have any history.
  static const _defaultPairs = [
    'heic>jpg',
    'png>jpg',
    'jpg>pdf',
    'webp>png',
    'mp4>mp3',
    'pdf>png',
    'mov>mp4',
    'wav>mp3',
    'docx>pdf',
    'csv>json',
    'srt>vtt',
    'zip>tar',
  ];

  @override
  void initState() {
    super.initState();
    _loadFavourites();
    HistoryStore.instance.addListener(_loadFavourites);
  }

  @override
  void dispose() {
    HistoryStore.instance.removeListener(_loadFavourites);
    super.dispose();
  }

  Future<void> _loadFavourites() async {
    final ids = await HistoryStore.instance.favouritePairIds();
    if (mounted) setState(() => _favourites = ids);
  }

  /// Pair lookup built once for the whole app, not per build. This used to
  /// allocate a ~5,900-entry map every time HomePage rebuilt.
  static final Map<String, ConversionPair> _byId = {
    for (final p in FormatRegistry.pairs) p.id: p,
  };

  List<ConversionPair> get _quickPairs {
    final ids = <String>{..._favourites, ..._defaultPairs}.take(12);
    return [
      for (final id in ids)
        if (_byId[id] != null) _byId[id]!,
    ];
  }

  Future<void> _pickSingle() async {
    final file = await FilePicker.pickFile();
    final path = file?.path;
    if (path == null || !mounted) return;
    context.push('/convert', extra: ConvertArgs(paths: [path], displayNames: [file!.name]));
  }

  Future<void> _pickMultiple() async {
    final files = await FilePicker.pickFiles();
    final paths = [
      for (final f in files)
        if (f.path != null) f.path!,
    ];
    if (paths.isEmpty || !mounted) return;
    BatchPage.seed(paths);
    context.go('/batch');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        _header(),
        const SizedBox(height: 6),
        _heroCard(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickMultiple,
                icon: const Icon(Icons.library_add_outlined, size: 19),
                label: const Text('Multiple'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push('/pairs'),
                icon: const Icon(Icons.grid_view_rounded, size: 19),
                label: const Text('Browse'),
              ),
            ),
          ],
        ),
        SectionTitle(
          _favourites.isEmpty ? 'Popular conversions' : 'Your most used',
          trailing: TextButton(
            onPressed: () => context.push('/pairs'),
            child: const Text('See all'),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final pair in _quickPairs) _PairChip(pair: pair)],
        ),
        const SectionTitle('Browse by type'),
        _familyGrid(),
        const SizedBox(height: 18),
        const OneKitBanner(),
        const SizedBox(height: 10),
        const SupportCard(),
        const SizedBox(height: 14),
        Center(
          child: Text(
            '${FormatRegistry.pairCount} conversions · ${FormatRegistry.all.length} formats · 0 uploads',
            style: TextStyle(fontSize: 11.5, color: t.textFaint, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
      child: Row(
        children: [
          const OneKitMark(size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'One', style: TextStyle(fontWeight: FontWeight.w800, color: t.textPrimary)),
                      TextSpan(text: 'Kit', style: TextStyle(fontWeight: FontWeight.w300, color: t.textPrimary)),
                    ],
                  ),
                  style: const TextStyle(fontSize: 22, letterSpacing: -0.8, height: 1.1),
                ),
                Text(
                  'Local file converter',
                  style: TextStyle(fontSize: 11.5, color: t.textFaint, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => context.push('/about'),
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'About',
          ),
        ],
      ),
    );
  }

  Widget _heroCard() {
    final t = context.tokens;
    return Panel(
      onTap: _pickSingle,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      child: Column(
        children: [
          PulseHalo(
            size: 130,
            child: Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.add_rounded, size: 36, color: t.onAccent),
            ),
          ),
          const SizedBox(height: 18),
          Text('Select a file', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Pick anything on your device. OneKit works out\nwhat it can become.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.45, color: t.textFaint),
          ),
        ],
      ),
    );
  }

  Widget _familyGrid() {
    const families = [
      Family.image,
      Family.audio,
      Family.video,
      Family.document,
      Family.data,
      Family.archive,
      Family.subtitle,
      Family.ebook,
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.5,
      children: [
        for (final f in families) _FamilyTile(family: f),
      ],
    );
  }
}

class _PairChip extends StatelessWidget {
  const _PairChip({required this.pair});
  final ConversionPair pair;

  Future<void> _run(BuildContext context) async {
    // The picker is deliberately unfiltered: Android maps extensions to MIME
    // types, and the long tail (QOI, FARBFELD, DFXP, ...) has no mapping, so a
    // filtered picker would show a screen with nothing selectable. Validating
    // afterwards is both more reliable and easier to explain when it is wrong.
    final file = await FilePicker.pickFile();
    final path = file?.path;
    if (path == null || !context.mounted) return;

    final picked = FormatRegistry.byExt(p.extension(path));
    if (picked?.ext != pair.from.ext) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('That is a ${picked?.upper ?? 'unknown'} file. '
              'This shortcut converts ${pair.from.upper}.'),
        ),
      );
      return;
    }

    context.push(
      '/convert',
      extra: ConvertArgs(paths: [path], target: pair.to, displayNames: [file!.name]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: () => _run(context),
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
          color: t.surface.withValues(alpha: 0.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              pair.from.upper,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: t.textPrimary),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Icon(Icons.arrow_forward_rounded, size: 13, color: t.textFaint),
            ),
            Text(
              pair.to.upper,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: t.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyTile extends StatelessWidget {
  const _FamilyTile({required this.family});
  final Family family;

  static const _icons = {
    Family.image: Icons.image_outlined,
    Family.audio: Icons.graphic_eq_rounded,
    Family.video: Icons.movie_outlined,
    Family.document: Icons.description_outlined,
    Family.data: Icons.data_object_rounded,
    Family.archive: Icons.folder_zip_outlined,
    Family.subtitle: Icons.subtitles_outlined,
    Family.ebook: Icons.menu_book_outlined,
    Family.vector: Icons.polyline_outlined,
    Family.font: Icons.text_fields_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final count = FormatRegistry.family(family).length;
    return InkWell(
      onTap: () => context.push('/pairs?q=${family.label.toLowerCase()}'),
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
        ),
        child: Row(
          children: [
            Icon(_icons[family], size: 20, color: t.textSecondary),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    family.label,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary),
                  ),
                  Text('$count formats', style: TextStyle(fontSize: 11, color: t.textFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
