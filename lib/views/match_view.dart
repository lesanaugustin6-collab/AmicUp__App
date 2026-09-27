import 'package:flutter/material.dart';

import 'matches_list_view.dart';

/// Compatibility entry point for the removed embedding-based matching screen.
/// Matches are now represented by the `matches` table and displayed through
/// [MatchesListView].
@Deprecated('Use MatchesListView instead.')
class MatchView extends StatelessWidget {
  const MatchView({super.key, required this.userVector, required this.userId});

  final List<double> userVector;
  final String userId;

  @override
  Widget build(BuildContext context) => const MatchesListView();
}
