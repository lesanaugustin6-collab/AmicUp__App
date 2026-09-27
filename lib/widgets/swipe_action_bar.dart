import 'package:flutter/material.dart';

class SwipeActionBar extends StatelessWidget {
  const SwipeActionBar({
    super.key,
    required this.onUndo,
    required this.onPass,
    required this.onLike,
    required this.canUndo,
  });

  final VoidCallback? onUndo;
  final VoidCallback onPass;
  final VoidCallback onLike;
  final bool canUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            onPressed: canUndo ? onUndo : null,
            style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
            icon: Icon(
              Icons.undo_rounded,
              color: canUndo
                  ? colors.primary
                  : colors.onSurface.withValues(alpha: 0.35),
            ),
            tooltip: 'Undo',
          ),
          const SizedBox(width: 20),
          FloatingActionButton(
            heroTag: null,
            onPressed: onPass,
            backgroundColor: colors.errorContainer,
            foregroundColor: colors.error,
            elevation: 3,
            highlightElevation: 5,
            child: const Icon(Icons.close),
          ),
          const SizedBox(width: 20),
          FloatingActionButton(
            heroTag: null,
            onPressed: onLike,
            backgroundColor: Colors.green.shade100,
            foregroundColor: Colors.green.shade800,
            elevation: 3,
            highlightElevation: 5,
            child: const Icon(Icons.check_rounded),
          ),
        ],
      ),
    );
  }
}
