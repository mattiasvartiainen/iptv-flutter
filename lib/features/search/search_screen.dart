import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/catalog/catalog_query.dart';
import '../../state/app_controller.dart';
import '../../state/catalog_view_state.dart';
import '../../ui/theme/app_tokens.dart';
import '../../ui/widgets/app_scope.dart';
import '../../ui/widgets/app_shell_scaffold.dart';
import '../../ui/widgets/paged_list_view.dart';
import '../../ui/widgets/state_views.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _textController = TextEditingController();
  Timer? _debounce;
  Timer? _statusTimer;
  AppController? _controller;
  CatalogViewState? _catalogView;
  CatalogItemKind? _kind;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.appControllerOf(context);
    if (identical(controller, _controller)) return;
    _catalogView?.removeListener(_syncStatusPolling);
    _controller = controller;
    _catalogView = controller.catalogView..addListener(_syncStatusPolling);
    unawaited(_refreshIndexStatus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _statusTimer?.cancel();
    _catalogView?.removeListener(_syncStatusPolling);
    _textController.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _runSearch();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  void _runSearch() {
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.catalogView.search(_textController.text, kind: _kind));
  }

  Future<void> _refreshIndexStatus() async {
    final view = _catalogView;
    if (view == null) return;
    await view.refreshSearchIndexStatus();
    _syncStatusPolling();
  }

  void _syncStatusPolling() {
    if (!mounted) return;
    if (_catalogView?.searchIndexStatus?.pendingItems == 0) {
      _statusTimer?.cancel();
      _statusTimer = null;
      return;
    }
    _statusTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshIndexStatus());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.appControllerOf(context);
    final view = controller.catalogView;
    return AppShellScaffold(
      showBack: true,
      title: 'Search',
      child: FocusTraversalGroup(
        child: Padding(
          padding: AppTokens.searchPaddingFor(MediaQuery.sizeOf(context).width),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _textController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _scheduleSearch,
                onSubmitted: (_) {
                  _debounce?.cancel();
                  _runSearch();
                },
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search channels, movies, and series',
                  suffixIcon: IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _textController.clear();
                      _scheduleSearch('');
                    },
                    icon: const Icon(Icons.clear),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _kindFilter('All', null),
                  _kindFilter('Live', CatalogItemKind.live),
                  _kindFilter('Movies', CatalogItemKind.movie),
                  _kindFilter('Series', CatalogItemKind.episode),
                ],
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: view,
                builder: (context, _) {
                  final status = view.searchIndexStatus;
                  if (status == null || !status.isIndexing) {
                    return const SizedBox.shrink();
                  }
                  final progress = status.totalItems == 0
                      ? null
                      : status.indexedItems / status.totalItems;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Building search index · ${status.indexedItems} of ${status.totalItems} items',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(value: progress),
                      ],
                    ),
                  );
                },
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: view.searchResults,
                  builder: (context, _) {
                    final results = view.searchResults;
                    if (_textController.text.trim().isEmpty) {
                      return const _SearchMessage(
                        icon: Icons.manage_search,
                        text: 'Enter a title to search this playlist.',
                      );
                    }
                    if (results.isLoading) {
                      return const LoadingView();
                    }
                    if (results.errorMessage != null && results.items.isEmpty) {
                      return ErrorView(
                        message: results.errorMessage!,
                        onRetry: _runSearch,
                      );
                    }
                    return PagedListView<CatalogItemSummary>(
                      collection: results,
                      emptyMessage: 'No matching titles.',
                      emptyIcon: Icons.search_off,
                      onRetry: _runSearch,
                      itemBuilder: (context, item, index) => ListTile(
                        key: ValueKey<String>(item.id),
                        leading: Icon(_iconFor(item.kind)),
                        title: Text(item.title, maxLines: 1),
                        subtitle: Text(
                          '${_kindName(item.kind)} · ${item.group ?? 'Ungrouped'}',
                          maxLines: 1,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => controller.openDetailsById(item.id),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindFilter(String label, CatalogItemKind? kind) => ChoiceChip(
    label: Text(label),
    selected: _kind == kind,
    onSelected: (_) {
      setState(() => _kind = kind);
      _runSearch();
    },
  );
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 36),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}

IconData _iconFor(CatalogItemKind kind) => switch (kind) {
  CatalogItemKind.live => Icons.live_tv,
  CatalogItemKind.movie => Icons.movie,
  CatalogItemKind.episode => Icons.tv,
  CatalogItemKind.unknown => Icons.play_circle_outline,
};

String _kindName(CatalogItemKind kind) => switch (kind) {
  CatalogItemKind.live => 'Live TV',
  CatalogItemKind.movie => 'Movie',
  CatalogItemKind.episode => 'Series',
  CatalogItemKind.unknown => 'Media',
};
