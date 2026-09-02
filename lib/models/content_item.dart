import 'package:flutter/foundation.dart';

enum ContentType { live, vod }

@immutable
class ContentItem {
  const ContentItem({
    required this.id,
    required this.title,
    required this.type,
    required this.streamUrl,
    required this.group,
    this.description = '',
    this.logoUrl,
    this.posterUrl,
    this.metadata = const <String, String>{},
    this.sourceIndex = 0,
  });

  final String id;
  final String title;
  final ContentType type;
  final String streamUrl;
  final String group;
  final String description;
  final String? logoUrl;
  final String? posterUrl;
  final Map<String, String> metadata;
  final int sourceIndex;
}
