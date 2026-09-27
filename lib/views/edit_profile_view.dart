import 'dart:io';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../utils/profile_field_codec.dart';
import '../widgets/avatar_preview.dart';
import '../widgets/country_picker_field.dart';
import '../widgets/language_picker_field.dart';

class EditProfileView extends StatefulWidget {
  const EditProfileView({super.key, this.userId});

  final String? userId;

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _PromptEntry {
  _PromptEntry({required this.question, required this.answer});

  String question;
  String answer;
}

class _EditProfileViewState extends State<EditProfileView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  final List<String> _matchIntentOptions = [
    'Friendship',
    'Hanging Out',
    'Networking',
    'Activities',
    'Coffee / Brunch',
  ];

  final List<String> _promptTemplates = AppConstants.lockedPromptQuestions;
  final List<String> _defaultInterestOptions =
      AppConstants.defaultInterestOptions;
  final List<String> _lockedPromptKeys = <String>[
    'prompt_1',
    'prompt_2',
    'prompt_3',
  ];

  bool _loading = true;
  bool _saving = false;
  bool _avatarLoading = false;
  bool _galleryLoading = false;

  String? _avatarUrl;
  List<String> _galleryPhotos = const [];
  String _matchIntent = 'Friendship';
  String _country = '';
  final List<String> _sports = [];
  final List<String> _hobbies = [];
  final List<String> _music = [];
  final List<String> _lifestyle = [];
  final List<String> _languages = [];
  final Map<String, String> _promptMap = {};
  final List<_PromptEntry> _promptEntries = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _usernameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final currentUserId = widget.userId ?? _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', currentUserId)
          .maybeSingle();

      if (!mounted) return;
      if (data == null) {
        setState(() => _loading = false);
        return;
      }

      final map = Map<String, dynamic>.from(data);
      final gallery = _listFromField(map['gallery_photos']);

      _bioController.text = (map['bio'] ?? '').toString();
      _usernameController.text = (map['username'] ?? '').toString();
      _locationController.text = (map['location'] ?? map['city'] ?? '')
          .toString();
      _country = (map['country'] ?? '').toString().trim();
      _avatarUrl = (map['avatar_url'] ?? '').toString();
      _galleryPhotos = gallery;
      _matchIntent =
          _matchIntentOptions.contains(map['match_intent']?.toString())
          ? map['match_intent'].toString()
          : 'Friendship';

      _sports
        ..clear()
        ..addAll(_listFromField(map['sports']));
      _hobbies
        ..clear()
        ..addAll(_listFromField(map['hobbies']));
      _music
        ..clear()
        ..addAll(_listFromField(map['music']));
      _lifestyle
        ..clear()
        ..addAll(_listFromField(map['lifestyle']));
      _languages
        ..clear()
        ..addAll(_listFromField(map['languages']).toSet());

      _promptMap.clear();
      _promptEntries.clear();

      final normalizedPromptAnswers = decodeProfilePrompts(map['prompts']);

      for (var index = 0; index < _promptTemplates.length; index++) {
        final key = _lockedPromptKeys[index];
        final answer = normalizedPromptAnswers[key] ?? '';
        _promptMap[key] = answer;
        _promptEntries.add(
          _PromptEntry(question: _promptTemplates[index], answer: answer),
        );
      }

      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<String> _listFromField(dynamic value) => decodeProfileList(value);

