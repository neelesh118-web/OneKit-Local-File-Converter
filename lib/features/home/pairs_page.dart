import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../core/ads/ads.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/starfield.dart';
import '../../engine/engine.dart';
import '../../engine/format.dart';
import '../../engine/registry.dart';
import '../convert/convert_page.dart';

/// The full conversion catalogue, searchable. Backed by a lazily built,
/// virtualised list so all 6,000+ entries scroll without a hitch.
class PairsPage extends StatefulWidget {
  const PairsPage({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  State<PairsPage> createState() => _PairsPageState();
}

class _PairsPageState extends State<PairsPage> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery ?? '');
  Family? _family;
  late List<ConversionPair> _results;
  Timer? _debounce;

  /// Compiled once. It used to be rebuilt on every keystroke.
  static final _separator = RegExp(r'\s*(to|->|→|>)\s*');

  /// Only pairs an engine actually claims are listed, so the catalogue can
  /// never advertise something the app would then refuse to run.
  static final List<ConversionPair> _runnable = FormatRegistry.pairs
      .where((p) => ConversionEngine.instance.canConvert(p.from, p.to))
      .toList();

  @override
  void initState() {
    super.initState();
    _family = _familyFromQuery(widget.initialQuery);
    if (_family != null) _controller.clear();
    _results = _compute();
  }

  static Family? _familyFromQuery(String? q) {
    if (q == null) return null;
    final lower = q.toLowerCase();
    for (final f in Family.values) {
      if (f.label.toLowerCase() == lower) return f;
    }
    return null;
  }

  List<ConversionPair> _compute() {
    final q = _controller.text.toLowerCase().trim();
    // "png to jpg", "png>jpg" and "png jpg" all normalise to the same query.
    final normalized = q.replaceAll(_separator, '>');

    return _runnable.where((p) {
      if (_family != null && p.from.family != _family && p.to.family != _family) return false;
      if (q.isEmpty) return true;
      if (normalized.contains('>')) return p.id.contains(normalized);
      // One pass over a prebuilt lowercase key, instead of lowercasing both
      // format names for all ~5,900 pairs on every keystroke.
      return p.searchKey.contains(q);
    }).toList();
  }

  void _refresh() => setState(() => _results = _compute());

  /// Typing outruns a 5,900-item scan, so filter on a short pause instead of
  /// on every character.
  void _refreshDebounced() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(ConversionPair pair) async {
    // Unfiltered on purpose — see the note in home_page.dart.
    final file = await FilePicker.pickFile();
    final path = file?.path;
    if (path == null || !mounted) return;

    final picked = FormatRegistry.byExt(p.extension(path));
    if (picked?.ext != pair.from.ext) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('That is a ${picked?.upper ?? 'unknown'} file. '
              'This conversion starts from ${pair.from.upper}.'),
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
    return Scaffold(
      backgroundColor: t.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Starfield(density: 0.7),
          SafeArea(
            child: Column(
              children: [
                PageHeader(
                  title: 'All conversions',
                  subtitle: '${_results.length} of ${_runnable.length}',
                  onBack: () => context.pop(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: TextField(
                    controller: _controller,
                    onChanged: (_) => _refreshDebounced(),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Try "heic to jpg" or "mp4"',
                      prefixIcon: Icon(Icons.search_rounded, size: 20, color: t.textFaint),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _controller.clear();
                                _refresh();
                              },
                            ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _familyChip(null, 'All'),
                      for (final f in Family.values)
                        if (FormatRegistry.family(f).isNotEmpty) _familyChip(f, f.label),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _results.isEmpty
                      ? EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No match',
                          message: 'Nothing in the catalogue matches that search.',
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            4,
                            20,
                            MediaQuery.viewPaddingOf(context).bottom + 24,
                          ),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemCount: _results.length + 1,
                          itemBuilder: (context, i) => i < _results.length
                              ? _PairRow(
                                  pair: _results[i],
                                  onTap: () => _run(_results[i]),
                                )
                              : const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: AppBanner(),
                                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _familyChip(Family? f, String label) {
    final t = context.tokens;
    final selected = _family == f;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () {
          _family = f;
          _refresh();
        },
        borderRadius: BorderRadius.circular(100),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: selected ? t.accent : Colors.transparent,
            border: Border.all(color: selected ? t.accent : t.border),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? t.onAccent : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PairRow extends StatelessWidget {
  const _PairRow({required this.pair, required this.onTap});
  final ConversionPair pair;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 128,
              child: Row(
                children: [
                  Text(
                    pair.from.upper,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: t.textPrimary),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded, size: 13, color: t.textFaint),
                  ),
                  Flexible(
                    child: Text(
                      pair.to.upper,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: t.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                pair.to.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: t.textFaint),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: t.textFaint),
          ],
        ),
      ),
    );
  }
}
