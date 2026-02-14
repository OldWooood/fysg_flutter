import 'package:flutter/material.dart';

import '../../models/song.dart';
import 'song_cover.dart';

class SongListTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final IconData fallbackIcon;
  final double coverSize;
  final BorderRadius coverRadius;

  const SongListTile({
    super.key,
    required this.song,
    required this.onTap,
    this.leading,
    this.trailing,
    this.contentPadding,
    this.titleStyle,
    this.subtitleStyle,
    this.fallbackIcon = Icons.music_note,
    this.coverSize = 50,
    this.coverRadius = const BorderRadius.all(Radius.circular(4)),
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTitleStyle =
        titleStyle ??
        Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold);
    final effectiveSubtitleStyle =
        subtitleStyle ?? Theme.of(context).textTheme.bodyMedium;

    return ListTile(
      contentPadding: contentPadding,
      leading: leading ?? _buildDefaultLeading(),
      title: Text(
        song.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: effectiveTitleStyle,
      ),
      subtitle: Text(
        song.artist ?? 'Unknown',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: effectiveSubtitleStyle,
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildDefaultLeading() {
    return SongCover(
      imageUrl: song.cover,
      width: coverSize,
      height: coverSize,
      borderRadius: coverRadius,
      placeholderIcon: fallbackIcon,
      placeholderIconSize: coverSize * 0.8,
    );
  }
}
