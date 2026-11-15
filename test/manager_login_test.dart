import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:daily_attendance/core/manager_login.dart';

void main() {
  test('new company codes are 6 valid characters', () {
    final random = Random(1);
    for (var i = 0; i < 200; i++) {
      final code = ManagerLogin.newCompanyCode(random);
      expect(ManagerLogin.isValidCode(code), isTrue, reason: code);
    }
  });

  test('codes reject look-alike characters and wrong lengths', () {
    for (final code in [
      'ABCDE0',
      'ABCDEO',
      'ABCDE1',
      'ABCDEI',
      'ABCDEL',
      'ABC',
      'ABCDEFG',
    ]) {
      expect(ManagerLogin.isValidCode(code), isFalse, reason: code);
    }
  });

  test('the login address ignores case and spaces', () {
    expect(
      ManagerLogin.email(companyCode: ' k7rm 2q', username: ' Ravi '),
      'ravi@k7rm2q.login.daily-attendance-b1b1e.firebaseapp.com',
    );
  });

  test('usernames', () {
    for (final ok in ['ravi', 'ravi.k', 'r2', 'priya-sharma']) {
      expect(ManagerLogin.isValidUsername(ok), isTrue, reason: ok);
    }
    for (final bad in ['', 'r', 'has space', '.ravi', 'ravi@x']) {
      expect(ManagerLogin.isValidUsername(bad), isFalse, reason: bad);
    }
  });
}
