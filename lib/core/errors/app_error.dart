import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// User-facing error with a stable domain code. Never surfaces raw Firebase text.
class AppError implements Exception {
  const AppError(this.code, this.message, {this.details});
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  @override
  String toString() => 'AppError($code): $message';

  static AppError from(Object error) {
    if (error is AppError) return error;
    if (error is FirebaseFunctionsException) {
      final details = error.details is Map ? Map<String, dynamic>.from(error.details as Map) : null;
      final code = details?['code'] as String? ?? error.code;
      return AppError(code, copyFor(code, error.message), details: details);
    }
    if (error is FirebaseAuthException) {
      return AppError('auth/${error.code}', authCopy(error.code));
    }
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') return const AppError('permission_denied', "You don't have access to that.");
      if (error.code == 'unavailable') return const AppError('offline', 'You look offline. Check your connection and try again.');
      return AppError(error.code, 'Something went wrong. Please try again.');
    }
    return const AppError('unknown', 'Something went wrong. Please try again.');
  }

  /// Product copy for domain codes (server messages are already friendly, but we keep a fallback map).
  static String copyFor(String code, String? serverMessage) {
    const known = {
      'unauthenticated': 'Sign in to continue.',
      'email_not_verified': 'Verify your college email to continue.',
      'campus_not_supported': "Your college email isn't on a supported campus yet.",
      'not_campus_member': "You're not a member of this campus.",
      'account_suspended': 'Your account is suspended. Contact campus support for help.',
      'permission_denied': "You don't have access to this.",
      'not_found': "We couldn't find that.",
      'event_full': 'This event is full.',
      'already_rsvped': "You're already on the list.",
      'rsvp_closed': 'RSVPs for this event have closed.',
      'event_cancelled': 'This event was cancelled.',
      'checkin_not_active': "Check-in isn't open yet. Ask the organizer to start it.",
      'checkin_window_closed': 'The check-in window for this event has closed.',
      'qr_expired': 'This check-in code has expired. Ask the organizer to refresh the QR.',
      'qr_invalid': "That doesn't look like a CampusBuzz check-in code.",
      'already_checked_in': "You're already checked in.",
      'feedback_requires_checkin': 'Only checked-in attendees can review this event.',
      'already_submitted': "You've already done this.",
      'insufficient_coins': "You don't have enough BuzzCoins yet.",
      'reward_inactive': "This reward isn't available right now.",
      'reward_out_of_stock': 'This reward is sold out.',
      'reward_limit_reached': "You've hit the limit for this reward.",
      'referral_invalid': "That referral code doesn't exist.",
      'self_referral': "You can't refer yourself.",
      'already_referred': 'A referral is already linked to this account.',
      'feature_disabled': "This isn't enabled on your campus yet.",
      'quest_not_live': "This quest isn't live right now.",
      'quest_full': 'This quest is full.',
      'quest_not_eligible': "This quest isn't open to you.",
      'internal': 'Something went wrong on our side. Please try again.',
      'unavailable': 'You look offline. Check your connection and try again.',
      'deadline-exceeded': 'That took too long. Please try again.',
    };
    if (serverMessage != null && serverMessage.isNotEmpty && !serverMessage.startsWith('FirebaseError') && !serverMessage.contains('Exception')) {
      return serverMessage;
    }
    return known[code] ?? 'Something went wrong. Please try again.';
  }

  static String authCopy(String code) => switch (code) {
        'invalid-email' => 'Enter a valid email address.',
        'user-disabled' => 'This account has been disabled. Contact campus support.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' => "That email and password don't match.",
        'email-already-in-use' => 'An account already exists for this email. Sign in instead.',
        'weak-password' => 'Use at least 8 characters with a number.',
        'too-many-requests' => 'Too many attempts. Wait a minute and try again.',
        'network-request-failed' => 'You look offline. Check your connection and try again.',
        _ => 'Something went wrong signing you in. Please try again.',
      };
}
