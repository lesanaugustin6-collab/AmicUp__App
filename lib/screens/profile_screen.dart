import 'package:flutter/material.dart';

import '../views/profile_view.dart';

/// Compatibility entry point for the retired profile implementation.
@Deprecated('Use ProfileView instead.')
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => const ProfileView();
}
