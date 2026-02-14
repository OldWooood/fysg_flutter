import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../providers/player_provider.dart';
import '../../models/song.dart';

class PlaylistBottomSheet extends ConsumerStatefulWidget {
  const PlaylistBottomSheet({super.key});

  @override
  ConsumerState<PlaylistBottomSheet> createState() => _PlaylistBottomSheetState();
}

class _PlaylistBottomSheetState extends ConsumerState<PlaylistBottomSheet> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
        // Scroll to current song
        final state = ref.read(playerProvider);
        if (state.currentIndex >= 0 && state.currentIndex < state.queue.length) {
            _itemScrollController.jumpTo(index: state.currentIndex);
        }
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final queue = playerState.queue;

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
         color: Theme.of(context).scaffoldBackgroundColor,
         borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
            // Header
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                        // Mode Toggle
                        TextButton.icon(
                            onPressed: () {
                                ref.read(playerProvider.notifier).toggleMode();
                            },
                            icon: Icon(_getModeIcon(playerState.mode)),
                            label: Text(_getModeLabel(playerState.mode)),
                        ),
                        
                        // Close
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                ),
            ),
            const Divider(height: 1),
            
            // List
            Expanded(
                child: queue.isEmpty 
                    ? const Center(child: Text("Queue is empty"))
                    : ScrollablePositionedList.builder(
                        itemScrollController: _itemScrollController,
                        itemPositionsListener: _itemPositionsListener,
                        itemCount: queue.length,
                        itemBuilder: (context, index) {
                            final song = queue[index];
                            final isCurrent = index == playerState.currentIndex;
                            
                            return ListTile(
                                leading: isCurrent 
                                    ? Icon(Icons.equalizer, color: Theme.of(context).primaryColor)
                                    : Text("${index + 1}", style: const TextStyle(color: Colors.grey)),
                                title: Text(
                                    song.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: isCurrent ? Theme.of(context).primaryColor : null,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal
                                    ),
                                ),
                                subtitle: Text(
                                    song.artist ?? "Unknown", 
                                    maxLines: 1,
                                    style: const TextStyle(fontSize: 12),
                                ),
                                onTap: () {
                                    ref.read(playerProvider.notifier).logQueue(queue, index);
                                },
                            );
                        },
                    ),
            ),
        ],
      ),
    );
  }

  IconData _getModeIcon(PlaybackMode mode) {
      switch (mode) {
          case PlaybackMode.sequence: return Icons.repeat;
          case PlaybackMode.shuffle: return Icons.shuffle;
          case PlaybackMode.single: return Icons.repeat_one;
      }
  }

  String _getModeLabel(PlaybackMode mode) {
      switch (mode) {
          case PlaybackMode.sequence: return "Order";
          case PlaybackMode.shuffle: return "Shuffle";
          case PlaybackMode.single: return "Loop One";
      }
  }
}
