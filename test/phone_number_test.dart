import 'package:flutter_test/flutter_test.dart';

import 'package:daily_attendance/core/phone_number.dart';

void main() {
  test('Indian numbers typed in common ways all come out the same', () {
    for (final typed in [
      '9876543210',
      '98765 43210',
      '98765-43210',
      '09876543210',
      '919876543210',
      '+91 98765 43210',
      '+919876543210',
      '0091 9876543210',
    ]) {
      expect(PhoneNumber.normalize(typed), '+919876543210', reason: typed);
    }
  });

  test('rejects numbers that are not mobiles', () {
    for (final bad in [
      '',
      '12345',
      '987654321', // 9 digits
      '98765432101', // 11 digits
      '5876543210', // Indian mobiles start with 6-9
      '+91 5876543210',
      'ravi',
    ]) {
      expect(PhoneNumber.normalize(bad), isNull, reason: bad);
    }
  });

  test('other countries are kept as typed with their code', () {
    expect(PhoneNumber.normalize('+44 7911 123456'), '+447911123456');
    expect(PhoneNumber.format('+447911123456'), '+447911123456');
  });

  test('Indian numbers are shown in two groups of five', () {
    expect(PhoneNumber.format('+919876543210'), '+91 98765 43210');
  });
}
