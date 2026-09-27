import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../viewmodels/settings_view_model.dart';
import 'appearance_view.dart';
import 'edit_profile_view.dart';
import 'blocked_profiles_view.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SettingsViewModel()..loadSettings(),
      child: const _SettingsViewBody(),
    );
  }
}

class _SettingsViewBody extends StatelessWidget {
  const _SettingsViewBody();

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    SettingsViewModel viewModel,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This will remove your profile and settings. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: AppTheme.of(context).onAccent,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    await viewModel.deleteAccount(context);
  }

  @override
  Widget build(BuildContext context) {
    final userEmail =
        Supabase.instance.client.auth.currentUser?.email ?? 'Not available';

    return Consumer<SettingsViewModel>(
      builder: (context, viewModel, _) {
        if (viewModel.isLoading) {
          return Scaffold(
            backgroundColor: AppTheme.of(context).canvas,
            body: Center(
              child: CircularProgressIndicator(
                color: AppTheme.of(context).violetStrong,
              ),
            ),
          );
        }

        final ageRange = viewModel.ageRange;

        return Scaffold(
          backgroundColor: AppTheme.of(context).canvas,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppTheme.of(context).ink,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              'Settings and privacy',
              style: TextStyle(
                color: AppTheme.of(context).ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            centerTitle: false,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _SectionCard(
                  title: 'Account',
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Edit profile'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EditProfileView(),
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Email'),
                      subtitle: Text(userEmail),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Delete Account',
                        style: TextStyle(color: Colors.red),
                      ),
                      trailing: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                      ),
                      onTap: () => _confirmDeleteAccount(context, viewModel),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Appearance',
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Themes and dark mode'),
                      subtitle: const Text(
                        'Accent colors · Light, dark, or device setting',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AppearanceView(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Discovery',
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Age range'),
                          Text(
                            '${ageRange.start.round()} - ${ageRange.end.round()} years',
                            style: TextStyle(
                              color: AppTheme.of(context).violetStrong,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    RangeSlider(
                      values: ageRange,
                      min: 18,
                      max: 99,
                      divisions: 81,
                      labels: RangeLabels(
                        ageRange.start.round().toString(),
                        ageRange.end.round().toString(),
                      ),
                      activeColor: AppTheme.of(context).violet,
                      onChanged: (value) => viewModel.setAgeRange(value),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Notifications',
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Push notifications'),
                      value: viewModel.pushNotifications,
                      onChanged: (value) =>
                          viewModel.setPushNotifications(value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Connection notifications'),
                      value: viewModel.matchNotifications,
                      onChanged: (value) =>
                          viewModel.setMatchNotifications(value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Message notifications'),
                      value: viewModel.messageNotifications,
                      onChanged: (value) =>
                          viewModel.setMessageNotifications(value),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Privacy',
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show friends list'),
                      subtitle: const Text(
                        'Let others see who your friends are. Your friends count stays visible.',
                      ),
                      value: viewModel.showFriendsList,
                      onChanged: viewModel.savingFriendsPrivacy
                          ? null
                          : viewModel.setShowFriendsList,
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Pause profile'),
                      subtitle: const Text(
                        'Take a break from being discovered.',
                      ),
                      value: viewModel.pauseProfile,
                      onChanged: viewModel.setPauseProfile,
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Incognito mode'),
                      subtitle: const Text(
                        'Hide your profile from discovery while active.',
                      ),
                      value: viewModel.incognitoMode,
                      onChanged: (value) => viewModel.setIncognitoMode(value),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.block_outlined),
                      title: const Text('Blocked accounts'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BlockedProfilesView(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'About',
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.info_outline),
                      title: const Text('AmicUp'),
                      subtitle: const Text(
                        'Find friends. Make plans. Stay connected.',
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Open-source licenses'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'AmicUp',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Center(
                    child: TextButton(
                      onPressed: () => viewModel.signOut(context),
                      child: const Text(
                        'Log Out',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                if (viewModel.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      viewModel.errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.of(context).surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.of(context).line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.of(context).ink,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
