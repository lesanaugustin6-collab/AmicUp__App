import 'package:flutter/material.dart';

import 'onboarding/onboarding_flow_view.dart';

/// Compatibility entry point for the retired profile-setup wizard.
@Deprecated('Use OnboardingFlowView instead.')
class ProfileSetupView extends StatelessWidget {
  const ProfileSetupView({super.key});

  @override
  Widget build(BuildContext context) =>
      const OnboardingFlowView(initialPage: 1);
}
