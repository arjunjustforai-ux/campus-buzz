/// Immutable Firestore document models. Field names mirror
/// `functions/src` and `docs/DATA_MODEL.md`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/formatting.dart';

typedef Json = Map<String, dynamic>;

Json _data(DocumentSnapshot d) => (d.data() as Map<String, dynamic>?) ?? const {};
List<String> _strList(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : const [];
Map<String, num> _numMap(dynamic v) => v is Map ? v.map((k, val) => MapEntry(k.toString(), (val as num?) ?? 0)) : const {};
int _int(dynamic v) => (v as num?)?.toInt() ?? 0;
double _dbl(dynamic v) => (v as num?)?.toDouble() ?? 0;

enum Role { student, organizer, ambassador, campusAdmin, brand, vendor, superAdmin;
  static Role? parse(String s) => switch (s) {
        'student' => Role.student, 'organizer' => Role.organizer, 'ambassador' => Role.ambassador,
        'campus_admin' => Role.campusAdmin, 'brand' => Role.brand, 'vendor' => Role.vendor, 'super_admin' => Role.superAdmin, _ => null,
      };
  String get wire => switch (this) { Role.campusAdmin => 'campus_admin', Role.superAdmin => 'super_admin', _ => name };
  String get label => switch (this) {
        Role.student => 'Student', Role.organizer => 'Organizer', Role.ambassador => 'Ambassador', Role.campusAdmin => 'Campus Ops',
        Role.brand => 'Brand', Role.vendor => 'Redemption partner', Role.superAdmin => 'Super admin',
      };
}

class EconomyConfig {
  const EconomyConfig({this.version = 1, this.rsvpReward = 5, this.checkinReward = 20, this.feedbackReward = 10, this.referralReward = 25, this.organizerReward = 50, this.organizerMinVerifiedAttendees = 10, this.streakThresholdWeeks = 3, this.streakMultiplier = 2, this.coinExpiryDays = 90, this.engagementNotificationCapPerDay = 2, this.checkinOpensMinutesBefore = 30, this.description = ''});
  final int version, rsvpReward, checkinReward, feedbackReward, referralReward, organizerReward, organizerMinVerifiedAttendees, streakThresholdWeeks, streakMultiplier, coinExpiryDays, engagementNotificationCapPerDay, checkinOpensMinutesBefore;
  final String description;
  factory EconomyConfig.fromJson(Json? j) => j == null ? const EconomyConfig() : EconomyConfig(
        version: _int(j['version']).clamp(1, 1 << 30), rsvpReward: j['rsvpReward'] == null ? 5 : _int(j['rsvpReward']), checkinReward: j['checkinReward'] == null ? 20 : _int(j['checkinReward']),
        feedbackReward: j['feedbackReward'] == null ? 10 : _int(j['feedbackReward']), referralReward: j['referralReward'] == null ? 25 : _int(j['referralReward']), organizerReward: j['organizerReward'] == null ? 50 : _int(j['organizerReward']),
        organizerMinVerifiedAttendees: j['organizerMinVerifiedAttendees'] == null ? 10 : _int(j['organizerMinVerifiedAttendees']), streakThresholdWeeks: j['streakThresholdWeeks'] == null ? 3 : _int(j['streakThresholdWeeks']),
        streakMultiplier: j['streakMultiplier'] == null ? 2 : _int(j['streakMultiplier']), coinExpiryDays: j['coinExpiryDays'] == null ? 90 : _int(j['coinExpiryDays']),
        engagementNotificationCapPerDay: j['engagementNotificationCapPerDay'] == null ? 2 : _int(j['engagementNotificationCapPerDay']), checkinOpensMinutesBefore: j['checkinOpensMinutesBefore'] == null ? 30 : _int(j['checkinOpensMinutesBefore']), description: j['description'] as String? ?? '');
  Json toJson() => {'rsvpReward': rsvpReward, 'checkinReward': checkinReward, 'feedbackReward': feedbackReward, 'referralReward': referralReward, 'organizerReward': organizerReward, 'organizerMinVerifiedAttendees': organizerMinVerifiedAttendees, 'streakThresholdWeeks': streakThresholdWeeks, 'streakMultiplier': streakMultiplier, 'coinExpiryDays': coinExpiryDays, 'engagementNotificationCapPerDay': engagementNotificationCapPerDay, 'checkinOpensMinutesBefore': checkinOpensMinutesBefore};
}

class Campus {
  const Campus({required this.id, required this.name, required this.shortName, required this.domains, required this.timezone, required this.economy, required this.featureFlags, required this.status, this.city = '', this.pilot = const {}, this.privacyPolicyUrl, this.termsUrl});
  final String id, name, shortName, timezone, status, city;
  final List<String> domains;
  final EconomyConfig economy;
  final Map<String, bool> featureFlags;
  final Json pilot;
  final String? privacyPolicyUrl, termsUrl;
  factory Campus.fromDoc(DocumentSnapshot d) { final j = _data(d); return Campus(id: d.id, name: j['name'] as String? ?? d.id, shortName: j['shortName'] as String? ?? j['name'] as String? ?? d.id, domains: _strList(j['domains']), timezone: j['timezone'] as String? ?? 'Asia/Kolkata', economy: EconomyConfig.fromJson(j['economy'] as Json?), featureFlags: (j['featureFlags'] as Map?)?.map((k, v) => MapEntry(k.toString(), v == true)) ?? const {}, status: j['status'] as String? ?? 'active', city: j['city'] as String? ?? '', pilot: (j['pilot'] as Map?)?.cast<String, dynamic>() ?? const {}, privacyPolicyUrl: j['privacyPolicyUrl'] as String?, termsUrl: j['termsUrl'] as String?); }
}

class Tribe {
  const Tribe({required this.id, required this.campusId, required this.name, this.emoji = '', this.color = '#FF5F1F', this.description = '', this.order = 0, this.active = true});
  final String id, campusId, name, emoji, color, description; final int order; final bool active;
  factory Tribe.fromDoc(DocumentSnapshot d) { final j = _data(d); return Tribe(id: d.id, campusId: j['campusId'] as String? ?? '', name: j['name'] as String? ?? d.id, emoji: j['emoji'] as String? ?? '', color: j['color'] as String? ?? '#FF5F1F', description: j['description'] as String? ?? '', order: _int(j['order']), active: j['active'] != false); }
}

class Club {
  const Club({required this.id, required this.campusId, required this.name, this.description = '', this.category = '', this.logoUrl, this.adminUids = const [], this.status = 'active'});
  final String id, campusId, name, description, category, status; final String? logoUrl; final List<String> adminUids;
  factory Club.fromDoc(DocumentSnapshot d) { final j = _data(d); return Club(id: d.id, campusId: j['campusId'] as String? ?? '', name: j['name'] as String? ?? d.id, description: j['description'] as String? ?? '', category: j['category'] as String? ?? '', logoUrl: j['logoUrl'] as String?, adminUids: _strList(j['adminUids']), status: j['status'] as String? ?? 'active'); }
}

class EventStats {
  const EventStats({this.rsvpCount = 0, this.waitlistCount = 0, this.checkinCount = 0, this.manualCheckinCount = 0, this.feedbackCount = 0, this.ratingAvg = 0, this.ratingDist = const {}});
  final int rsvpCount, waitlistCount, checkinCount, manualCheckinCount, feedbackCount; final double ratingAvg; final Map<String, num> ratingDist;
  factory EventStats.fromJson(Json? j) => j == null ? const EventStats() : EventStats(rsvpCount: _int(j['rsvpCount']), waitlistCount: _int(j['waitlistCount']), checkinCount: _int(j['checkinCount']), manualCheckinCount: _int(j['manualCheckinCount']), feedbackCount: _int(j['feedbackCount']), ratingAvg: _dbl(j['ratingAvg']), ratingDist: _numMap(j['ratingDist']));
  double get conversion => rsvpCount == 0 ? 0 : checkinCount / rsvpCount * 100;
}

class EventLocation {
  const EventLocation({required this.name, this.address = '', this.lat, this.lng});
  final String name, address; final double? lat, lng;
  factory EventLocation.fromJson(Json? j) => EventLocation(name: j?['name'] as String? ?? '', address: j?['address'] as String? ?? '', lat: (j?['lat'] as num?)?.toDouble(), lng: (j?['lng'] as num?)?.toDouble());
  Json toJson() => {'name': name, 'address': address, 'lat': lat, 'lng': lng};
}

class Event {
  const Event({required this.id, required this.campusId, required this.participatingCampusIds, required this.clubId, required this.clubName, required this.organizerUid, required this.title, required this.description, this.posterUrl, required this.startAt, required this.endAt, required this.location, required this.capacity, required this.waitlistEnabled, required this.tribeIds, required this.tags, required this.status, required this.stats, this.checkinActive = false, this.checkinOpensAt, this.checkinClosesAt, this.registrationClosesAt, this.contact = '', this.certificateEnabled = true, this.reviewStatus = 'approved', this.cancellationReason, this.tribeRsvps = const {}, this.tribeCheckins = const {}, this.reportCount = 0});
  final String id, campusId, clubId, clubName, organizerUid, title, description, status, contact, reviewStatus;
  final String? posterUrl, cancellationReason;
  final List<String> participatingCampusIds, tribeIds, tags;
  final DateTime startAt, endAt; final DateTime? checkinOpensAt, checkinClosesAt, registrationClosesAt;
  final EventLocation location; final int capacity, reportCount; final bool waitlistEnabled, checkinActive, certificateEnabled;
  final EventStats stats; final Map<String, num> tribeRsvps, tribeCheckins;
  factory Event.fromDoc(DocumentSnapshot d) { final j = _data(d); return Event(id: d.id, campusId: j['campusId'] as String? ?? '', participatingCampusIds: _strList(j['participatingCampusIds']), clubId: j['clubId'] as String? ?? '', clubName: j['clubName'] as String? ?? '', organizerUid: j['organizerUid'] as String? ?? '', title: j['title'] as String? ?? '', description: j['description'] as String? ?? '', posterUrl: j['posterUrl'] as String?, startAt: Fmt.toDate(j['startAt']) ?? DateTime.now().toUtc(), endAt: Fmt.toDate(j['endAt']) ?? DateTime.now().toUtc(), location: EventLocation.fromJson(j['location'] as Json?), capacity: _int(j['capacity']), waitlistEnabled: j['waitlistEnabled'] == true, tribeIds: _strList(j['tribeIds']), tags: _strList(j['tags']), status: j['status'] as String? ?? 'published', stats: EventStats.fromJson(j['stats'] as Json?), checkinActive: j['checkinActive'] == true, checkinOpensAt: Fmt.toDate(j['checkinOpensAt']), checkinClosesAt: Fmt.toDate(j['checkinClosesAt']), registrationClosesAt: Fmt.toDate(j['registrationClosesAt']), contact: j['contact'] as String? ?? '', certificateEnabled: j['certificateEnabled'] != false, reviewStatus: j['reviewStatus'] as String? ?? 'approved', cancellationReason: (j['cancellation'] as Map?)?['reason'] as String?, tribeRsvps: _numMap(j['tribeRsvps']), tribeCheckins: _numMap(j['tribeCheckins']), reportCount: _int(j['reportCount'])); }
  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed' || status == 'archived';
  bool get isPast => endAt.isBefore(DateTime.now().toUtc());
  bool get isFull => capacity > 0 && stats.rsvpCount >= capacity;
  bool get isCrossCampus => participatingCampusIds.length > 1;
  int get spotsLeft => capacity == 0 ? -1 : (capacity - stats.rsvpCount).clamp(0, capacity);
}

class UserProfile {
  const UserProfile({required this.uid, required this.email, required this.displayName, this.avatarUrl, this.activeCampusId, this.campusIds = const [], this.tribeIds = const [], this.primaryTribeId, this.onboardingCompleted = false, this.status = 'active', this.referralCode, this.notificationPrefs = const {}, this.privacy = const {}, this.superAdmin = false, this.feedVariant = 'chronological', this.suspensionReason, this.createdAt});
  final String uid, email, displayName, status, feedVariant; final String? avatarUrl, activeCampusId, primaryTribeId, referralCode, suspensionReason;
  final List<String> campusIds, tribeIds; final bool onboardingCompleted, superAdmin; final Map<String, bool> notificationPrefs, privacy; final DateTime? createdAt;
  factory UserProfile.fromDoc(DocumentSnapshot d) { final j = _data(d); return UserProfile(uid: d.id, email: j['email'] as String? ?? '', displayName: j['displayName'] as String? ?? '', avatarUrl: j['avatarUrl'] as String?, activeCampusId: j['activeCampusId'] as String?, campusIds: _strList(j['campusIds']), tribeIds: _strList(j['tribeIds']), primaryTribeId: j['primaryTribeId'] as String?, onboardingCompleted: j['onboardingCompleted'] == true, status: j['status'] as String? ?? 'active', referralCode: j['referralCode'] as String?, notificationPrefs: (j['notificationPrefs'] as Map?)?.map((k, v) => MapEntry(k.toString(), v == true)) ?? const {}, privacy: (j['privacy'] as Map?)?.map((k, v) => MapEntry(k.toString(), v == true)) ?? const {}, superAdmin: j['superAdmin'] == true, feedVariant: j['feedVariant'] as String? ?? 'chronological', suspensionReason: (j['suspension'] as Map?)?['reason'] as String?, createdAt: Fmt.toDate(j['createdAt'])); }
  bool get isSuspended => status == 'suspended';
}

class Membership {
  const Membership({required this.id, required this.campusId, required this.uid, required this.roles, required this.status, this.clubIds = const [], this.requestedRoles = const [], this.vendorId, this.brandId, this.displayName = '', this.tribeIds = const [], this.roleRequests = const {}, this.joinedAt});
  final String id, campusId, uid, status, displayName; final Set<Role> roles; final List<String> clubIds, requestedRoles, tribeIds; final String? vendorId, brandId; final Json roleRequests; final DateTime? joinedAt;
  factory Membership.fromDoc(DocumentSnapshot d) { final j = _data(d); return Membership(id: d.id, campusId: j['campusId'] as String? ?? '', uid: j['uid'] as String? ?? '', roles: _strList(j['roles']).map(Role.parse).whereType<Role>().toSet(), status: j['status'] as String? ?? 'active', clubIds: _strList(j['clubIds']), requestedRoles: _strList(j['requestedRoles']), vendorId: j['vendorId'] as String?, brandId: j['brandId'] as String?, displayName: j['displayName'] as String? ?? '', tribeIds: _strList(j['tribeIds']), roleRequests: (j['roleRequests'] as Map?)?.cast<String, dynamic>() ?? const {}, joinedAt: Fmt.toDate(j['joinedAt'])); }
  bool has(Role r) => roles.contains(r);
}

class Rsvp {
  const Rsvp({required this.id, required this.eventId, required this.uid, required this.status, this.eventTitle = '', this.startAt, this.createdAt});
  final String id, eventId, uid, status, eventTitle; final DateTime? startAt, createdAt;
  factory Rsvp.fromDoc(DocumentSnapshot d) { final j = _data(d); return Rsvp(id: d.id, eventId: j['eventId'] as String? ?? '', uid: j['uid'] as String? ?? '', status: j['status'] as String? ?? 'confirmed', eventTitle: j['eventTitle'] as String? ?? '', startAt: Fmt.toDate(j['startAt']), createdAt: Fmt.toDate(j['createdAt'])); }
  bool get isActive => status != 'cancelled';
}

class Checkin {
  const Checkin({required this.id, required this.eventId, required this.uid, required this.method, required this.at, this.eventTitle = '', this.coinsAwarded = 0, this.certificateRef, this.streakAtCheckin = 0, this.multiplierApplied = false, this.clubId = '', this.startAt});
  final String id, eventId, uid, method, eventTitle, clubId; final DateTime at; final DateTime? startAt; final int coinsAwarded, streakAtCheckin; final String? certificateRef; final bool multiplierApplied;
  factory Checkin.fromDoc(DocumentSnapshot d) { final j = _data(d); return Checkin(id: d.id, eventId: j['eventId'] as String? ?? '', uid: j['uid'] as String? ?? '', method: j['method'] as String? ?? 'qr', at: Fmt.toDate(j['at']) ?? DateTime.now().toUtc(), eventTitle: j['eventTitle'] as String? ?? '', coinsAwarded: _int(j['coinsAwarded']), certificateRef: j['certificateRef'] as String?, streakAtCheckin: _int(j['streakAtCheckin']), multiplierApplied: j['multiplierApplied'] == true, clubId: j['clubId'] as String? ?? '', startAt: Fmt.toDate(j['startAt'])); }
}

class CoinBalance {
  const CoinBalance({this.balance = 0, this.lifetimeEarned = 0, this.lifetimeRedeemed = 0, this.lifetimeExpired = 0, this.expiringSoon = 0, this.expiringSoonAt});
  final int balance, lifetimeEarned, lifetimeRedeemed, lifetimeExpired, expiringSoon; final DateTime? expiringSoonAt;
  factory CoinBalance.fromDoc(DocumentSnapshot d) { final j = _data(d); return CoinBalance(balance: _int(j['balance']), lifetimeEarned: _int(j['lifetimeEarned']), lifetimeRedeemed: _int(j['lifetimeRedeemed']), lifetimeExpired: _int(j['lifetimeExpired']), expiringSoon: _int(j['expiringSoon']), expiringSoonAt: Fmt.toDate(j['expiringSoonAt'])); }
}

class LedgerEntry {
  const LedgerEntry({required this.id, required this.type, required this.reason, required this.amount, required this.createdAt, this.refId, this.expiresAt, this.meta = const {}});
  final String id, type, reason; final int amount; final DateTime createdAt; final DateTime? expiresAt; final String? refId; final Json meta;
  factory LedgerEntry.fromDoc(DocumentSnapshot d) { final j = _data(d); return LedgerEntry(id: d.id, type: j['type'] as String? ?? 'credit', reason: j['reason'] as String? ?? '', amount: _int(j['amount']), createdAt: Fmt.toDate(j['createdAt']) ?? DateTime.now().toUtc(), refId: j['refId'] as String?, expiresAt: Fmt.toDate(j['expiresAt']), meta: (j['meta'] as Map?)?.cast<String, dynamic>() ?? const {}); }
  String get label => switch (reason) { 'rsvp' => 'RSVP', 'checkin' => meta['multiplierApplied'] == true ? 'Verified check-in · 2x streak' : 'Verified check-in', 'feedback' => 'Event feedback', 'referral' => 'Friend showed up', 'organizer_bonus' => 'Organizer bonus', 'quest' => 'Quest complete', 'redemption' => 'Reward redeemed', 'expiry' => 'Coins expired', 'admin_adjustment' => 'Adjustment', 'redemption_refund' => 'Refund', _ => reason };
}

class ParticipationStats {
  const ParticipationStats({this.streak = 0, this.multiplierActive = false, this.totalCheckins = 0, this.totalRsvps = 0, this.lastWeekKey, this.attendedTags = const {}});
  final int streak, totalCheckins, totalRsvps; final bool multiplierActive; final String? lastWeekKey; final Map<String, num> attendedTags;
  factory ParticipationStats.fromDoc(DocumentSnapshot d) { final j = _data(d); return ParticipationStats(streak: _int(j['streak']), multiplierActive: j['multiplierActive'] == true, totalCheckins: _int(j['totalCheckins']), totalRsvps: _int(j['totalRsvps']), lastWeekKey: j['lastWeekKey'] as String?, attendedTags: _numMap(j['attendedTags'])); }
}

class Reward {
  const Reward({required this.id, required this.campusId, required this.title, required this.description, required this.type, required this.coinCost, this.inventory, this.faceValue, this.imageUrl, this.terms = '', this.redemptionInstructions = '', this.perUserLimit = 0, this.status = 'active', this.vendorId, this.redeemed = 0});
  final String id, campusId, title, description, type, terms, redemptionInstructions, status; final int coinCost, perUserLimit, redeemed; final int? inventory; final num? faceValue; final String? imageUrl, vendorId;
  factory Reward.fromDoc(DocumentSnapshot d) { final j = _data(d); return Reward(id: d.id, campusId: j['campusId'] as String? ?? '', title: j['title'] as String? ?? '', description: j['description'] as String? ?? '', type: j['type'] as String? ?? 'generic', coinCost: _int(j['coinCost']), inventory: j['inventory'] == null ? null : _int(j['inventory']), faceValue: j['faceValue'] as num?, imageUrl: j['imageUrl'] as String?, terms: j['terms'] as String? ?? '', redemptionInstructions: j['redemptionInstructions'] as String? ?? '', perUserLimit: _int(j['perUserLimit']), status: j['status'] as String? ?? 'active', vendorId: j['vendorId'] as String?, redeemed: _int((j['stats'] as Map?)?['redeemed'])); }
  bool get soldOut => inventory != null && inventory! <= 0;
  String get typeLabel => switch (type) { 'voucher' => 'Voucher', 'printing_credit' => 'Printing', 'priority_access' => 'Priority access', 'merchandise' => 'Merch', 'certificate' => 'Certificate', _ => 'Reward' };
}

class Redemption {
  const Redemption({required this.id, required this.uid, required this.rewardId, required this.rewardTitle, required this.code, required this.status, required this.coinCost, this.issuedAt, this.expiresAt, this.fulfilledAt, this.faceValue, this.vendorId, this.redemptionInstructions, this.settlementStatus = 'pending', this.settlementMonth});
  final String id, uid, rewardId, rewardTitle, code, status, settlementStatus; final int coinCost; final DateTime? issuedAt, expiresAt, fulfilledAt; final num? faceValue; final String? vendorId, redemptionInstructions, settlementMonth;
  factory Redemption.fromDoc(DocumentSnapshot d) { final j = _data(d); return Redemption(id: d.id, uid: j['uid'] as String? ?? '', rewardId: j['rewardId'] as String? ?? '', rewardTitle: j['rewardTitle'] as String? ?? '', code: j['code'] as String? ?? '', status: j['status'] as String? ?? 'issued', coinCost: _int(j['coinCost']), issuedAt: Fmt.toDate(j['issuedAt']), expiresAt: Fmt.toDate(j['expiresAt']), fulfilledAt: Fmt.toDate(j['fulfilledAt']), faceValue: j['faceValue'] as num?, vendorId: j['vendorId'] as String?, redemptionInstructions: j['redemptionInstructions'] as String?, settlementStatus: j['settlementStatus'] as String? ?? 'pending', settlementMonth: j['settlementMonth'] as String?); }
}

class Vendor {
  const Vendor({required this.id, required this.campusId, required this.name, this.contact = '', this.status = 'active', this.fulfilled = 0, this.pendingSettlementValue = 0, this.settlements = const {}});
  final String id, campusId, name, contact, status; final int fulfilled; final num pendingSettlementValue; final Json settlements;
  factory Vendor.fromDoc(DocumentSnapshot d) { final j = _data(d); final s = (j['stats'] as Map?) ?? {}; return Vendor(id: d.id, campusId: j['campusId'] as String? ?? '', name: j['name'] as String? ?? d.id, contact: j['contact'] as String? ?? '', status: j['status'] as String? ?? 'active', fulfilled: _int(s['fulfilled']), pendingSettlementValue: (s['pendingSettlementValue'] as num?) ?? 0, settlements: (j['settlements'] as Map?)?.cast<String, dynamic>() ?? const {}); }
}

class Feedback {
  const Feedback({required this.id, required this.eventId, required this.rating, this.review, this.displayName, this.anonymous = false, this.at, this.status = 'published'});
  final String id, eventId, status; final int rating; final String? review, displayName; final bool anonymous; final DateTime? at;
  factory Feedback.fromDoc(DocumentSnapshot d) { final j = _data(d); return Feedback(id: d.id, eventId: j['eventId'] as String? ?? '', rating: _int(j['rating']), review: j['review'] as String?, displayName: j['anonymous'] == true ? null : j['displayName'] as String?, anonymous: j['anonymous'] == true, at: Fmt.toDate(j['at']), status: j['status'] as String? ?? 'published'); }
}

class Friendship {
  const Friendship({required this.id, required this.uids, required this.requesterUid, required this.status, this.createdAt});
  final String id, requesterUid, status; final List<String> uids; final DateTime? createdAt;
  factory Friendship.fromDoc(DocumentSnapshot d) { final j = _data(d); return Friendship(id: d.id, uids: _strList(j['uids']), requesterUid: j['requesterUid'] as String? ?? '', status: j['status'] as String? ?? 'pending', createdAt: Fmt.toDate(j['createdAt'])); }
  String other(String me) => uids.firstWhere((u) => u != me, orElse: () => '');
}

class Quest {
  const Quest({required this.id, required this.brandId, required this.title, required this.description, required this.type, required this.status, required this.campusIds, required this.tribeIds, required this.startAt, required this.endAt, required this.rewardCoins, this.creativeUrl, this.criteria = const {}, this.terms = '', this.sponsorDisclosure = 'Sponsored quest', this.participantLimit = 0, this.campaignValue = 0, this.financialStatus = 'quoted', this.stats = const {}, this.rejectionReason});
  final String id, brandId, title, description, type, status, terms, sponsorDisclosure, financialStatus; final String? creativeUrl, rejectionReason; final List<String> campusIds, tribeIds; final DateTime startAt, endAt; final int rewardCoins, participantLimit; final num campaignValue; final Json criteria, stats;
  factory Quest.fromDoc(DocumentSnapshot d) { final j = _data(d); return Quest(id: d.id, brandId: j['brandId'] as String? ?? '', title: j['title'] as String? ?? '', description: j['description'] as String? ?? '', type: j['type'] as String? ?? 'event_attendance', status: j['status'] as String? ?? 'draft', campusIds: _strList(j['campusIds']), tribeIds: _strList(j['tribeIds']), startAt: Fmt.toDate(j['startAt']) ?? DateTime.now().toUtc(), endAt: Fmt.toDate(j['endAt']) ?? DateTime.now().toUtc(), rewardCoins: _int(j['rewardCoins']), creativeUrl: j['creativeUrl'] as String?, criteria: (j['criteria'] as Map?)?.cast<String, dynamic>() ?? const {}, terms: j['terms'] as String? ?? '', sponsorDisclosure: j['sponsorDisclosure'] as String? ?? 'Sponsored quest', participantLimit: _int(j['participantLimit']), campaignValue: (j['campaignValue'] as num?) ?? 0, financialStatus: j['financialStatus'] as String? ?? 'quoted', stats: (j['stats'] as Map?)?.cast<String, dynamic>() ?? const {}, rejectionReason: j['rejectionReason'] as String?); }
  String get typeLabel => switch (type) { 'event_attendance' => 'Attend an event', 'qr_activation' => 'Scan at the venue', 'event_count' => 'Multi-event challenge', 'checklist' => 'Checklist', 'streak' => 'Streak challenge', _ => type };
}

class QuestCompletion {
  const QuestCompletion({required this.id, required this.questId, required this.status, this.progress = const {}, this.coinsAwarded = 0, this.completedAt, this.questTitle = ''});
  final String id, questId, status, questTitle; final Json progress; final int coinsAwarded; final DateTime? completedAt;
  factory QuestCompletion.fromDoc(DocumentSnapshot d) { final j = _data(d); return QuestCompletion(id: d.id, questId: j['questId'] as String? ?? '', status: j['status'] as String? ?? 'joined', progress: (j['progress'] as Map?)?.cast<String, dynamic>() ?? const {}, coinsAwarded: _int(j['coinsAwarded']), completedAt: Fmt.toDate(j['completedAt']), questTitle: j['questTitle'] as String? ?? ''); }
}

class Referral {
  const Referral({required this.id, required this.referrerUid, required this.referredUid, required this.rewardAwarded, this.signupAt, this.firstAttendanceAt});
  final String id, referrerUid, referredUid; final bool rewardAwarded; final DateTime? signupAt, firstAttendanceAt;
  factory Referral.fromDoc(DocumentSnapshot d) { final j = _data(d); return Referral(id: d.id, referrerUid: j['referrerUid'] as String? ?? '', referredUid: j['referredUid'] as String? ?? '', rewardAwarded: j['rewardAwarded'] == true, signupAt: Fmt.toDate(j['signupAt']), firstAttendanceAt: Fmt.toDate(j['firstAttendanceAt'])); }
}

class LeaderboardRow {
  const LeaderboardRow({required this.tribeId, required this.name, required this.count, required this.rank, this.previousRank, this.movement});
  final String tribeId, name; final int count, rank; final int? previousRank, movement;
  factory LeaderboardRow.fromJson(Json j) => LeaderboardRow(tribeId: j['tribeId'] as String? ?? '', name: j['name'] as String? ?? '', count: _int(j['count']), rank: _int(j['rank']), previousRank: (j['previousRank'] as num?)?.toInt(), movement: (j['movement'] as num?)?.toInt());
}

class Survey {
  const Survey({required this.id, required this.campusId, required this.title, required this.status, this.responses = 0, this.closesAt, this.createdAt});
  final String id, campusId, title, status; final int responses; final DateTime? closesAt, createdAt;
  factory Survey.fromDoc(DocumentSnapshot d) { final j = _data(d); return Survey(id: d.id, campusId: j['campusId'] as String? ?? '', title: j['title'] as String? ?? '', status: j['status'] as String? ?? 'open', responses: _int((j['stats'] as Map?)?['responses']), closesAt: Fmt.toDate(j['closesAt']), createdAt: Fmt.toDate(j['createdAt'])); }
}

class AuditLog {
  const AuditLog({required this.id, required this.actorUid, required this.action, required this.entityType, required this.entityId, this.reason, this.before, this.after, this.at});
  final String id, actorUid, action, entityType, entityId; final String? reason; final Json? before, after; final DateTime? at;
  factory AuditLog.fromDoc(DocumentSnapshot d) { final j = _data(d); return AuditLog(id: d.id, actorUid: j['actorUid'] as String? ?? '', action: j['action'] as String? ?? '', entityType: j['entityType'] as String? ?? '', entityId: j['entityId'] as String? ?? '', reason: j['reason'] as String?, before: (j['before'] as Map?)?.cast<String, dynamic>(), after: (j['after'] as Map?)?.cast<String, dynamic>(), at: Fmt.toDate(j['at'])); }
}

class Entitlement {
  const Entitlement({required this.id, required this.key, required this.status, this.plan, this.billingStatus = 'manual', this.validUntil});
  final String id, key, status, billingStatus; final String? plan; final DateTime? validUntil;
  factory Entitlement.fromDoc(DocumentSnapshot d) { final j = _data(d); return Entitlement(id: d.id, key: j['key'] as String? ?? '', status: j['status'] as String? ?? 'inactive', plan: j['plan'] as String?, billingStatus: j['billingStatus'] as String? ?? 'manual', validUntil: Fmt.toDate(j['validUntil'])); }
  bool get isActive => status == 'active' && (validUntil == null || validUntil!.isAfter(DateTime.now().toUtc()));
}

class BrandAccount {
  const BrandAccount({required this.id, required this.name, this.status = 'active', this.logoUrl});
  final String id, name, status; final String? logoUrl;
  factory BrandAccount.fromDoc(DocumentSnapshot d) { final j = _data(d); return BrandAccount(id: d.id, name: j['name'] as String? ?? d.id, status: j['status'] as String? ?? 'active', logoUrl: j['logoUrl'] as String?); }
}

class NotificationLog {
  const NotificationLog({required this.id, required this.title, required this.category, required this.status, this.route, this.at});
  final String id, title, category, status; final String? route; final DateTime? at;
  factory NotificationLog.fromDoc(DocumentSnapshot d) { final j = _data(d); return NotificationLog(id: d.id, title: j['title'] as String? ?? '', category: j['category'] as String? ?? '', status: j['status'] as String? ?? '', route: j['route'] as String?, at: Fmt.toDate(j['at'])); }
}
