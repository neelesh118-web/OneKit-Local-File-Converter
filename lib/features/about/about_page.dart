import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
                      const Center(child: OneKitLockup(markSize: 76)),
                      const SizedBox(height: 26),
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
                          'OneKit converts files entirely on your device. There is no upload, no queue on '
                          'someone else’s server, and no account. That means your files stay private, it '
                          'works with no signal, and there are no size limits beyond your own storage.',
                          style: TextStyle(fontSize: 14, height: 1.55, color: t.textSecondary),
                        ),
                      ),
                      const SectionTitle('What it covers'),
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
                            applicationName: 'OneKit',
                            applicationVersion: '1.0.0',
                            applicationLegalese: 'Local File Converter',
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Center(
                        child: Text(
                          'OneKit 1.0.0',
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