  Future<void> _pickAvatar() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _avatarLoading = true);
    try {
      final url = await _uploadImage(file: File(picked.path), isAvatar: true);
      if (url != null && url.isNotEmpty) {
        setState(() => _avatarUrl = url);
      }
    } finally {
      if (mounted) {
        setState(() => _avatarLoading = false);
      }
    }
  }

  Future<void> _addGalleryPhoto() async {
    if (_galleryPhotos.length >= 6) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can add up to 6 photos.')),
      );
      return;
    }

    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _galleryLoading = true);
    try {
      final url = await _uploadImage(file: File(picked.path), isAvatar: false);
      if (url != null && url.isNotEmpty) {
        setState(() => _galleryPhotos = [..._galleryPhotos, url]);
      }
    } finally {
      if (mounted) {
        setState(() => _galleryLoading = false);
      }
    }
  }

  Future<String?> _uploadImage({
    required File file,
    required bool isAvatar,
  }) async {
    final userId = widget.userId ?? _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return null;

    final fileExt = file.path.split('.').last.toLowerCase();
    final storagePath = isAvatar
        ? 'avatars/$userId/${DateTime.now().millisecondsSinceEpoch}.$fileExt'
        : '$userId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    const bucket = 'profiles';

    try {
      await _supabase.storage.from(bucket).upload(storagePath, file);
      return _supabase.storage.from(bucket).getPublicUrl(storagePath);
    } catch (error) {
      debugPrint('Upload failed: $error');
      return null;
    }
  }

  void _removeGalleryPhoto(String url) {
    if (_galleryPhotos.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least 2 profile photos.')),
      );
      return;
    }
    setState(() {
      _galleryPhotos.remove(url);
    });
  }

  void _addInterest(String group, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    switch (group) {
      case 'sports':
        if (!_sports.contains(trimmed)) _sports.add(trimmed);
        break;
      case 'hobbies':
        if (!_hobbies.contains(trimmed)) _hobbies.add(trimmed);
        break;
      case 'music':
        if (!_music.contains(trimmed)) _music.add(trimmed);
        break;
      case 'lifestyle':
        if (!_lifestyle.contains(trimmed)) _lifestyle.add(trimmed);
        break;
    }
    setState(() {});
  }

  void _removeInterest(String group, String value) {
    switch (group) {
      case 'sports':
        _sports.remove(value);
        break;
      case 'hobbies':
        _hobbies.remove(value);
        break;
      case 'music':
        _music.remove(value);
        break;
      case 'lifestyle':
        _lifestyle.remove(value);
        break;
    }
    setState(() {});
  }

  Future<void> _saveProfile() async {
    final userId = widget.userId ?? _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No active user found.')));
      return;
    }

    if (_galleryPhotos.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least 2 profile photos.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final nextUsername = _usernameController.text.trim();
      final currentProfile = await _supabase
          .from('profiles')
          .select('username, last_username_change_at, username_change_count')
          .eq('id', userId)
          .maybeSingle();

      final previousUsername = (currentProfile?['username'] ?? '').toString();
      final lastChangeValue = currentProfile?['last_username_change_at'];
      final lastChange = lastChangeValue is String && lastChangeValue.isNotEmpty
          ? DateTime.tryParse(lastChangeValue)
          : null;
      final changeCount = currentProfile?['username_change_count'] is num
          ? (currentProfile!['username_change_count'] as num).toInt()
          : 0;

      if (nextUsername.isNotEmpty && nextUsername != previousUsername) {
        final isTaken = await _supabase
            .from('profiles')
            .select('id')
            .eq('username', nextUsername)
            .maybeSingle();

        if (isTaken != null && (isTaken['id']?.toString() ?? '') != userId) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This username is already taken.')),
          );
          setState(() => _saving = false);
          return;
        }

        final now = DateTime.now();
        final within14Days =
            lastChange != null && now.difference(lastChange).inDays < 14;
        if (within14Days && changeCount >= 2) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Username can only be changed 2 times every 14 days.',
              ),
            ),
          );
          setState(() => _saving = false);
          return;
        }
      }

      final promptMap = {
        for (var index = 0; index < _lockedPromptKeys.length; index++)
          _lockedPromptKeys[index]: _promptEntries.length > index
              ? _promptEntries[index].answer.trim()
              : '',
      };

      final nextChangeCount =
          nextUsername.isEmpty || nextUsername == previousUsername
          ? (changeCount)
          : ((lastChange != null &&
                    DateTime.now().difference(lastChange).inDays < 14)
                ? changeCount + 1
                : 1);

      await _supabase
          .from('profiles')
          .update({
            'bio': _bioController.text.trim(),
            'username': nextUsername,
            'location': _locationController.text.trim(),
            'country': _country,
            'match_intent': _matchIntent,
            'avatar_url': _avatarUrl ?? '',
            'gallery_photos': encodeProfileList(_galleryPhotos),
            'sports': encodeProfileList(_sports),
            'hobbies': encodeProfileList(_hobbies),
            'music': encodeProfileList(_music),
            'lifestyle': encodeProfileList(_lifestyle),
            'languages': encodeProfileList(_languages),
            'prompts': promptMap,
            if (nextUsername.isNotEmpty && nextUsername != previousUsername)
              'username_change_count': nextChangeCount,
            if (nextUsername.isNotEmpty && nextUsername != previousUsername)
              'last_username_change_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved successfully.')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save profile: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildInterestSection({
    required String title,
    required List<String> items,
    required String group,
  }) {
    final options =
        AppConstants.predefinedInterestMap[group] ?? _defaultInterestOptions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options
              .map(
                (option) => FilterChip(
                  label: Text(option),
                  selected: items.contains(option),
                  onSelected: (selected) {
                    if (selected) {
                      _addInterest(group, option);
                    } else {
                      _removeInterest(group, option);
                    }
                  },
                  selectedColor: AppTheme.of(context).surfaceMuted,
                  backgroundColor: AppTheme.of(context).surfaceMuted,
                  checkmarkColor: AppTheme.of(context).violet,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildPromptEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Icebreakers'),
        ...List.generate(_promptTemplates.length, (index) {
          final promptKey = _lockedPromptKeys[index];
          final promptQuestion = _promptTemplates[index];
          final entry = _promptEntries.asMap().containsKey(index)
              ? _promptEntries[index]
              : _PromptEntry(question: promptQuestion, answer: '');

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  promptQuestion,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: entry.answer,
                  maxLines: 3,
                  minLines: 2,
                  onChanged: (value) {
                    if (_promptEntries.length <= index) {
                      _promptEntries.add(
                        _PromptEntry(question: promptQuestion, answer: value),
                      );
                    } else {
                      _promptEntries[index].answer = value;
                      _promptEntries[index].question = promptQuestion;
                    }
                    _promptMap[promptKey] = value;
                    setState(() {});
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Write your answer',
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _saving ? null : _saveProfile,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: GestureDetector(
                onTap: _avatarUrl == null || _avatarUrl!.isEmpty
                    ? _pickAvatar
                    : () =>
                          showAvatarPreview(context, NetworkImage(_avatarUrl!)),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: AppTheme.of(context).surfaceMuted,
                      backgroundImage:
                          _avatarUrl != null && _avatarUrl!.isNotEmpty
                          ? NetworkImage(_avatarUrl!)
                          : null,
                      child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                          ? Icon(
                              Icons.person,
                              size: 52,
                              color: AppTheme.of(context).violetStrong,
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _avatarLoading ? null : _pickAvatar,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.of(context).violet,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(
                            _avatarLoading
                                ? Icons.hourglass_top
                                : Icons.camera_alt,
                            size: 16,
                            color: AppTheme.of(context).onAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            CountryPickerField(
              country: _country,
              onChanged: (value) => setState(() => _country = value),
            ),
            const SizedBox(height: 16),
            LanguagePickerField(
              selectedLanguages: _languages,
              onChanged: (values) => setState(() {
                _languages
                  ..clear()
                  ..addAll(values);
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _matchIntentOptions.contains(_matchIntent)
                  ? _matchIntent
                  : _matchIntentOptions.first,
              items: _matchIntentOptions
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _matchIntent = value);
                }
              },
              decoration: const InputDecoration(
                labelText: 'What brings you here?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bioController,
              maxLength: 220,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Bio',
                border: const OutlineInputBorder(),
                counterText: '${_bioController.text.length}/220',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionTitle('Gallery'),
                Text(
                  '${_galleryPhotos.length}/6',
                  style: TextStyle(
                    color: AppTheme.of(context).muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Keep at least 2 photos. Add up to 6.',
              style: TextStyle(color: AppTheme.of(context).muted),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ..._galleryPhotos.map(
                  (photoUrl) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.network(
                          photoUrl,
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeGalleryPhoto(photoUrl),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_galleryPhotos.length < 6)
                  GestureDetector(
                    onTap: _galleryLoading ? null : _addGalleryPhoto,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppTheme.of(context).muted,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        color: AppTheme.of(context).surfaceMuted,
                      ),
                      child: Center(
                        child: _galleryLoading
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : const Icon(Icons.add_a_photo, size: 28),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _buildInterestSection(
              title: 'Sports',
              items: _sports,
              group: 'sports',
            ),
            const SizedBox(height: 18),
            _buildInterestSection(
              title: 'Hobbies',
              items: _hobbies,
              group: 'hobbies',
            ),
            const SizedBox(height: 18),
            _buildInterestSection(
              title: 'Music',
              items: _music,
              group: 'music',
            ),
            const SizedBox(height: 18),
            _buildInterestSection(
              title: 'Lifestyle',
              items: _lifestyle,
              group: 'lifestyle',
            ),
            const SizedBox(height: 24),
            _buildPromptEditor(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
