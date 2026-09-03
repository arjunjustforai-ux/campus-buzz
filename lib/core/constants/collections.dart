/// Mirror of `functions/src/config/collections.ts`. Keep in sync.
abstract final class Col {
  static const users = 'users';
  static const campuses = 'campuses';
  static const memberships = 'memberships';
  static const tribes = 'tribes';
  static const clubs = 'clubs';
  static const events = 'events';
  static const eventQrSessions = 'event_qr_sessions';
  static const rsvps = 'rsvps';
  static const checkins = 'checkins';
  static const eventFeedback = 'event_feedback';
  static const coinLedger = 'coin_ledger';
  static const coinBalances = 'coin_balances';
  static const participationStats = 'participation_stats';
  static const rewards = 'rewards';
  static const redemptions = 'redemptions';
  static const vendors = 'vendors';
  static const referrals = 'referrals';
  static const friendships = 'friendships';
  static const brandAccounts = 'brand_accounts';
  static const brandMemberships = 'brand_memberships';
  static const quests = 'quests';
  static const questCompletions = 'quest_completions';
  static const notificationJobs = 'notification_jobs';
  static const notificationDeliveryLogs = 'notification_delivery_logs';
  static const surveys = 'surveys';
  static const surveyResponses = 'survey_responses';
  static const pilotMetrics = 'pilot_metrics';
  static const metricsDaily = 'metrics_daily';
  static const featureConfigs = 'feature_configs';
  static const entitlements = 'entitlements';
  static const auditLogs = 'audit_logs';
  static const supportRequests = 'support_requests';
  static const economyVersions = 'economy_versions';
  static const analyticsEvents = 'analytics_events';
  static const contentReports = 'content_reports';
  static const tribeLeaderboards = 'tribe_leaderboards';
}

abstract final class Ids {
  static String membership(String campusId, String uid) => '${campusId}_$uid';
  static String rsvp(String eventId, String uid) => '${eventId}_$uid';
  static String checkin(String eventId, String uid) => '${eventId}_$uid';
  static String feedback(String eventId, String uid) => '${eventId}_$uid';
  static String friendship(String a, String b) => ([a, b]..sort()).join('_');
  static String questCompletion(String questId, String uid) => '${questId}_$uid';
  static String surveyResponse(String surveyId, String uid) => '${surveyId}_$uid';
}
