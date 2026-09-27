import 'package:flutter/material.dart';
import 'reaction_picker.dart';

Future<String?> showCompactMessageMenu(
  BuildContext context, {
  required bool ownMessage,
  Rect? anchor,
  String preview = '',
  String? imageUrl,
  String? selectedReaction,
}) async {
  final result = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close message options',
    barrierColor: Colors.black54,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    transitionBuilder: (context, animation, secondary, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: .96, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
    pageBuilder: (context, animation, secondary) => CustomSingleChildLayout(
      delegate: _MenuPosition(
        anchor,
        MediaQuery.paddingOf(context),
        MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: ownMessage
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                _Panel(
                  radius: 32,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        for (final emoji in [
                          '❤️',
                          '😭',
                          '😂',
                          '😜',
                          '🤗',
                          '🙈',
                        ])
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () =>
                                  Navigator.pop(context, 'react:$emoji'),
                              child: Semantics(
                                selected: emoji == selectedReaction,
                                label: emoji,
                                button: true,
                                child: Container(
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: emoji == selectedReaction
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer
                                        : null,
                                  ),
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontFamilyFallback: [
                                        'Noto Color Emoji',
                                        'Apple Color Emoji',
                                        'Segoe UI Emoji',
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: IconButton(
                            tooltip: 'More reactions',
                            onPressed: () => Navigator.pop(context, 'more'),
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (preview.isNotEmpty || imageUrl != null) ...[
                  Container(
                    key: const ValueKey('selected-message-preview'),
                    constraints: const BoxConstraints(maxWidth: 300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: ownMessage
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (imageUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                imageUrl,
                                height: 80,
                                width: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, error, stack) =>
                                    const SizedBox(
                                      height: 48,
                                      child: Icon(Icons.image_outlined),
                                    ),
                              ),
                            ),
                          ),
                        if (preview.isNotEmpty)
                          Text(
                            preview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: ownMessage
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: 230,
                  child: _Panel(
                    radius: 18,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _Action(
                            icon: Icons.reply_rounded,
                            label: 'Reply',
                            value: 'reply',
                          ),
                          const _Action(
                            icon: Icons.forward_outlined,
                            label: 'Forward',
                            value: 'forward',
                          ),
                          const _Action(
                            icon: Icons.copy_rounded,
                            label: 'Copy',
                            value: 'copy',
                          ),
                          if (ownMessage)
                            const _Action(
                              icon: Icons.delete_outline_rounded,
                              label: 'Delete',
                              value: 'delete',
                            )
                          else
                            const _Action(
                              icon: Icons.flag_outlined,
                              label: 'Report',
                              value: 'report',
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (result != 'more' || !context.mounted) return result;
  final emoji = await showReactionPicker(context);
  return emoji == null ? null : 'react:$emoji';
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, required this.radius});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    elevation: 8,
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _MenuPosition extends SingleChildLayoutDelegate {
  _MenuPosition(this.anchor, this.padding, this.keyboard);
  final Rect? anchor;
  final EdgeInsets padding;
  final double keyboard;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => BoxConstraints(
    maxWidth: (c.maxWidth - 24).clamp(0, 340),
    maxHeight: (c.maxHeight - padding.vertical - keyboard - 24).clamp(
      0,
      double.infinity,
    ),
  );
  @override
  Offset getPositionForChild(Size size, Size child) {
    final target =
        anchor ??
        Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
    return Offset(
      (target.center.dx - child.width / 2).clamp(
        12.0,
        size.width - child.width - 12,
      ),
      (target.top - 66).clamp(
        padding.top + 12,
        (size.height - padding.bottom - keyboard - child.height - 12).clamp(
          padding.top + 12,
          double.infinity,
        ),
      ),
    );
  }

  @override
  bool shouldRelayout(covariant _MenuPosition old) =>
      anchor != old.anchor ||
      padding != old.padding ||
      keyboard != old.keyboard;
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.pop(context, value),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 23),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}
