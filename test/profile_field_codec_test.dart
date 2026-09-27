import 'dart:convert';

import 'package:amicup_app/utils/profile_field_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile request preserves native arrays instead of JSON strings', () {
    final encoded = encodeProfileList([' Hiking ', '', 'Coffee']);

    final request = jsonDecode(jsonEncode({'gallery_photos': encoded}));
    expect(request['gallery_photos'], isA<List>());
    expect(request['gallery_photos'], ['Hiking', 'Coffee']);
    expect(decodeProfileList(encoded), ['Hiking', 'Coffee']);
  });

  test('reads profiles saved by older clients', () {
    expect(decodeProfileList('["Music","Travel"]'), ['Music', 'Travel']);
    expect(decodeProfileList(['Music', 'Travel']), ['Music', 'Travel']);
    expect(decodeProfileList('Music, Travel'), ['Music', 'Travel']);
  });
}
