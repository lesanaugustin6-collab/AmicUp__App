import 'dart:math' as math;

import 'package:flutter/material.dart';

enum SwipeDirection { left, right }

class SwipeableCardStackController {
  VoidCallback? _swipeLeft;
  VoidCallback? _swipeRight;

  void _attach({
    required VoidCallback swipeLeft,
    required VoidCallback swipeRight,
  }) {
    _swipeLeft = swipeLeft;
    _swipeRight = swipeRight;
  }

  void _detach() {
    _swipeLeft = null;
    _swipeRight = null;
  }

  void swipeLeft() => _swipeLeft?.call();

  void swipeRight() => _swipeRight?.call();

  // Backward-compatible aliases for earlier vertical integrations.
  void swipeUp() => _swipeLeft?.call();

  void swipeDown() => _swipeRight?.call();
}

class SwipeableCardStack extends StatefulWidget {
  const SwipeableCardStack({
    super.key,
    required this.topCard,
    this.nextCard,
    required this.onLike,
    required this.onPass,
    this.controller,
    this.swipeThreshold = 0.22,
    this.velocityThreshold = 900,
  });

  final Widget topCard;
  final Widget? nextCard;
  final Future<void> Function() onLike;
  final Future<void> Function() onPass;
  final SwipeableCardStackController? controller;
  final double swipeThreshold;
  final double velocityThreshold;

  @override
  State<SwipeableCardStack> createState() => _SwipeableCardStackState();
}

class _SwipeableCardStackState extends State<SwipeableCardStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _swipeController;
  Animation<double>? _swipeAnimation;

  double _dragDx = 0;
  bool _isAnimatingOut = false;

  @override
  void initState() {
    super.initState();
    _swipeController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 280),
          )
          ..addListener(() {
            final animation = _swipeAnimation;
            if (animation == null) return;
            setState(() {
              _dragDx = animation.value;
            });
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _swipeAnimation = null;
            }
          });

    widget.controller?._attach(
      swipeLeft: _triggerSwipeLeft,
      swipeRight: _triggerSwipeRight,
    );
  }

  @override
  void didUpdateWidget(covariant SwipeableCardStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(
        swipeLeft: _triggerSwipeLeft,
        swipeRight: _triggerSwipeRight,
      );
    }

    if (!_isAnimatingOut && _dragDx != 0) {
      _dragDx = 0;
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _swipeController.dispose();
    super.dispose();
  }

  Future<void> _animateToDx(double targetDx) async {
    _swipeController.stop();
    _swipeController.reset();

    _swipeAnimation = Tween<double>(begin: _dragDx, end: targetDx).animate(
      CurvedAnimation(parent: _swipeController, curve: Curves.easeOutCubic),
    );

    await _swipeController.forward();
  }

  Future<void> _animateOffscreen(SwipeDirection direction) async {
    if (_isAnimatingOut) return;
    _isAnimatingOut = true;

    final width = MediaQuery.of(context).size.width;
    final targetDx = direction == SwipeDirection.right
        ? width * 1.15
        : -width * 1.15;

    await _animateToDx(targetDx);

    if (!mounted) return;

    if (direction == SwipeDirection.right) {
      await widget.onLike();
    } else {
      await widget.onPass();
    }

    if (!mounted) return;

    setState(() {
      _dragDx = 0;
      _isAnimatingOut = false;
    });
  }

  Future<void> _settleBack() async {
    await _animateToDx(0);
    if (!mounted) return;
    setState(() {
      _dragDx = 0;
    });
  }

  void _triggerSwipeLeft() {
    _animateOffscreen(SwipeDirection.left);
  }

  void _triggerSwipeRight() {
    _animateOffscreen(SwipeDirection.right);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_isAnimatingOut) return;
    setState(() {
      _dragDx += details.delta.dx;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_isAnimatingOut) return;

    final width = MediaQuery.of(context).size.width;
    final threshold = width * widget.swipeThreshold;
    final velocityX = details.velocity.pixelsPerSecond.dx;

    final crossedRight = _dragDx > threshold;
    final crossedLeft = _dragDx < -threshold;
    final fastRight = velocityX > widget.velocityThreshold;
    final fastLeft = velocityX < -widget.velocityThreshold;

    if (crossedRight || fastRight) {
      _animateOffscreen(SwipeDirection.right);
      return;
    }

    if (crossedLeft || fastLeft) {
      _animateOffscreen(SwipeDirection.left);
      return;
    }

    _settleBack();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final normalizedDx = (_dragDx / (width * widget.swipeThreshold)).clamp(
      -1.0,
      1.0,
    );
    final swipeProgress = normalizedDx.abs();
    final passOpacity = normalizedDx < 0 ? swipeProgress : 0.0;
    final likeOpacity = normalizedDx > 0 ? swipeProgress : 0.0;
    final rotation = normalizedDx * 0.12;
    final nextCardScale = 0.94 + (swipeProgress * 0.03);
    final nextCardOffsetY = 16 - (swipeProgress * 6);

    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.nextCard != null)
          IgnorePointer(
            child: Opacity(
              opacity: 0.88 + (swipeProgress * 0.08),
              child: Transform.scale(
                scale: nextCardScale,
                alignment: Alignment.center,
                child: Transform.translate(
                  offset: Offset(0, nextCardOffsetY),
                  child: widget.nextCard,
                ),
              ),
            ),
          ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          child: Transform.translate(
            offset: Offset(_dragDx, 0),
            child: Transform.rotate(
              angle: rotation,
              child: Transform.translate(
                offset: Offset(normalizedDx * 12, 0),
                child: Stack(
                  children: [
                    widget.topCard,
                    Positioned(
                      top: 28,
                      left: 20,
                      child: Opacity(
                        opacity: likeOpacity,
                        child: const _SwipeStamp(
                          label: 'CONNECT',
                          color: Colors.green,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 28,
                      right: 20,
                      child: Opacity(
                        opacity: passOpacity,
                        child: const _SwipeStamp(
                          label: 'PASS',
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SwipeStamp extends StatelessWidget {
  const _SwipeStamp({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: label == 'CONNECT' ? -math.pi / 20 : math.pi / 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          border: Border.all(color: color.withValues(alpha: 0.95), width: 2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.95),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }
}
