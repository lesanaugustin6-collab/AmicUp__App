import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSendMessage,
    this.isSending = false,
    this.isBlocked = false,
    this.hintText = 'Message...',
  });

  final Function(String) onSendMessage;
  final bool isSending;
  final bool isBlocked;
  final String hintText;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  late final TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (_hasText != hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSendMessage(text);
      _controller.clear();
      setState(() => _hasText = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sendColor = _hasText
        ? theme.colorScheme.primary
        : (isDark ? AppTheme.of(context).ink : AppTheme.of(context).muted);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 8),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.darkSurface
                : AppTheme.of(context).surfaceMuted,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: AppTheme.of(context).ink.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !widget.isBlocked && !widget.isSending,
                    textInputAction: TextInputAction.send,
                    keyboardType: TextInputType.text,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _handleSend(),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        color: AppTheme.of(context).muted,
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: sendColor,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed:
                        (_hasText && !widget.isBlocked && !widget.isSending)
                        ? _handleSend
                        : null,
                    icon: Icon(
                      Icons.arrow_upward_rounded,
                      color: AppTheme.of(context).onAccent,
                      size: 18,
                    ),
                    splashRadius: 22,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
