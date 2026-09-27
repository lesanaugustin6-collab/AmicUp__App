import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/amicup_motion.dart';

/// Shared, restrained gestures for text and photo messages.
class MessageInteraction extends StatefulWidget {
  const MessageInteraction({
    super.key,
    required this.child,
    required this.onOptions,
    required this.onHeart,
    required this.onReply,
    this.ownMessage = false,
    this.highlighted,
    this.messageId,
    this.sentAt,
    this.forwarded = false,
  });
  final Widget child;
  final VoidCallback onOptions;
  final VoidCallback onHeart;
  final VoidCallback onReply;
  final bool ownMessage;
  final ValueListenable<String?>? highlighted;
  final String? messageId;
  final DateTime? sentAt;
  final bool forwarded;

  @override
  State<MessageInteraction> createState() => _MessageInteractionState();
}

class _MessageInteractionState extends State<MessageInteraction> {
  double _offset = 0;
  bool _dragging = false;
  bool _armed = false;
  bool _showTime = false;

  Widget _content(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: widget.ownMessage
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      if (widget.forwarded)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
          child: Text(
            'Forwarded',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      widget.child,
      AnimatedSize(
        duration: AmicUpMotion.duration(context, AmicUpMotion.fast),
        curve: AmicUpMotion.curve,
        child: _showTime && widget.sentAt != null
            ? Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                child: Text(
                  DateFormat(
                    'MMM d, y • HH:mm',
                  ).format(widget.sentAt!.toLocal()),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    ],
  );

  void _reset() => setState(() {
    _offset = 0;
    _armed = false;
    _dragging = false;
  });

  @override
  Widget build(BuildContext context) => Semantics(
    customSemanticsActions: {
      const CustomSemanticsAction(label: 'Message options'): widget.onOptions,
      const CustomSemanticsAction(label: 'React with heart'): widget.onHeart,
      const CustomSemanticsAction(label: 'Reply'): widget.onReply,
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.sentAt == null
          ? null
          : () => setState(() => _showTime = !_showTime),
      onLongPress: () {
        HapticFeedback.selectionClick();
        widget.onOptions();
      },
      onDoubleTap: () {
        HapticFeedback.selectionClick();
        widget.onHeart();
      },
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: (details) {
        final next = (_offset + details.delta.dx * (widget.ownMessage ? -1 : 1))
            .clamp(0.0, 64.0);
        if (next >= 48 && !_armed) HapticFeedback.selectionClick();
        setState(() {
          _offset = next;
          _armed = next >= 48;
        });
      },
      onHorizontalDragCancel: _reset,
      onHorizontalDragEnd: (_) {
        final reply = _armed;
        _reset();
        if (reply) widget.onReply();
      },
      child: Stack(
        alignment: widget.ownMessage
            ? Alignment.centerRight
            : Alignment.centerLeft,
        children: [
          if (_offset > 0)
            Opacity(
              opacity: (_offset / 48).clamp(0.0, 1.0),
              child: Icon(
                Icons.reply_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          AnimatedContainer(
            duration: _dragging || MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AmicUpMotion.fast,
            curve: AmicUpMotion.curve,
            transform: Matrix4.translationValues(
              _offset * (widget.ownMessage ? -1 : 1),
              0,
              0,
            ),
            child: widget.highlighted == null
                ? _content(context)
                : ValueListenableBuilder<String?>(
                    valueListenable: widget.highlighted!,
                    builder: (context, value, child) => AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                      foregroundDecoration: BoxDecoration(
                        color: value == widget.messageId
                            ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: .16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: child,
                    ),
                    child: _content(context),
                  ),
          ),
        ],
      ),
    ),
  );
}
