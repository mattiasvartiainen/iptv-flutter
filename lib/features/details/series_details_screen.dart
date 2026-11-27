import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../app/navigation/app_route.dart';
import '../../app/navigation/navigation_controller.dart';
import '../../features/catalog/widgets/episode_layout.dart';
import '../../services/catalog/catalog_query.dart';
import '../../services/metadata/series_metadata.dart';
import '../../services/sources/source_contracts.dart';
import '../../state/catalog_view_state.dart';
import '../../state/playlists_controller.dart';
import '../../ui/theme/app_tokens.dart';
import '../../ui/widgets/app_scope.dart';
import '../../ui/widgets/app_shell_scaffold.dart';
import '../../ui/widgets/media_artwork.dart';
import '../../ui/widgets/media_tile.dart';
import 'series_details_controller.dart';

class SeriesDetailsScreen extends StatefulWidget {
  const SeriesDetailsScreen({super.key, required this.series});
  final SeriesSummary series;
  @override
  State<SeriesDetailsScreen> createState() => _SeriesDetailsScreenState();
}

class _SeriesDetailsScreenState extends State<SeriesDetailsScreen> {
  SeriesDetailsController? _controller;
  final _scroll = ScrollController();
  final _firstEpisode = FocusNode(debugLabel: 'Series first episode');
  final _episodeStatus = FocusNode(debugLabel: 'Series episode status');
  final _episodeHeading = GlobalKey();
  final _episodeGrid = GlobalKey();
  (double, double, int, bool)? _episodeLayout;
  String? _focusedEpisodeId;
  final _seasonsFocus = <String, FocusNode>{};
  CatalogViewState? _catalog;
  NavigationController? _navigation;
  PlaylistsController? _playlists;
  AppRoute? _route;
  bool _initialFocusSet = false;
  bool _wasActive = true;
  bool _reloadMetadata = false;
  int _revision = 0;
  bool _apiEnabled = false;
  SourceVerificationState? _verification;
  bool _sourceEnabled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_catalog != null) return;
    _catalog = AppScope.appControllerOf(context).catalogView;
    _navigation = AppScope.navigationControllerOf(context);
    _playlists = AppScope.playlistsControllerOf(context);
    _route = _navigation!.currentRoute;
    final queries = _catalog!.queryService;
    final playlistId = _catalog!.playlistId;
    if (queries == null || playlistId == null) return;
    final source = _playlists!.playlists
        .where((entry) => entry.playlistId == playlistId)
        .firstOrNull;
    _revision = source?.connectionRevision ?? 0;
    _apiEnabled = source?.verificationRecord?.apiEnabled ?? false;
    _verification = source?.verificationRecord?.verification;
    _sourceEnabled = source?.enabled ?? false;
    _controller = SeriesDetailsController(
      queries: queries,
      subject: SeriesMetadataSubject(
        playlistId: playlistId,
        seriesId: widget.series.id,
        locale: Localizations.localeOf(context).toLanguageTag(),
      ),
      repository: AppScope.seriesMetadataRepositoryOf(context),
    );
    _controller!.addListener(_changed);
    _controller!.episodes.addListener(_pageChanged);
    _scroll.addListener(_prefetch);
    _navigation!.addListener(_navigationChanged);
    _catalog!.addListener(_navigationChanged);
    _playlists!.addListener(_navigationChanged);
    unawaited(_controller!.loadSeasons());
    _controller!.loadMetadata();
  }

  void _changed() {
    if (!mounted) return;
    if (!_initialFocusSet && _controller!.seasons.isNotEmpty) {
      _initialFocusSet = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_wasActive) return;
        _focusControl(_seasonsFocus[_controller!.seasons.first.id]);
      });
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_wasActive) return;
      final node = _firstEpisode.hasFocus
          ? _firstEpisode
          : _seasonsFocus.values.where((node) => node.hasFocus).firstOrNull;
      if (node?.context case final focusContext?) {
        unawaited(
          Scrollable.ensureVisible(
            focusContext,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ),
        );
      }
    });
  }

  void _pageChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetch();
    });
  }

  void _prefetch() {
    final controller = _controller;
    if (!_wasActive ||
        controller == null ||
        !_scroll.hasClients ||
        _scroll.position.extentAfter > 400) {
      return;
    }
    if (controller.episodes.hasMore &&
        !controller.episodes.isLoading &&
        !controller.episodes.isLoadingMore &&
        controller.episodes.failure == null) {
      unawaited(controller.episodes.loadMore());
    }
  }

  void _navigationChanged() {
    final controller = _controller;
    if (controller == null) return;
    final source = _playlists!.playlists
        .where((entry) => entry.playlistId == controller.subject.playlistId)
        .firstOrNull;
    final samePlaylist =
        _catalog!.playlistId == controller.subject.playlistId && source != null;
    final changed =
        source != null &&
        (source.connectionRevision != _revision ||
            (source.verificationRecord?.apiEnabled ?? false) != _apiEnabled ||
            source.verificationRecord?.verification != _verification ||
            source.enabled != _sourceEnabled);
    if (changed) {
      _revision = source.connectionRevision;
      _apiEnabled = source.verificationRecord?.apiEnabled ?? false;
      _verification = source.verificationRecord?.verification;
      _sourceEnabled = source.enabled;
      controller.suspendMetadata(clear: true);
      _reloadMetadata = true;
    }
    final active = samePlaylist && identical(_navigation!.currentRoute, _route);
    if (!samePlaylist) {
      controller.suspendMetadata(clear: true);
    } else if (!active && _wasActive) {
      _reloadMetadata = _reloadMetadata || controller.loadingMetadata;
      controller.suspendMetadata();
    }
    if (active && (!_wasActive || changed) && _reloadMetadata) {
      _reloadMetadata = false;
      controller.loadMetadata();
    }
    _wasActive = active;
  }

  void _select(SeasonSummary season) {
    final controller = _controller!;
    if (controller.selectedSeason?.id == season.id) return;
    unawaited(controller.selectSeason(season));
  }

  void _focusControl(FocusNode? node) {
    node?.requestFocus();
    if (node?.context case final focusContext?) {
      unawaited(Scrollable.ensureVisible(focusContext, alignment: 0.2));
    }
  }

  void _preserveEpisodeOnResize(EpisodeLayout layout) {
    final next = (layout.width, layout.height, layout.columns, layout.isRow);
    final previous = _episodeLayout;
    _episodeLayout = next;
    if (previous == null || previous == next) return;
    final focusedNode = FocusManager.instance.primaryFocus;
    final id = _focusedEpisodeId;
    if (id == null || focusedNode == null) return;
    final seasonId = _controller!.selectedSeason?.id;
    final index = _controller!.episodes.items.indexWhere(
      (episode) => episode.id == id,
    );
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          _episodeLayout != next ||
          _controller?.selectedSeason?.id != seasonId ||
          FocusManager.instance.primaryFocus != focusedNode) {
        return;
      }
      final render = _episodeGrid.currentContext?.findRenderObject();
      if (render is! RenderSliver) return;
      final start = _scroll.offset - render.constraints.scrollOffset;
      final extent = layout.isRow
          ? AppTokens.episodeRowExtentFor(layout.textScaler)
          : AppTokens.episodeTileHeight + AppTokens.gridGap;
      final target = start + (index ~/ layout.columns) * extent;
      _scroll.jumpTo(
        target.clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final focusContext = focusedNode.context;
        if (mounted &&
            focusContext != null &&
            FocusManager.instance.primaryFocus == focusedNode) {
          unawaited(Scrollable.ensureVisible(focusContext));
        }
      });
    });
  }

  Future<void> _focusEpisodes() async {
    if (_firstEpisode.context != null) {
      _focusControl(_firstEpisode);
      return;
    }
    if (_episodeHeading.currentContext case final headingContext?) {
      await Scrollable.ensureVisible(headingContext, alignment: 0.1);
    }
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) _focusControl(_firstEpisode);
  }

  @override
  void dispose() {
    _navigation?.removeListener(_navigationChanged);
    _catalog?.removeListener(_navigationChanged);
    _playlists?.removeListener(_navigationChanged);
    _controller?.removeListener(_changed);
    _controller?.episodes.removeListener(_pageChanged);
    _controller?.dispose();
    _scroll.dispose();
    _firstEpisode.dispose();
    _episodeStatus.dispose();
    for (final node in _seasonsFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AppShellScaffold(
      title: widget.series.title,
      showBack: true,
      child: controller == null
          ? const Center(child: Text('Series is unavailable.'))
          : ListenableBuilder(
              listenable: AppScope.preferencesControllerOf(context),
              builder: (context, _) => LayoutBuilder(
                builder: (context, viewport) => CustomScrollView(
                  key: PageStorageKey('series-overview-${widget.series.id}'),
                  controller: _scroll,
                  slivers: [
                    SliverPadding(
                      padding: AppTokens.pagePaddingFor(
                        MediaQuery.sizeOf(context).width,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _header(context, controller),
                            const SizedBox(height: 28),
                            Text(
                              'Seasons',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            if (controller.loadingSeasons)
                              const Text('Loading seasons...')
                            else if (controller.seasonsFailed)
                              TextButton(
                                onPressed: () =>
                                    unawaited(controller.loadSeasons()),
                                child: const Text(
                                  'Could not load seasons. Retry',
                                ),
                              )
                            else if (controller.seasons.isEmpty)
                              const Text('No seasons found.')
                            else
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  for (final season in controller.seasons)
                                    Focus(
                                      onKeyEvent: (node, event) {
                                        if (event is KeyDownEvent &&
                                            event.logicalKey ==
                                                LogicalKeyboardKey.arrowDown) {
                                          if (controller
                                              .episodes
                                              .items
                                              .isNotEmpty) {
                                            unawaited(_focusEpisodes());
                                            return KeyEventResult.handled;
                                          }
                                          if (controller.episodes.failure !=
                                              null) {
                                            _focusControl(_episodeStatus);
                                            return KeyEventResult.handled;
                                          }
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      child: OutlinedButton(
                                        focusNode: _seasonsFocus.putIfAbsent(
                                          season.id,
                                          () => FocusNode(
                                            debugLabel:
                                                'Season ${season.seasonNumber}',
                                          ),
                                        ),
                                        onPressed: () => _select(season),
                                        style:
                                            controller.selectedSeason?.id ==
                                                season.id
                                            ? OutlinedButton.styleFrom(
                                                backgroundColor:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .secondaryContainer,
                                              )
                                            : null,
                                        child: Semantics(
                                          selected:
                                              controller.selectedSeason?.id ==
                                              season.id,
                                          child: Text(
                                            'Season ${season.seasonNumber}',
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 24),
                            Text(
                              key: _episodeHeading,
                              controller.selectedSeason == null
                                  ? 'Select a season to see episodes.'
                                  : 'Episodes - Season ${controller.selectedSeason!.seasonNumber}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      key: _episodeGrid,
                      padding: EdgeInsets.symmetric(
                        horizontal: AppTokens.pageInsetFor(
                          MediaQuery.sizeOf(context).width,
                        ),
                      ),
                      sliver: SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final layout = EpisodeLayout(
                            width: constraints.crossAxisExtent,
                            height: viewport.maxHeight,
                            listPreference: AppScope.preferencesControllerOf(
                              context,
                            ).useListView,
                            textScaler: MediaQuery.textScalerOf(context),
                          );
                          final columns = layout.columns;
                          _preserveEpisodeOnResize(layout);
                          return SliverGrid(
                            gridDelegate: layout.gridDelegate,
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final episode = controller.episodes.items[index];
                              return Focus(
                                canRequestFocus: false,
                                onFocusChange: (focused) {
                                  if (focused) {
                                    _focusedEpisodeId = episode.id;
                                  } else if (_focusedEpisodeId == episode.id) {
                                    _focusedEpisodeId = null;
                                  }
                                },
                                onKeyEvent: (node, event) {
                                  if (index < columns &&
                                      event is KeyDownEvent &&
                                      event.logicalKey ==
                                          LogicalKeyboardKey.arrowUp) {
                                    _focusControl(
                                      _seasonsFocus[controller
                                          .selectedSeason
                                          ?.id],
                                    );
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: MediaTile(
                                  key: ValueKey(episode.id),
                                  listView: layout.isRow,
                                  episodeRow: layout.isRow,
                                  keepAliveWhileFocused: true,
                                  imageUrl:
                                      episode.artworkUrl ?? episode.logoUrl,
                                  title: episode.title,
                                  subtitle:
                                      'Episode ${episode.episodeNumber ?? '-'}',
                                  focusNode: index == 0 ? _firstEpisode : null,
                                  icon: Icons.play_circle_outline,
                                  onActivate: () => AppScope.activateItemById(
                                    context,
                                    episode.id,
                                  ),
                                ),
                              );
                            }, childCount: controller.episodes.items.length),
                          );
                        },
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child:
                            controller.episodes.isLoading ||
                                controller.episodes.isLoadingMore
                            ? const Text('Loading episodes...')
                            : controller.episodes.failure != null
                            ? Focus(
                                onKeyEvent: (node, event) {
                                  if (event is KeyDownEvent &&
                                      event.logicalKey ==
                                          LogicalKeyboardKey.arrowUp) {
                                    _focusControl(
                                      _seasonsFocus[controller
                                          .selectedSeason
                                          ?.id],
                                    );
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: TextButton(
                                  focusNode: _episodeStatus,
                                  onPressed: () => _retryEpisodes(),
                                  child: const Text(
                                    'Could not load episodes. Retry',
                                  ),
                                ),
                              )
                            : controller.episodes.hasMore
                            ? TextButton(
                                onPressed: () =>
                                    unawaited(controller.episodes.loadMore()),
                                child: const Text('Load more episodes'),
                              )
                            : controller.selectedSeason != null &&
                                  controller.episodes.items.isEmpty
                            ? const Text('No episodes found.')
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  void _retryEpisodes() {
    _focusControl(_seasonsFocus[_controller!.selectedSeason?.id]);
    unawaited(_controller!.episodes.retry());
  }

  Widget _header(BuildContext context, SeriesDetailsController controller) {
    final metadata = controller.metadata;
    final backdrop = metadata?[ContentMetadataField.backdrop];
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final poster = SizedBox(
          width: wide ? 180 : 120,
          height: wide ? 270 : 180,
          child: MediaArtwork(
            imageUrl:
                metadata?[ContentMetadataField.poster] ??
                safeArtworkUrl(widget.series.artworkUrl),
          ),
        );
        final information = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.series.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${widget.series.seasonCount} seasons · ${widget.series.episodeCount} episodes',
            ),
            const SizedBox(height: 12),
            Text(
              metadata?[ContentMetadataField.plot] ??
                  'No description available yet.',
            ),
            for (final (field, label) in const [
              (ContentMetadataField.releaseDate, 'Released'),
              (ContentMetadataField.genres, 'Genres'),
              (ContentMetadataField.rating, 'Rating'),
              (ContentMetadataField.director, 'Director'),
              (ContentMetadataField.cast, 'Cast'),
            ])
              if (metadata?[field] case final value?) ...[
                const SizedBox(height: 8),
                Text('$label: $value'),
              ],
            if (controller.loadingMetadata)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Loading series information...'),
              ),
            if (controller.staleMetadata)
              const Text('Showing cached series information.'),
            if (controller.metadataFailure case final failure?
                when failure != MetadataFailure.unverified &&
                    failure != MetadataFailure.cancelled) ...[
              const SizedBox(height: 12),
              Text(
                failure == MetadataFailure.unmapped
                    ? 'Provider information could not be matched safely to this series.'
                    : 'Could not retrieve series information. Seasons and episodes remain available.',
              ),
              TextButton.icon(
                onPressed: () => controller.loadMetadata(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry series information'),
              ),
            ],
            if (metadata != null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Information: Xtream'),
              ),
          ],
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.cardRadius),
          child: Stack(
            children: [
              if (backdrop != null)
                Positioned.fill(
                  child: MediaArtwork(
                    imageUrl: backdrop,
                    fit: BoxFit.cover,
                    decodeWidth: 1280,
                    decodeHeight: 720,
                  ),
                ),
              Positioned.fill(
                child: ColoredBox(
                  color: theme.colorScheme.surface.withValues(
                    alpha: backdrop == null ? 1 : 0.9,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          poster,
                          const SizedBox(width: 24),
                          Expanded(child: information),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          poster,
                          const SizedBox(height: 16),
                          information,
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
