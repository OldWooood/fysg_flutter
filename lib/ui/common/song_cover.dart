import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../api/image_cache_service.dart';

class SongCover extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData placeholderIcon;
  final double placeholderIconSize;

  const SongCover({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderIcon = Icons.music_note,
    this.placeholderIconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final child = _buildImageOrPlaceholder(context);
    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }

  Widget _buildImageOrPlaceholder(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return _placeholder(context);
    }

    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: ImageCacheService.headers,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, _) => _placeholder(context),
      errorWidget: (context, _, __) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
      alignment: Alignment.center,
      child: Icon(
        placeholderIcon,
        size: placeholderIconSize,
        color: Colors.grey,
      ),
    );
  }
}
