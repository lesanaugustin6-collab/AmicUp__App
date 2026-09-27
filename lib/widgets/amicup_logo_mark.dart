import 'package:flutter/material.dart';

/// The AmicUp mark for compact UI surfaces. It intentionally has no
/// background so it sits cleanly on every navigation/theme surface.
class AmicUpLogoMark extends StatelessWidget {
  const AmicUpLogoMark({super.key, this.size = 30, this.semanticLabel});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      'assets/amicup_logo_transparent.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
    return semanticLabel == null
        ? mark
        : Semantics(label: semanticLabel, image: true, child: mark);
  }
}
