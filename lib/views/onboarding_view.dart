import 'package:flutter/material.dart';

import 'onboarding/onboarding_flow_view.dart';

/// Compatibility entry point for callers that still reference OnboardingView.
@Deprecated('Use OnboardingFlowView instead.')
class OnboardingView extends StatelessWidget {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) => const OnboardingFlowView();
}
