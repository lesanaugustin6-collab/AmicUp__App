import 'package:flutter/material.dart';
import 'dart:ui';

/// Shared timing for AmicUp's quick, restrained transitions.
abstract final class AmicUpMotion {
  static const fast = Duration(milliseconds: 170);
  static const standard = Duration(milliseconds: 240);
  static const curve = Curves.easeOutCubic;

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}

/// A small crossfade and horizontal settle for content inside a selected tab.
class AmicUpContentSwitcher extends StatelessWidget {
  const AmicUpContentSwitcher({
    super.key,
    required this.child,
    required this.direction,
  });

  final Widget child;
  final int direction;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: AmicUpMotion.duration(context, AmicUpMotion.fast),
    switchInCurve: AmicUpMotion.curve,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0.025 * direction, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: child,
  );
}

/// A translucent surface that keeps the active accent and content visible.
class AmicUpGlassSurface extends StatelessWidget {
  const AmicUpGlassSurface({
    super.key,
    required this.child,
    required this.color,
    required this.borderColor,
    this.radius = 0,
    this.blur = 8,
  });

  final Widget child;
  final Color color;
  final Color borderColor;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: blur <= 0
        ? _surface()
        : BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: _surface(),
          ),
  );

  Widget _surface() => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child,
  );
}

/// Animate only newly received messages, then collapse a confirmed deletion.
class AmicUpMessageMotion extends StatefulWidget {
  const AmicUpMessageMotion({
    super.key,
    required this.child,
    required this.animateEntrance,
    required this.visible,
    required this.ownMessage,
  });

  final Widget child;
  final bool animateEntrance;
  final bool visible;
  final bool ownMessage;

  @override
  State<AmicUpMessageMotion> createState() => _AmicUpMessageMotionState();
}

class _AmicUpMessageMotionState extends State<AmicUpMessageMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AmicUpMotion.fast,
    value: widget.animateEntrance ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animateEntrance) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void didUpdateWidget(AmicUpMessageMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.visible ? widget.child : const SizedBox.shrink();
    }
    final animation = CurvedAnimation(
      parent: _controller,
      curve: AmicUpMotion.curve,
    );
    return SizeTransition(
      sizeFactor: animation,
      alignment: widget.ownMessage
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(widget.ownMessage ? 0.08 : -0.08, 0.08),
            end: Offset.zero,
          ).animate(animation),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Keeps every tab alive while moving only the outgoing and incoming pages.
class AmicUpTabStack extends StatefulWidget {
  const AmicUpTabStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<AmicUpTabStack> createState() => _AmicUpTabStackState();
}

class _AmicUpTabStackState extends State<AmicUpTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AmicUpMotion.standard,
  );
  int? _outgoingIndex;

  @override
  void initState() {
    super.initState();
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(AmicUpTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    _outgoingIndex = oldWidget.index;
    _controller.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _outgoingIndex = null);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = reduceMotion
            ? 1.0
            : AmicUpMotion.curve.transform(_controller.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              Offstage(
                offstage: i != widget.index && i != _outgoingIndex,
                child: TickerMode(
                  enabled: i == widget.index,
                  child: IgnorePointer(
                    ignoring: i != widget.index,
                    child: Transform.scale(
                      scale: i == widget.index ? 0.985 + 0.015 * progress : 1,
                      child: Opacity(
                        opacity: i == widget.index
                            ? 0.72 + 0.28 * progress
                            : i == _outgoingIndex
                            ? 1 - progress
                            : 1,
                        child: widget.children[i],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A plain fade keeps forward and back navigation predictable.
class AmicUpPageTransitionsBuilder extends PageTransitionsBuilder {
  const AmicUpPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return FadeTransition(opacity: animation, child: child);
  }
}
