import 'package:campusbuzz/core/errors/app_error.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps server domain codes to product copy, never raw Firebase text', () {
    final e = AppError.from(FirebaseFunctionsException(code: 'deadline-exceeded', message: 'This check-in code has expired. Ask the organizer to refresh the QR.', details: {'code': 'qr_expired'}));
    expect(e.code, 'qr_expired');
    expect(e.message, contains('expired'));
    final generic = AppError.from(FirebaseFunctionsException(code: 'internal', message: 'FirebaseError: something', details: null));
    expect(generic.message, isNot(contains('FirebaseError')));
  });

  test('auth errors get friendly copy', () {
    expect(AppError.from(FirebaseAuthException(code: 'wrong-password')).message, contains("don't match"));
    expect(AppError.from(FirebaseAuthException(code: 'email-already-in-use')).message, contains('already exists'));
    expect(AppError.from(FirebaseAuthException(code: 'weird')).message, isNotEmpty);
  });

  test('insufficient coins copy carries the shortfall from the server', () {
    final e = AppError.from(FirebaseFunctionsException(code: 'failed-precondition', message: 'You need 25 more BuzzCoins for this reward.', details: {'code': 'insufficient_coins', 'shortfall': 25}));
    expect(e.details?['shortfall'], 25);
    expect(e.message, 'You need 25 more BuzzCoins for this reward.');
  });

  test('unknown errors are wrapped', () {
    expect(AppError.from(Exception('x')).code, 'unknown');
    expect(AppError.copyFor('permission_denied', null), "You don't have access to this.");
  });
}
