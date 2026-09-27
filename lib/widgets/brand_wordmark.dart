import 'package:flutter/material.dart';

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Amic',
            style: TextStyle(
              color: dark ? const Color(0xFFBBA3F3) : const Color(0xFF493078),
            ),
          ),
          TextSpan(
            text: 'Up',
            style: TextStyle(
              color: dark ? const Color(0xFFE0D4FF) : const Color(0xFF8053D7),
            ),
          ),
        ],
      ),
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      ),
      semanticsLabel: 'AmicUp',
    );
  }
}
