import 'package:flutter/material.dart';

class MediaArtwork extends StatelessWidget {
  const MediaArtwork({
    super.key,
    this.imageUrl,
    this.fit = BoxFit.contain,
    this.decodeWidth = 320,
    this.decodeHeight = 480,
    this.fallbackIcon = Icons.ondemand_video,
  });

  final String? imageUrl;
  final BoxFit fit;
  final int decodeWidth;
  final int decodeHeight;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(fallbackIcon, size: 24);
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return fallback;
    return Image.network(
      url,
      width: double.infinity,
      fit: fit,
      cacheWidth: decodeWidth,
      cacheHeight: decodeHeight,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => fallback,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback,
    );
  }
}
