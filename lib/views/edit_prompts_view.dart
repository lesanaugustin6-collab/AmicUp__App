import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

class EditPromptsView extends StatefulWidget {
  const EditPromptsView({super.key, required this.initialPrompts});

  final List<Map<String, String>> initialPrompts;

  @override
  State<EditPromptsView> createState() => _EditPromptsViewState();
}

class _EditPromptsViewState extends State<EditPromptsView> {
  final List<Map<String, String>> _promptOptions = [
    {'question': 'I’m looking for a friend who...', 'answer': ''},
    {
      'question': 'My ideal way to spend a free afternoon with friends is...',
      'answer': '',
    },
    {'question': 'The fastest way to become my friend is...', 'answer': ''},
    {'question': 'A fun evening for me looks like...', 'answer': ''},
    {'question': 'The best first hangout would be...', 'answer': ''},
    {'question': 'One thing I always want in a new friend is...', 'answer': ''},
  ];

  late final List<Map<String, String>> _prompts;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prompts = List<Map<String, String>>.from(
      widget.initialPrompts.isNotEmpty
          ? widget.initialPrompts
          : List.generate(
              3,
              (index) => {
                'question':
                    _promptOptions[index % _promptOptions.length]['question'] ??
                    '',
                'answer': '',
              },
            ),
    );

    for (var i = 0; i < _prompts.length; i++) {
      final prompt = _prompts[i];
      final question = prompt['question'];
      if (question == null || question.isEmpty) {
        _prompts[i] = {
          'question':
              _promptOptions[i % _promptOptions.length]['question'] ?? '',
          'answer': prompt['answer'] ?? '',
        };
      }
    }
  }

  Future<void> _savePrompts() async {
    final invalidIndex = _prompts.indexWhere((entry) {
      final answer = (entry['answer'] ?? '').trim();
      return answer.isEmpty;
    });

    if (invalidIndex >= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all 3 prompt answers before saving.'),
        ),
      );
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to update your prompts.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await SupabaseService().updateProfilePrompts(
        userId: userId,
        prompts: _prompts
            .map(
              (p) => {
                'question': (p['question'] ?? '').trim(),
                'answer': (p['answer'] ?? '').trim(),
              },
            )
            .toList(),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save prompts: $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversation Starters')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (var i = 0; i < _prompts.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prompt ${i + 1}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue:
                            _prompts[i]['question'] ??
                            _promptOptions[i %
                                _promptOptions.length]['question'],
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Prompt question',
                        ),
                        items: _promptOptions
                            .map(
                              (option) => DropdownMenuItem<String>(
                                value: option['question'],
                                child: Text(
                                  option['question'] ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _prompts[i]['question'] = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: _prompts[i]['answer'] ?? '',
                        maxLines: 4,
                        minLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Answer',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        onChanged: (value) {
                          _prompts[i]['answer'] = value;
                        },
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Answer cannot be empty';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _savePrompts,
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
