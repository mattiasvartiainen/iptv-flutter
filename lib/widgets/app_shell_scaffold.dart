import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'app_scope.dart';

class AppShellScaffold extends StatelessWidget {
  const AppShellScaffold({
    super.key,
    required this.child,
    this.showBack = false,
    this.title,
  });

  final Widget child;
  final bool showBack;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 24, 40, 18),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Text(
                            'IPTV',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(width: 32),
                          _NavButton(
                            label: 'HOME',
                            active:
                                controller.activeNavItem == PrimaryNavItem.home,
                            onPressed: controller.openHome,
                          ),
                          _NavButton(
                            label: 'LIVE TV',
                            active:
                                controller.activeNavItem ==
                                PrimaryNavItem.liveTv,
                            onPressed: controller.openLiveTv,
                          ),
                          _NavButton(
                            label: 'MOVIES',
                            active:
                                controller.activeNavItem ==
                                PrimaryNavItem.movies,
                            onPressed: controller.openMovies,
                          ),
                          _NavButton(
                            label: 'SERIES',
                            active:
                                controller.activeNavItem ==
                                PrimaryNavItem.series,
                            onPressed: controller.openSeries,
                          ),
                          _NavButton(
                            label: 'SEARCH',
                            active:
                                controller.activeNavItem ==
                                PrimaryNavItem.search,
                            onPressed: controller.openSearch,
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: controller.openSettings,
                    icon: const Icon(Icons.settings),
                    tooltip: 'Settings',
                  ),
                ],
              ),
            ),
            if (showBack || title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 12),
                child: Row(
                  children: [
                    if (showBack)
                      TextButton.icon(
                        onPressed: controller.goBack,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back'),
                      ),
                    if (title != null) ...[
                      if (showBack) const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: active
              ? Colors.white
              : theme.colorScheme.onSurface.withValues(alpha: 0.72),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 2,
              width: 52,
              decoration: BoxDecoration(
                color: active ? theme.colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
