import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Searchable country picker shared with profile editing.
class CountryPickerField extends StatelessWidget {
  const CountryPickerField({
    super.key,
    required this.country,
    required this.onChanged,
  });

  final String country;
  final ValueChanged<String> onChanged;

  Future<void> _pickCountry(BuildContext context) async {
    var query = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = AppConstants.worldCountries
              .where((item) => item.toLowerCase().contains(query.toLowerCase()))
              .toList();
          final availableHeight =
              MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom -
              190;
          return AlertDialog(
            title: const Text('Choose your country'),
            content: SizedBox(
              width: double.maxFinite,
              height: availableHeight.clamp(160.0, 360.0),
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search countries',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No countries found'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) => ListTile(
                              title: Text(filtered[index]),
                              onTap: () =>
                                  Navigator.pop(dialogContext, filtered[index]),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _pickCountry(context),
    borderRadius: BorderRadius.circular(4),
    child: InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Country',
        border: OutlineInputBorder(),
        suffixIcon: Icon(Icons.arrow_drop_down_rounded),
      ),
      child: Text(country.isEmpty ? 'Choose country' : country),
    ),
  );
}
