import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/navigation/app_route.dart';
import '../../app/navigation/navigation_controller.dart';
import '../../models/content_item.dart';
import '../../services/metadata/movie_metadata.dart';
import '../../state/catalog_view_state.dart';
import '../../state/playlists_controller.dart';
import '../../ui/theme/app_tokens.dart';
import '../../ui/widgets/app_scope.dart';
import '../../ui/widgets/app_shell_scaffold.dart';
import '../../ui/widgets/media_artwork.dart';
import 'movie_details_controller.dart';

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.item});
  final ContentItem item;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  final _playFocus = FocusNode(debugLabel: 'Details Play');
  MovieDetailsController? _controller;
  CatalogViewState? _catalog;
  NavigationController? _navigation;
  PlaylistsController? _playlists;
  int _sourceRevision = 0;
  bool _sourceApiEnabled = false;
  AppRoute? _ownerRoute;
  bool _active = true;
  bool _reloadOnReturn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_catalog != null) return;
    _catalog = AppScope.appControllerOf(context).catalogView;
    _navigation = AppScope.navigationControllerOf(context);
    _playlists = AppScope.playlistsControllerOf(context);
    _ownerRoute = _navigation!.currentRoute;
    final playlistId = _catalog!.playlistId;
    _sourceRevision =
        _playlists!.playlists
            .where((playlist) => playlist.playlistId == playlistId)
            .firstOrNull
            ?.connectionRevision ??
        0;
    _sourceApiEnabled =
        _playlists!.playlists
            .where((playlist) => playlist.playlistId == playlistId)
            .firstOrNull
            ?.verificationRecord
            ?.apiEnabled ??
        false;
    final repository = AppScope.movieMetadataRepositoryOf(context);
    if (repository != null &&
        playlistId != null &&
        widget.item.type == ContentType.vod) {
      _controller = MovieDetailsController(
        repository: repository,
        subject: MovieMetadataSubject(
          playlistId: playlistId,
          itemId: widget.item.id,
          locale: Localizations.localeOf(context).toLanguageTag(),
        ),
      )..load();
    }
    _catalog!.addListener(_routeChanged);
    _navigation!.addListener(_routeChanged);
    _playlists!.addListener(_routeChanged);
  }

  void _routeChanged() {
    final controller = _controller;
    if (controller == null) return;
    final samePlaylist = _catalog!.playlistId == controller.subject.playlistId;
    if (!samePlaylist) {
      _active = false;
      _reloadOnReturn = false;
      controller.clear();
      return;
    }
    final playlist = _playlists!.playlists
        .where(
          (playlist) => playlist.playlistId == controller.subject.playlistId,
        )
        .firstOrNull;
    if (playlist != null &&
        (playlist.connectionRevision != _sourceRevision ||
            (playlist.verificationRecord?.apiEnabled ?? false) !=
                _sourceApiEnabled)) {
      _sourceRevision = playlist.connectionRevision;
      _sourceApiEnabled = playlist.verificationRecord?.apiEnabled ?? false;
      controller.clear();
      _reloadOnReturn = true;
      if (samePlaylist && identical(_navigation!.currentRoute, _ownerRoute)) {
        _reloadOnReturn = false;
        controller.load();
      }
    }
    final active =
        samePlaylist && identical(_navigation!.currentRoute, _ownerRoute);
    if (active == _active) return;
    _active = active;
    if (!active) {
      _reloadOnReturn = controller.isLoading;
      controller.suspend();
      if (!samePlaylist) {
        controller.clear();
      }
    } else if (_reloadOnReturn) {
      _reloadOnReturn = false;
      controller.load();
    }
  }

  Future<void> _ensurePlayVisible() async {
    final playContext = _playFocus.context;
    if (!mounted || !_playFocus.hasFocus || playContext == null) return;
    await Scrollable.ensureVisible(
      playContext,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    if (!mounted || !playContext.mounted || !_playFocus.hasFocus) return;
    await Scrollable.ensureVisible(
      playContext,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  @override
  void dispose() {
    _catalog?.removeListener(_routeChanged);
    _navigation?.removeListener(_routeChanged);
    _playlists?.removeListener(_routeChanged);
    _controller?.dispose();
    _playFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppShellScaffold(
    showBack: true,
    title: widget.item.title,
    child: _controller == null
        ? _content(context)
        : ListenableBuilder(
            listenable: _controller!,
            builder: (context, _) => _content(context),
          ),
  );

  Widget _content(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _contentForHeight(context, constraints.maxHeight),
  );

  Widget _contentForHeight(BuildContext context, double availableHeight) {
    final item = widget.item;
    final metadata = _controller?.metadata;
    final poster =
        metadata?[MovieMetadataField.poster] ??
        safeArtworkUrl(item.posterUrl ?? item.logoUrl);
    final backdrop = metadata?[MovieMetadataField.backdrop];
    final plot =
        metadata?[MovieMetadataField.plot] ??
        (item.description.isEmpty
            ? 'No description available yet.'
            : item.description);
    final theme = Theme.of(context);
    final facts = <String>[
      ?metadata?[MovieMetadataField.releaseDate],
      ?metadata?[MovieMetadataField.runtime],
      ?metadata?[MovieMetadataField.genres],
      ?metadata?[MovieMetadataField.rating],
    ];
    return SingleChildScrollView(
      padding: AppTokens.pagePaddingFor(MediaQuery.sizeOf(context).width),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= 700 && availableHeight >= 400;
              final artwork = SizedBox(
                width: wide ? 220 : 160,
                height: wide ? 330 : 240,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.cardRadius),
                  child: ColoredBox(
                    color: theme.colorScheme.surfaceContainer,
                    child: MediaArtwork(imageUrl: poster),
                  ),
                ),
              );
              final information = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: theme.textTheme.headlineSmall),
                  if (item.group.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(item.group, style: theme.textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 16),
                  FocusTraversalGroup(
                    child: Focus(
                      canRequestFocus: false,
                      onFocusChange: (focused) {
                        if (!focused) return;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          unawaited(_ensurePlayVisible());
                        });
                      },
                      child: ElevatedButton.icon(
                        focusNode: _playFocus,
                        autofocus: true,
                        onPressed: () => AppScope.playerControllerOf(
                          context,
                        ).openPlayer(item),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play selected stream'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!wide) ...[artwork, const SizedBox(height: 20)],
                  if (facts.isNotEmpty) ...[
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [for (final fact in facts) Text(fact)],
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text('Synopsis', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(plot),
                  for (final (field, label) in const [
                    (MovieMetadataField.director, 'Director'),
                    (MovieMetadataField.cast, 'Cast'),
                  ])
                    if (metadata?[field] case final value?) ...[
                      const SizedBox(height: 16),
                      Text(label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(value),
                    ],
                  if (metadata != null && metadata.fields.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Information: ${metadata.sources.values.toSet().join(', ')}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  _metadataStatus(context),
                ],
              );
              return ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.cardRadius),
                child: Stack(
                  children: [
                    if (backdrop != null)
                      Positioned.fill(
                        child: ExcludeSemantics(
                          child: MediaArtwork(
                            imageUrl: backdrop,
                            fit: BoxFit.cover,
                            decodeWidth: 1280,
                            decodeHeight: 720,
                            fallbackIcon: Icons.movie_outlined,
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: ColoredBox(
                        color: theme.colorScheme.surface.withValues(
                          alpha: backdrop == null ? 1 : 0.94,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                artwork,
                                const SizedBox(width: 28),
                                Expanded(child: information),
                              ],
                            )
                          : information,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _metadataStatus(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    final failure = controller.failure;
    final message = switch (failure) {
      MetadataFailure.unmapped =>
        'Provider information could not be matched to this movie.',
      MetadataFailure.unsupported =>
        'This provider does not support movie information.',
      MetadataFailure.notFound => 'Movie information was not found.',
      MetadataFailure.denied =>
        'Provider access was denied. Check the playlist account in Settings.',
      MetadataFailure.rateLimited =>
        'The provider is busy. Retry movie information later.',
      MetadataFailure.malformed =>
        'The provider returned invalid movie information.',
      MetadataFailure.tooLarge =>
        'The provider returned too much movie information.',
      MetadataFailure.timeout || MetadataFailure.network =>
        'Could not retrieve movie information. You can still play.',
      MetadataFailure.storage => 'Could not load or save movie information.',
      MetadataFailure.unverified ||
      MetadataFailure.notMovie ||
      MetadataFailure.cancelled ||
      null => null,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller.isLoading) const Text('Loading movie information...'),
          if (controller.isStale)
            const Text('Showing cached movie information.'),
          if (message != null) ...[
            Text(message),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => controller.load(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry movie information'),
            ),
          ],
        ],
      ),
    );
  }
}
