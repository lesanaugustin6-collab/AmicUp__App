import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

class LanguagePickerField extends StatelessWidget {
  const LanguagePickerField({
    super.key,
    required this.selectedLanguages,
    required this.onChanged,
  });

  final List<String> selectedLanguages;
  final ValueChanged<List<String>> onChanged;

  Future<void> _pickLanguages(BuildContext context) async {
    final selected = selectedLanguages.toSet().toList();
    final options = {...AppConstants.languages, ...selectedLanguages}.toList();
    var query = '';
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final inset = MediaQuery.viewInsetsOf(context).bottom;
          final height = (MediaQuery.sizeOf(context).height - inset - 80).clamp(
            180.0,
            520.0,
          );
          final visible = options
              .where((language) => language.toLowerCase().contains(query))
              .toList();
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: inset),
              child: SizedBox(
                height: height,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Languages',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search languages',
                          prefixIcon: Icon(Icons.search_rounded),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => setSheetState(
                          () => query = value.trim().toLowerCase(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: visible.isEmpty
                          ? const Center(child: Text('No languages found'))
                          : ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final language = visible[index];
                                return CheckboxListTile(
                                  title: Text(language),
                                  value: selected.contains(language),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  onChanged: (checked) => setSheetState(() {
                                    if (checked == true) {
                                      selected.add(language);
                                    } else {
                                      selected.remove(language);
                                    }
                                  }),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            List<String>.of(selected),
                          ),
                          child: Text('Done (${selected.length})'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context);
    return InkWell(
      onTap: () => _pickLanguages(context),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Languages',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          selectedLanguages.isEmpty
              ? 'Choose languages'
              : selectedLanguages.join(', '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selectedLanguages.isEmpty ? colors.muted : colors.ink,
          ),
        ),
      ),
    );
  }
}
