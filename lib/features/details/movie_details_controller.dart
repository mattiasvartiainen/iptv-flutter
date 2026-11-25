import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/logging/app_logger.dart';
import '../../services/metadata/movie_metadata.dart';

class MovieDetailsController extends ChangeNotifier {
  MovieDetailsController({
    required this.repository,
    required this.subject,
    this.logger = const DebugAppLogger(),
  });

  final MovieMetadataRepository repository;
  final MovieMetadataSubject subject;
  final AppLogger logger;
  MovieMetadata? metadata;
  MetadataFailure? failure;
  bool isLoading = false;
  bool isStale = false;
  bool _disposed = false;
  int _generation = 0;
  MetadataCancellation? _cancellation;
  StreamSubscription<MovieMetadataResult>? _subscription;

  void load({bool forceRefresh = false}) {
    if (_disposed) return;
    suspend();
    final generation = ++_generation;
    final cancellation = MetadataCancellation();
    _cancellation = cancellation;
    isLoading = true;
    failure = null;
    notifyListeners();
    _subscription = repository
        .resolve(
          subject,
          cancellation: cancellation,
          forceRefresh: forceRefresh,
        )
        .listen(
          (result) {
            if (_disposed || generation != _generation) return;
            metadata = result.metadata ?? metadata;
            failure = result.failure;
            isStale = result.isStale;
            isLoading = result.isRefreshing;
            notifyListeners();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_disposed || generation != _generation) return;
            // Only a safe category reaches logs/UI; provider or storage errors may echo secrets.
            logger.error('movie_metadata_resolution_failed');
            failure = MetadataFailure.storage;
            isLoading = false;
            notifyListeners();
          },
          onDone: () {
            if (_disposed || generation != _generation) return;
            isLoading = false;
            notifyListeners();
          },
        );
  }

  void suspend() {
    _generation++;
    _cancellation?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    _cancellation = null;
    isLoading = false;
  }

  void clear() {
    suspend();
    metadata = null;
    failure = null;
    isStale = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    suspend();
    super.dispose();
  }
}
