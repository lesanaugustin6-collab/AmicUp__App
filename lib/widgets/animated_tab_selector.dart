import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/amicup_motion.dart';

/// Presentation-only selector; the parent retains ownership of tab state.
class AnimatedTabSelector extends StatelessWidget {
  const AnimatedTabSelector({
    super.key,
    required this.labels,
    required this.icons,
    required this.selectedIndex,
    required this.onSelected,
  }) : assert(labels.length > 1),
       assert(labels.length == icons.length),
       assert(selectedIndex >= 0 && selectedIndex < labels.length);

  final List<String> labels;
  final List<IconData> icons;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final duration = AmicUpMotion.duration(context, AmicUpMotion.standard);
    return AmicUpGlassSurface(
      radius: 24,
      blur: 12,
      color: AppTheme.of(context).surfaceMuted.withValues(alpha: 0.74),
      borderColor: AppTheme.of(context).line.withValues(alpha: 0.55),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedAlign(
                    duration: duration,
                    curve: AmicUpMotion.curve,
                    alignment: AlignmentDirectional(
                      -1 + 2 * selectedIndex / (labels.length - 1),
                      0,
                    ),
                    child: FractionallySizedBox(
                      widthFactor: 1 / labels.length,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTheme.of(
                            context,
                          ).violet.withValues(alpha: 0.94),
                          border: Border.all(
                            color: AppTheme.of(
                              context,
                            ).onAccent.withValues(alpha: 0.16),
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: List.generate(labels.length, (index) {
                  final selected = selectedIndex == index;
                  final color = selected
                      ? AppTheme.of(context).onAccent
                      : AppTheme.of(context).muted;
                  return Expanded(
                    child: Semantics(
                      selected: selected,
                      button: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => onSelected(index),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(icons[index], size: 20, color: color),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    labels[index],
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: color,
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
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
