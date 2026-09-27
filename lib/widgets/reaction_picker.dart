import 'package:flutter/material.dart';

/// The keyboard supports the device's full emoji set, including joined emoji.
bool isSingleEmoji(String value) {
  final text = value.trim();
  return text.characters.length == 1 &&
      RegExp(
        r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}\u{2190}-\u{21FF}\u{25A0}-\u{25FF}\u{2B00}-\u{2BFF}\u{00A9}\u{00AE}\u{203C}\u{2049}\u{2122}\u{2139}\u{3030}\u{303D}\u{3297}\u{3299}\u{FE0F}\u{20E3}]',
        unicode: true,
      ).hasMatch(text);
}

Future<String?> showReactionPicker(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReactionPicker(),
    );

class _ReactionPicker extends StatefulWidget {
  const _ReactionPicker();
  @override
  State<_ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<_ReactionPicker> {
  final _controller = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (isSingleEmoji(text)) {
      Navigator.pop(context, text);
    } else {
      setState(() => _error = 'Choose one emoji.');
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'React with an emoji',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              children: [
                for (final emoji in [
                  '❤️',
                  '😭',
                  '😂',
                  '😜',
                  '🤗',
                  '🙈',
                  '👍',
                  '👎',
                  '🔥',
                  '🥰',
                  '😍',
                  '😎',
                  '😮',
                  '😢',
                  '😡',
                  '🤔',
                  '😅',
                  '🤣',
                  '🥹',
                  '💜',
                  '👏',
                  '🙏',
                  '💪',
                  '🎉',
                  '✨',
                  '💯',
                  '🤝',
                  '👀',
                  '🫶',
                  '🥳',
                  '🫡',
                  '😴',
                ])
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => Navigator.pop(context, emoji),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 25),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.done,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Any emoji from your keyboard',
                hintText: 'Type or paste an emoji',
                errorText: _error,
                suffixIcon: IconButton(
                  tooltip: 'Use emoji',
                  onPressed: _submit,
                  icon: const Icon(Icons.check_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
