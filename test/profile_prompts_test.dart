import 'dart:convert';
import 'package:amicup_app/constants/app_constants.dart';
import 'package:amicup_app/utils/profile_field_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Signup answers survive display, editing, and saving', () {
    final signup = [
      for (var i = 0; i < 3; i++)
        {
          'question': AppConstants.lockedPromptQuestions[i],
          'answer': 'Answer $i',
        },
    ];
    final saved = decodeProfilePrompts(signup);
    expect(saved, {
      'prompt_1': 'Answer 0',
      'prompt_2': 'Answer 1',
      'prompt_3': 'Answer 2',
    });
    expect(decodeProfilePrompts(saved), saved);
    expect(decodeProfilePrompts(jsonEncode(signup)), saved);
  });
  test('Legacy keyed lists and missing answers remain safe', () {
    expect(
      decodeProfilePrompts([
        {'question': 'prompt_2', 'answer': ' Hello '},
      ]),
      {'prompt_2': 'Hello'},
    );
    expect(decodeProfilePrompts(null), isEmpty);
    expect(decodeProfilePrompts('invalid'), isEmpty);
    expect(
      decodeProfilePrompts([
        null,
        {'question': 'prompt_1', 'answer': null},
      ]),
      isEmpty,
    );
  });
}
