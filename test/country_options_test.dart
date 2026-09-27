import 'package:amicup_app/constants/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Moldova is available in the onboarding country list', () {
    expect(AppConstants.worldCountries, contains('Moldova'));
    expect(
      AppConstants.worldCountries.indexOf('Moldova'),
      lessThan(AppConstants.worldCountries.indexOf('Romania')),
    );
  });
}
