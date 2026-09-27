import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/profile_field_codec.dart';

class EditCategoryView extends StatefulWidget {
  const EditCategoryView({
    super.key,
    required this.categoryName,
    required this.availableOptions,
    required this.currentSelections,
    this.minSelection = 2,
    this.maxSelection = 6,
  });

  final String categoryName;
  final List<String> availableOptions;
  final List<String> currentSelections;
  final int minSelection;
  final int maxSelection;

  @override
  State<EditCategoryView> createState() => _EditCategoryViewState();
}

class _EditCategoryViewState extends State<EditCategoryView> {
  late final List<String> _selected = List<String>.from(
    widget.currentSelections,
  );
  bool _saving = false;

  String get _databaseColumn {
    final key = widget.categoryName.trim().toLowerCase();
    switch (key) {
      case 'social vibe':
      case 'social_vibe':
      case 'social-vibe':
        return 'social_vibe';
      case 'sports':
      case 'hobbies':
      case 'music':
      case 'lifestyle':
        return key;
      default:
        return key
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'^_|_$'), '');
    }
  }

  Future<void> _saveCategory() async {
    if (_selected.length < widget.minSelection) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select at least ${widget.minSelection} ${widget.categoryName.toLowerCase()} options.',
          ),
        ),
      );
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to update preferences.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({_databaseColumn: encodeProfileList(_selected)})
          .eq('id', userId);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save ${widget.categoryName}: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _toggleOption(String option) {
    final isSelected = _selected.contains(option);

    if (isSelected) {
      setState(() => _selected.remove(option));
      return;
    }

    if (_selected.length >= widget.maxSelection) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You can choose up to ${widget.maxSelection} options in ${widget.categoryName}.',
          ),
        ),
      );
      return;
    }

    setState(() => _selected.add(option));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveCategory,
            child: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select ${widget.minSelection}-${widget.maxSelection} options',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '${_selected.length} selected',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.of(context).ink,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    children: widget.availableOptions.map((option) {
                      final selected = _selected.contains(option);
                      return FilterChip(
                        label: Text(option),
                        selected: selected,
                        onSelected: (_) => _toggleOption(option),
                        selectedColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.18),
                        checkmarkColor: Theme.of(context).colorScheme.primary,
                        showCheckmark: true,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
