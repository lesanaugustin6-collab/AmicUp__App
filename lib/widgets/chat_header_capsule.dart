import 'package:flutter/material.dart';

import '../theme/amicup_motion.dart';
import '../theme/app_theme.dart';

/// The compact, theme-aware surfaces used in conversation headers.
class ChatHeaderCapsule extends StatelessWidget {
  const ChatHeaderCapsule({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context);
    return AmicUpGlassSurface(
      radius: 28,
      blur: 0,
      color: colors.surface.withValues(alpha: 0.92),
      borderColor: colors.line.withValues(alpha: 0.72),
      child: child,
    );
  }
}
