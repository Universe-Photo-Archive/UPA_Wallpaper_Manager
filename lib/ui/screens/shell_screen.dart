import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../l10n/app_localizations.dart';

/// Adaptive shell: sidebar on desktop, bottom nav on mobile.
class ShellScreen extends ConsumerWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/gallery')) return 1;
    if (location.startsWith('/settings')) return 2;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/gallery');
      case 2:
        context.go('/settings');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final index = _currentIndex(context);
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final scale = ref.watch(configProvider).uiScale;

    final destinations = [
      _NavItem(Icons.home_rounded, l10n.navHome),
      _NavItem(Icons.photo_library_rounded, l10n.navGallery),
      _NavItem(Icons.settings_rounded, l10n.navSettings),
    ];

    if (isWide) {
      // Desktop: sidebar
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: (i) => _onTap(context, i),
              labelType: NavigationRailLabelType.all,
              minWidth: 72 * scale,
              leading: Padding(
                padding: EdgeInsets.symmetric(vertical: 16 * scale),
                child: Image.asset(
                  'assets/icons/app_icon.png',
                  width: 32 * scale,
                  height: 32 * scale,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              destinations: destinations
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.icon, size: 24 * scale),
                        selectedIcon: Icon(d.icon, size: 24 * scale),
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).dividerTheme.color,
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    // Mobile: bottom nav. SafeArea pushes every tab (home / gallery /
    // settings) below the phone status bar (clock, battery, network).
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: child,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => _onTap(context, i),
        destinations: destinations
            .map((d) => NavigationDestination(
                  icon: Icon(d.icon),
                  label: d.label,
                ))
            .toList(),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}
