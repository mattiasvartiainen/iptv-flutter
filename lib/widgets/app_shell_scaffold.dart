import 'package:flutter/material.dart';

import '../app/navigation/app_route.dart';
import '../app/navigation/navigation_controller.dart';
import '../state/app_controller.dart';
import '../ui/theme/app_tokens.dart';
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
    final controller = AppScope.appControllerOf(context);
    final navigation = AppScope.navigationControllerOf(context);
    return ListenableBuilder(
      listenable: navigation,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < AppTokens.compactBreakpoint ||
              constraints.maxHeight < AppTokens.compactNavigationFallbackHeight;
          final extendedRail =
              !compact && constraints.maxWidth >= AppTokens.expandedBreakpoint;
          return _buildScaffold(
            context,
            controller,
            compact: compact,
            extendedRail: extendedRail,
          );
        },
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    AppController controller, {
    required bool compact,
    required bool extendedRail,
  }) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: compact
          ? AppBar(
              automaticallyImplyLeading: false,
              leading: showBack
                  ? IconButton(
                      tooltip: 'Back',
                      onPressed: controller.goBack,
                      icon: const Icon(Icons.arrow_back),
                    )
                  : null,
              title: Text(
                title ?? 'IPTV',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                FocusTraversalGroup(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Search',
                        onPressed: controller.openSearch,
                        icon: const Icon(Icons.search),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: controller.openSettings,
                        icon: const Icon(Icons.settings),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: Row(
          children: [
            Offstage(
              offstage: compact,
              child: _buildNavigationRail(
                context,
                controller,
                extended: extendedRail,
              ),
            ),
            Offstage(offstage: compact, child: const VerticalDivider(width: 1)),
            Expanded(
              child: Column(
                children: [
                  Offstage(
                    offstage: compact || (!showBack && title == null),
                    child: _buildPageHeading(context, controller, theme),
                  ),
                  Expanded(child: FocusTraversalGroup(child: child)),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: compact
          ? FocusTraversalGroup(
              child: NavigationBar(
                selectedIndex: _compactSelectedIndex(controller),
                onDestinationSelected: (index) =>
                    _openCompactDestination(controller, index),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.live_tv_outlined),
                    selectedIcon: Icon(Icons.live_tv),
                    label: 'Live',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.movie_outlined),
                    selectedIcon: Icon(Icons.movie),
                    label: 'Movies',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.tv_outlined),
                    selectedIcon: Icon(Icons.tv),
                    label: 'Series',
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildNavigationRail(
    BuildContext context,
    AppController controller, {
    required bool extended,
  }) {
    final navigation = AppScope.navigationControllerOf(context);
    final selectedIndex = navigation.currentRoute is SettingsRoute
        ? 5
        : switch (controller.activeNavItem) {
            PrimaryNavItem.home => 0,
            PrimaryNavItem.liveTv => 1,
            PrimaryNavItem.movies => 2,
            PrimaryNavItem.series => 3,
            PrimaryNavItem.search => 4,
          };
    return FocusTraversalGroup(
      child: NavigationRail(
        extended: extended,
        minWidth: 72,
        minExtendedWidth: 190,
        labelType: extended ? null : NavigationRailLabelType.selected,
        leading: extended
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'IPTV',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              )
            : const SizedBox(height: 16),
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) =>
            _openRailDestination(controller, index),
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: Text('Home'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.live_tv_outlined),
            selectedIcon: Icon(Icons.live_tv),
            label: Text('Live'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie),
            label: Text('Movies'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.tv_outlined),
            selectedIcon: Icon(Icons.tv),
            label: Text('Series'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.search),
            label: Text('Search'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: Text('Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeading(
    BuildContext context,
    AppController controller,
    ThemeData theme,
  ) => FocusTraversalGroup(
    child: Padding(
      padding: AppTokens.shellTitlePaddingFor(MediaQuery.sizeOf(context).width),
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
  );

  int _compactSelectedIndex(AppController controller) =>
      switch (controller.activeNavItem) {
        PrimaryNavItem.home || PrimaryNavItem.search => 0,
        PrimaryNavItem.liveTv => 1,
        PrimaryNavItem.movies => 2,
        PrimaryNavItem.series => 3,
      };

  void _openCompactDestination(AppController controller, int index) {
    switch (index) {
      case 0:
        controller.openHome();
      case 1:
        controller.openLiveTv();
      case 2:
        controller.openMovies();
      case 3:
        controller.openSeries();
    }
  }

  void _openRailDestination(AppController controller, int index) {
    switch (index) {
      case 0:
        controller.openHome();
      case 1:
        controller.openLiveTv();
      case 2:
        controller.openMovies();
      case 3:
        controller.openSeries();
      case 4:
        controller.openSearch();
      case 5:
        controller.openSettings();
    }
  }
}
