import 'package:flutter/material.dart';

import 'discover_view.dart';

/// Compatibility entry point for older imports.
///
/// Discovery now has one maintained implementation: [DiscoverView].
@Deprecated('Use DiscoverView from discover_view.dart instead.')
class DiscoveryView extends StatelessWidget {
  const DiscoveryView({super.key});

  @override
  Widget build(BuildContext context) => const DiscoverView();
}
