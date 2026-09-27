import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, required this.visible});

  final bool visible;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.visible) _controller.repeat();
  }

  @override
  void didUpdateWidget(TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: widget.visible
          ? Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 5, 16, 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.of(context).surfaceMuted,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    3,
                    (index) => _TypingDot(
                      controller: _controller,
                      index: index,
                      animate: !reduceMotion,
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _TypingDot extends StatelessWidget {
  const _TypingDot({
    required this.controller,
    required this.index,
    required this.animate,
  });

  final AnimationController controller;
  final int index;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final begin = index * 0.16;
    final animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.72, end: 1), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0.72), weight: 55),
    ]).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(
          begin,
          (begin + 0.62).clamp(0.0, 1.0).toDouble(),
        ),
      ),
    );

    final dot = Container(
      width: 7,
      height: 7,
      margin: EdgeInsets.only(right: index == 2 ? 0 : 5),
      decoration: BoxDecoration(
        color: AppTheme.of(context).muted,
        shape: BoxShape.circle,
      ),
    );
    if (!animate) return dot;
    return ScaleTransition(scale: animation, child: dot);
  }
}
