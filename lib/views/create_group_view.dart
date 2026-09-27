import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/group_service.dart';
import '../theme/app_theme.dart';

class CreateGroupView extends StatefulWidget {
  const CreateGroupView({super.key});

  @override
  State<CreateGroupView> createState() => _CreateGroupViewState();
}

class _CreateGroupViewState extends State<CreateGroupView> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _rules = TextEditingController();
  final _timerMinutes = TextEditingController();
  final _timerSeconds = TextEditingController();
  final _service = GroupService(Supabase.instance.client);
  final _selectedFriends = <String>{};
  String _visibility = 'private';
  bool _hasMessageTimer = false;
  File? _image;
  late Future<List<Map<String, dynamic>>> _friends;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _friends = _service.friends();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _rules.dispose();
    _timerMinutes.dispose();
    _timerSeconds.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop group picture',
          toolbarColor: AppTheme.of(context).violet,
          toolbarWidgetColor: AppTheme.of(context).onAccent,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Crop group picture',
          aspectRatioLockEnabled: true,
        ),
      ],
    );
    if (cropped != null && mounted) setState(() => _image = File(cropped.path));
  }

  Future<String?> _uploadImage() async {
    final image = _image;
    if (image == null) return null;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await Supabase.instance.client.storage
        .from('group_images')
        .upload(path, image);
    return Supabase.instance.client.storage
        .from('group_images')
        .getPublicUrl(path);
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    final minutes = int.tryParse(_timerMinutes.text.trim()) ?? 0;
    final seconds = int.tryParse(_timerSeconds.text.trim()) ?? 0;
    final cooldown = _hasMessageTimer ? minutes * 60 + seconds : 0;
    if (minutes < 0 ||
        seconds < 0 ||
        seconds > 59 ||
        cooldown > 3600 ||
        (_hasMessageTimer && cooldown <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a timer between 1 second and 1 hour.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final imageUrl = await _uploadImage();
      final id = await _service.create(
        name: _name.text.trim(),
        visibility: _visibility,
        description: _description.text.trim(),
        imageUrl: imageUrl,
        rules: _rules.text.trim(),
        messageCooldownSeconds: cooldown,
        memberIds: _selectedFriends.toList(),
      );
      if (mounted) Navigator.pop(context, id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create group: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create group')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(52),
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 52,
                backgroundColor: AppTheme.of(context).surfaceMuted,
                backgroundImage: _image == null ? null : FileImage(_image!),
                child: _image == null
                    ? Icon(
                        Icons.add_a_photo_outlined,
                        color: AppTheme.of(context).violetStrong,
                        size: 30,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _visibility == 'public' ? 'Channel picture' : 'Group picture',
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _name,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Name *'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'A name is required.'
                : null,
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'private',
                icon: Icon(Icons.lock_outline),
                label: Text('Private group'),
              ),
              ButtonSegment(
                value: 'public',
                icon: Icon(Icons.public),
                label: Text('Public channel'),
              ),
            ],
            selected: {_visibility},
            onSelectionChanged: (value) =>
                setState(() => _visibility = value.first),
          ),
          const SizedBox(height: 12),
          Text(
            _visibility == 'public'
                ? 'Anyone can find and join this channel.'
                : 'Only members can see this group. Invite friends below.',
            style: TextStyle(color: AppTheme.of(context).muted),
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _description,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'About (optional)'),
          ),
          TextFormField(
            controller: _rules,
            maxLines: 4,
            maxLength: 3000,
            decoration: const InputDecoration(
              labelText: 'Rules and policies (optional)',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Message timer',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(_hasMessageTimer ? 'Timer enabled' : 'No time limit'),
            subtitle: const Text('Set the exact wait between messages.'),
            value: _hasMessageTimer,
            onChanged: (value) => setState(() => _hasMessageTimer = value),
          ),
          if (_hasMessageTimer)
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _timerMinutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minutes',
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _timerSeconds,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Seconds'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          const Text(
            'Add friends',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _friends,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.data!.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Connect with friends first, then you can add them here.',
                  ),
                );
              }
              return Column(
                children: snapshot.data!.map((friend) {
                  final id = friend['id'].toString();
                  final name = [
                    friend['first_name'],
                    friend['last_name'],
                  ].whereType<String>().where((e) => e.isNotEmpty).join(' ');
                  return CheckboxListTile(
                    value: _selectedFriends.contains(id),
                    onChanged: (selected) => setState(
                      () => selected == true
                          ? _selectedFriends.add(id)
                          : _selectedFriends.remove(id),
                    ),
                    title: Text(
                      name.isEmpty
                          ? friend['username']?.toString() ?? 'Member'
                          : name,
                    ),
                    secondary: CircleAvatar(
                      backgroundImage: friend['avatar_url'] == null
                          ? null
                          : NetworkImage(friend['avatar_url'].toString()),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _create,
            child: Text(
              _saving
                  ? 'Creating…'
                  : _visibility == 'public'
                  ? 'Create channel'
                  : 'Create group',
            ),
          ),
        ],
      ),
    ),
  );
}
