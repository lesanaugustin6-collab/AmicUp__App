import 'dart:convert';
import '../constants/app_constants.dart';

/// Reads both signup question/answer lists and editor prompt-key maps.
Map<String, String> decodeProfilePrompts(dynamic value) {
  if (value is String) {
    try {
      return decodeProfilePrompts(jsonDecode(value));
    } on FormatException {
      return {};
    }
  }
  final answers = <String, String>{};
  void add(dynamic question, dynamic answer) {
    if (question is! String || answer is! String) return;
    final questions = AppConstants.lockedPromptQuestions;
    final index = questions.indexOf(question.trim());
    final key = index >= 0 ? 'prompt_${index + 1}' : question.trim();
    if (RegExp(r'^prompt_[1-3]$').hasMatch(key)) {
      answers[key] = answer.trim();
    }
  }

  if (value is Map) {
    value.forEach(add);
  } else if (value is List) {
    for (final entry in value) {
      if (entry is Map) add(entry['question'], entry['answer']);
    }
  }
  return answers;
}

/// Reads native profile arrays and legacy JSON/comma-separated text.
List<String> decodeProfileList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return const [];
  try {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return decoded
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
    }
  } on FormatException {
    // Older clients may have saved comma-separated text.
  }
  return text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

/// Keeps arrays as lists for the Supabase request serializer. JSON-encoding
/// here would double-encode them into strings and cause PostgreSQL 22P02.
List<String> encodeProfileList(Iterable<String> values) => values
    .map((value) => value.trim())
    .where((value) => value.isNotEmpty)
    .toList();
