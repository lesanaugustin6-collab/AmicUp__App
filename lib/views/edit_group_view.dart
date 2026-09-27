import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/group_service.dart';
import '../theme/app_theme.dart';

class EditGroupView extends StatefulWidget {
  const EditGroupView({super.key, required this.channel});
  final Map<String, dynamic> channel;

  @override
  State<EditGroupView> createState() => _EditGroupViewState();
}

class _EditGroupViewState extends State<EditGroupView> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.channel['name']?.toString() ?? '');
  late final _about = TextEditingController(text: widget.channel['description']?.toString() ?? '');
  late final _rules = TextEditingController(text: widget.channel['rules']?.toString() ?? '');
  late final _minutes = TextEditingController(text: (((widget.channel['message_cooldown_seconds'] as num?)?.toInt() ?? 0) ~/ 60).toString());
  late final _seconds = TextEditingController(text: (((widget.channel['message_cooldown_seconds'] as num?)?.toInt() ?? 0) % 60).toString());
  late bool _timerEnabled = ((widget.channel['message_cooldown_seconds'] as num?)?.toInt() ?? 0) > 0;
  final _groups = GroupService(Supabase.instance.client);
  File? _image;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose(); _about.dispose(); _rules.dispose(); _minutes.dispose(); _seconds.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(toolbarTitle: 'Crop group picture', toolbarColor: AppTheme.of(context).violet, toolbarWidgetColor: AppTheme.of(context).onAccent, lockAspectRatio: true),
        IOSUiSettings(title: 'Crop group picture', aspectRatioLockEnabled: true),
      ],
    );
    if (cropped != null && mounted) setState(() => _image = File(cropped.path));
  }

  Future<String?> _uploadImage() async {
    if (_image == null) return widget.channel['image_url']?.toString();
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await Supabase.instance.client.storage.from('group_images').upload(path, _image!);
    return Supabase.instance.client.storage.from('group_images').getPublicUrl(path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    final minutes = int.tryParse(_minutes.text.trim()) ?? 0;
    final seconds = int.tryParse(_seconds.text.trim()) ?? 0;
    final cooldown = _timerEnabled ? minutes * 60 + seconds : 0;
    if (minutes < 0 || seconds < 0 || seconds > 59 || cooldown > 3600 || (_timerEnabled && cooldown == 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a timer between 1 second and 1 hour.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _groups.updateGroup(
        channelId: widget.channel['id'].toString(),
        name: _name.text.trim(), description: _about.text.trim(), rules: _rules.text.trim(),
        messageCooldownSeconds: cooldown, imageUrl: await _uploadImage(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save group: $error')));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit group')),
    body: Form(
      key: _formKey,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: InkWell(onTap: _pickImage, borderRadius: BorderRadius.circular(52), child: CircleAvatar(radius: 52, backgroundColor: AppTheme.of(context).surfaceMuted, backgroundImage: _image != null ? FileImage(_image!) : widget.channel['image_url'] == null ? null : NetworkImage(widget.channel['image_url'].toString()), child: _image == null && widget.channel['image_url'] == null ? const Icon(Icons.add_a_photo_outlined) : null))),
        const SizedBox(height: 20),
        TextFormField(controller: _name, maxLength: 60, decoration: const InputDecoration(labelText: 'Name *'), validator: (value) => value == null || value.trim().isEmpty ? 'A name is required.' : null),
        TextFormField(controller: _about, maxLength: 300, maxLines: 3, decoration: const InputDecoration(labelText: 'About (optional)')),
        TextFormField(controller: _rules, maxLength: 3000, maxLines: 5, decoration: const InputDecoration(labelText: 'Rules and policies (optional)')),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: Text(_timerEnabled ? 'Message timer enabled' : 'No time limit'), value: _timerEnabled, onChanged: (value) => setState(() => _timerEnabled = value)),
        if (_timerEnabled) Row(children: [Expanded(child: TextFormField(controller: _minutes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutes'))), const SizedBox(width: 12), Expanded(child: TextFormField(controller: _seconds, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Seconds')))]),
        const SizedBox(height: 20),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save changes')),
      ]),
    ),
  );
}
