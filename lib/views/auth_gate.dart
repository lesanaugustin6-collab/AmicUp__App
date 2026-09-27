import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main_navigation_view.dart';
import 'onboarding/onboarding_flow_view.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;

    if (session == null) {
      return const OnboardingFlowView(initialPage: 0);
    }

    return _AuthenticatedGate(userId: session.user.id);
  }
}

class _AuthenticatedGate extends StatefulWidget {
  const _AuthenticatedGate({required this.userId});

  final String userId;

  @override
  State<_AuthenticatedGate> createState() => _AuthenticatedGateState();
}

class _AuthenticatedGateState extends State<_AuthenticatedGate> {
  Future<Map<String, dynamic>?> _fetchProfile() async {
    final client = Supabase.instance.client;
    final response = await client
        .from('profiles')
        .select()
        .eq('id', widget.userId)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return response;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return const OnboardingFlowView(initialPage: 0);
        }

        final profile = snapshot.data;
        final hasRequiredProfileData =
            profile != null &&
            profile['first_name'] != null &&
            profile['first_name'].toString().trim().isNotEmpty &&
            profile['username'] != null &&
            profile['username'].toString().trim().isNotEmpty;

        if (!hasRequiredProfileData) {
          return const OnboardingFlowView(initialPage: 1);
        }

        return const MainNavigationView();
      },
    );
  }
}
