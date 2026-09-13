import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ads/ads.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/starfield.dart';
import '../../engine/engine.dart';
import '../../engine/format.dart';
import '../../engine/registry.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Starfield(density: 0.9, speed: 0.8),
          SafeArea(
            child: Column(
              children: [
                PageHeader(title: 'About', onBack: () => context.pop()),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      MediaQuery.viewPaddingOf(context).bottom + 28,
                    ),
                    children: [
                      const SizedBox(height: 12),
                      const Center(child: AppLockup(markSize: 76)),
                      const SizedBox(height: 10),
                      const AppBanner(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          StatPill(
                            label: 'Conversions',
                            value: '${FormatRegistry.pairCount}',
                            icon: Icons.swap_horiz_rounded,
                          ),
                          const SizedBox(width: 10),
                          StatPill(
                            label: 'Formats',
                            value: '${FormatRegistry.all.length}',
                            icon: Icons.category_outlined,
                          ),
                          const SizedBox(width: 10),
                          const StatPill(
                            label: 'Servers used',
                            value: '0',
                            icon: Icons.cloud_off_rounded,
                          ),
                        ],
                      ),
                      const SectionTitle('How it works'),
                      Panel(
                        child: Text(
                          'This app converts files entirely on your device. There is no upload, no queue on '
                          'someone else’s server, and no account. That means your files stay private, it '
                          'works with no signal, and there are no size limits beyond your own storage.',
                          style: TextStyle(fontSize: 14, height: 1.55, color: t.textSecondary),
                        ),
                      ),
                      const SectionTitle('What it covers'),
                      const _PairBreakdown(),
                      const SizedBox(height: 10),
                      for (final f in Family.values)
                        if (FormatRegistry.family(f).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _FamilyLine(family: f),
                          ),
                      const SectionTitle('Engines'),
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final c in ConversionEngine.converters)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: t.textFaint,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      c.name,
                                      style: TextStyle(fontSize: 13.5, color: t.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SectionTitle('Support'),
                      const SupportCard(),
                      const SizedBox(height: 14),
                      Panel(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.article_outlined),
                          title: const Text('Open source licences'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => showLicensePage(
                            context: context,
                            applicationName: '100% Local File Converter',
                            applicationVersion: '1.0.0',
                            applicationLegalese: 'Local File Converter',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const AppBanner(),
                      const SizedBox(height: 22),
                      Center(
                        child: Text(
                          '100% Local File Converter 1.0.0',
                          style: TextStyle(fontSize: 12, color: t.textFaint),
                        ),
                      ),
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
}

class _FamilyLine extends StatelessWidget {
  const _FamilyLine({required this.family});
  final Family family;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final formats = FormatRegistry.family(family);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                family.label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary),
              ),
              const Spacer(),
              Text(
                '${formats.length}',
                style: TextStyle(fontSize: 12.5, color: t.textFaint, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            formats.map((f) => f.upper).join('  ·  '),
            style: TextStyle(fontSize: 11.5, height: 1.5, color: t.textFaint),
          ),
        ],
      ),
    );
  }
}

/// Same-family vs cross-family split of the conversion catalogue, computed
/// from the registry so it can never disagree with what the engines do.
class _PairBreakdown extends StatelessWidget {
  const _PairBreakdown();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final total = FormatRegistry.pairCount;
    final same = FormatRegistry.sameFamilyPairCount;
    final cross = FormatRegistry.crossFamilyPairTotal;
    final routes = FormatRegistry.crossFamilyPairCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (same > 0) Expanded(flex: same, child: ColoredBox(color: t.textPrimary)),
                  if (cross > 0) Expanded(flex: cross, child: ColoredBox(color: t.textFaint)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _LegendRow(
            color: t.textPrimary,
            value: same,
            total: total,
            label: 'Same family',
            detail: 'PNG → JPG, MKV → MP4',
          ),
          const SizedBox(height: 8),
          _LegendRow(
            color: t.textFaint,
            value: cross,
            total: total,
            label: 'Cross family',
            detail: 'MP4 → MP3, PDF → PNG',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final e in routes)
                Text(
                  '→ ${e.key.label} ${e.value}',
                  style: TextStyle(fontSize: 11, color: t.textFaint),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One line of the breakdown legend: swatch, count, share, examples.
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.value,
    required this.total,
    required this.label,
    required this.detail,
  });

  final Color color;
  final int value;
  final int total;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pct = total == 0 ? 0.0 : value * 100 / total;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$value',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: t.textPrimary),
        ),
        const SizedBox(width: 7),
        Text(
          '$label · ${pct.toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.textSecondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            detail,
            style: TextStyle(fontSize: 11, color: t.textFaint),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
