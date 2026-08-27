import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/starfield.dart';

/// The persistent frame: one starfield painted behind every tab, a bottom
/// navigation bar that respects the gesture inset, and a drawer menu.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _tabs = <_Tab>[
    _Tab('/', 'Convert', Icons.autorenew_rounded, Icons.autorenew_rounded),
    _Tab('/batch', 'Batch', Icons.layers_outlined, Icons.layers_rounded),
    _Tab('/history', 'History', Icons.history_rounded, Icons.history_rounded),
    _Tab('/files', 'Files', Icons.folder_outlined, Icons.folder_rounded),
    _Tab('/settings', 'Settings', Icons.tune_outlined, Icons.tune_rounded),
  ];

  int get _index {
    final i = _tabs.indexWhere((t) => t.path == location);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.background,
      // Not extendBody: the nav bar is effectively opaque, and letting content
      // run underneath it left the last rows of every tab unreachable.
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Starfield(density: 1.0, speed: 1.0),
          // SafeArea keeps page content clear of the notch and status bar; the
          // bottom edge is handled by the nav bar instead.
          SafeArea(bottom: false, child: child),
        ],
      ),
      bottomNavigationBar: _NavBar(
        index: _index,
        tabs: _tabs,
        onTap: (i) => context.go(_tabs[i].path),
      ),
    );
  }
}

class _Tab {
  const _Tab(this.path, this.label, this.icon, this.activeIcon);
  final String path;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.tabs, required this.onTap});

  final int index;
  final List<_Tab> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.94),
        border: Border(top: BorderSide(color: t.border)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 8),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: _NavItem(
                  tab: tabs[i],
                  selected: i == index,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.tab, required this.selected, required this.onTap});

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = selected ? t.textPrimary : t.textFaint;

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The active tab gets a small cap rule instead of a filled pill, so
            // the bar stays as quiet as the rest of the monochrome system.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 2.5,
              width: selected ? 20 : 0,
              margin: const EdgeInsets.only(bottom: 7),
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(selected ? tab.activeIcon : tab.icon, size: 23, color: color),
            const SizedBox(height: 3),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
