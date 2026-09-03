/// Feature flags (product phases). Separate from economy config by design.
enum FeatureFlag {
  discoveryEnabled('discovery_enabled', true),
  searchEnabled('search_enabled', true),
  tribesEnabled('tribes_enabled', true),
  buzzcoinsEnabled('buzzcoins_enabled', true),
  qrCheckinEnabled('qr_checkin_enabled', true),
  rewardsEnabled('rewards_enabled', true),
  streaksEnabled('streaks_enabled', true),
  tribeLeaderboardEnabled('tribe_leaderboard_enabled', true),
  referralsEnabled('referrals_enabled', true),
  friendsEnabled('friends_enabled', true),
  personalizedFeedEnabled('personalized_feed_enabled', true),
  reviewsEnabled('reviews_enabled', true),
  socialProofEnabled('social_proof_enabled', true),
  campusBuzzScoreEnabled('campus_buzz_score_enabled', true),
  brandQuestsEnabled('brand_quests_enabled', true),
  brandDashboardEnabled('brand_dashboard_enabled', true),
  intercampusEventsEnabled('intercampus_events_enabled', false),
  premiumOrganizerEnabled('premium_organizer_enabled', true),
  institutionalAnalyticsEnabled('institutional_analytics_enabled', true),
  talentProfileEnabled('talent_profile_enabled', false);

  const FeatureFlag(this.key, this.defaultValue);
  final String key;
  final bool defaultValue;
}
