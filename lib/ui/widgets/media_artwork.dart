import 'package:flutter/material.dart';

class MediaArtwork extends StatelessWidget {
  const MediaArtwork({
    super.key,
    this.imageUrl,
    this.fit = BoxFit.contain,
    this.decodeWidth = 320,
    this.decodeHeight = 480,
    this.resizePolicy = ResizeImagePolicy.exact,
    this.fallbackIcon = Icons.ondemand_video,
  });

  final String? imageUrl;
  final BoxFit fit;
  final int decodeWidth;
  final int decodeHeight;
  final ResizeImagePolicy resizePolicy;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(fallbackIcon, size: 24);
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return fallback;
    return Image(
      image: ResizeImage(
        NetworkImage(url),
        width: decodeWidth,
        height: decodeHeight,
        policy: resizePolicy,
      ),
      width: double.infinity,
      fit: fit,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => fallback,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback,
    );
  }
}
