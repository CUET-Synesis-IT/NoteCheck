import 'dart:convert';
import 'dart:typed_data';

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.createdAt,
  });

  final int id;
  final String name;
  final String email;
  final String role;
  final DateTime? createdAt;

  bool get isAdmin => role == 'admin';

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: _i(j['id']),
        name: j['name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        role: j['role'] as String? ?? 'user',
        createdAt: _date(j['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
        'created_at': createdAt?.toIso8601String(),
      };

  User copyWith({String? name, String? role}) =>
      User(id: id, name: name ?? this.name, email: email, role: role ?? this.role, createdAt: createdAt);
}

class AuthSession {
  const AuthSession({required this.token, required this.user, required this.expiresInDays});

  final String token;
  final User user;
  final int expiresInDays;

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
        token: j['access_token'] as String,
        user: User.fromJson(j['user'] as Map<String, dynamic>),
        expiresInDays: _i(j['expires_in_days']),
      );
}

class Prediction {
  const Prediction({
    required this.scanId,
    required this.isGenuine,
    required this.confidence,
    required this.genuineProb,
    required this.counterfeitProb,
    required this.threshold,
    required this.latencyMs,
    required this.wasCropped,
    required this.createdAt,
    this.noteImage,
  });

  final int scanId;
  final bool isGenuine;
  final double confidence;
  final double genuineProb;
  final double counterfeitProb;
  final double threshold;
  final double latencyMs;
  final bool wasCropped;
  final DateTime? createdAt;
  final Uint8List? noteImage;

  String get label => isGenuine ? 'genuine' : 'counterfeit';

  factory Prediction.fromJson(Map<String, dynamic> j) {
    final probs = (j['probabilities'] as Map?)?.cast<String, dynamic>() ?? const {};
    Uint8List? image;
    final b64 = j['cropped_banknote_base64'] as String?;
    if (b64 != null && b64.contains(',')) {
      try {
        image = base64Decode(b64.split(',').last);
      } catch (_) {}
    }
    return Prediction(
      scanId: _i(j['scan_id']),
      isGenuine: j['prediction'] == 'genuine',
      confidence: _d(j['confidence']),
      genuineProb: _d(probs['genuine']),
      counterfeitProb: _d(probs['counterfeit']),
      threshold: _d(j['decision_threshold']),
      latencyMs: _d(j['inference_time_ms']),
      wasCropped: j['note_detected_and_cropped'] == true,
      createdAt: _date(j['created_at']),
      noteImage: image,
    );
  }
}

class Scan {
  const Scan({
    required this.id,
    required this.isGenuine,
    required this.confidence,
    required this.genuineProb,
    required this.counterfeitProb,
    required this.latencyMs,
    required this.wasCropped,
    required this.hasImage,
    required this.createdAt,
    this.userId,
    this.userEmail,
  });

  final int id;
  final bool isGenuine;
  final double confidence;
  final double genuineProb;
  final double counterfeitProb;
  final double latencyMs;
  final bool wasCropped;
  final bool hasImage;
  final DateTime? createdAt;
  final int? userId;
  final String? userEmail;

  String get label => isGenuine ? 'Genuine' : 'Counterfeit';

  factory Scan.fromJson(Map<String, dynamic> j) => Scan(
        id: _i(j['id']),
        isGenuine: j['prediction'] == 'genuine',
        confidence: _d(j['confidence']),
        genuineProb: _d(j['genuine_prob']),
        counterfeitProb: _d(j['counterfeit_prob']),
        latencyMs: _d(j['latency_ms']),
        wasCropped: j['was_cropped'] == true,
        hasImage: j['has_image'] == true,
        createdAt: _date(j['created_at']),
        userId: j['user_id'] == null ? null : _i(j['user_id']),
        userEmail: j['user_email'] as String?,
      );
}

class PagedScans {
  const PagedScans({required this.items, required this.total, required this.limit, required this.offset});

  final List<Scan> items;
  final int total;
  final int limit;
  final int offset;

  bool get hasMore => offset + items.length < total;

  factory PagedScans.fromJson(Map<String, dynamic> j) => PagedScans(
        items: (j['items'] as List? ?? const []).map((e) => Scan.fromJson(e as Map<String, dynamic>)).toList(),
        total: _i(j['total']),
        limit: _i(j['limit']),
        offset: _i(j['offset']),
      );
}

class UserStats {
  const UserStats({
    required this.totalScans,
    required this.genuineCount,
    required this.counterfeitCount,
    required this.counterfeitRate,
    required this.avgConfidence,
    required this.avgLatencyMs,
    this.lastScanAt,
  });

  final int totalScans;
  final int genuineCount;
  final int counterfeitCount;
  final double counterfeitRate;
  final double avgConfidence;
  final double avgLatencyMs;
  final DateTime? lastScanAt;

  static const empty = UserStats(
    totalScans: 0,
    genuineCount: 0,
    counterfeitCount: 0,
    counterfeitRate: 0,
    avgConfidence: 0,
    avgLatencyMs: 0,
  );

  factory UserStats.fromJson(Map<String, dynamic> j) => UserStats(
        totalScans: _i(j['total_scans']),
        genuineCount: _i(j['genuine_count']),
        counterfeitCount: _i(j['counterfeit_count']),
        counterfeitRate: _d(j['counterfeit_rate']),
        avgConfidence: _d(j['avg_confidence']),
        avgLatencyMs: _d(j['avg_latency_ms']),
        lastScanAt: _date(j['last_scan_at']),
      );
}

class DayCount {
  const DayCount({required this.date, required this.count, required this.counterfeit});

  final DateTime date;
  final int count;
  final int counterfeit;

  int get genuine => count - counterfeit;

  factory DayCount.fromJson(Map<String, dynamic> j) => DayCount(
        date: DateTime.parse(j['date'] as String),
        count: _i(j['count']),
        counterfeit: _i(j['counterfeit']),
      );
}

class AdminOverview {
  const AdminOverview({
    required this.totalScans,
    required this.genuineCount,
    required this.counterfeitCount,
    required this.counterfeitRate,
    required this.totalUsers,
    required this.adminCount,
    required this.scansLast24h,
    required this.avgLatencyMs,
    required this.byDay,
  });

  final int totalScans;
  final int genuineCount;
  final int counterfeitCount;
  final double counterfeitRate;
  final int totalUsers;
  final int adminCount;
  final int scansLast24h;
  final double avgLatencyMs;
  final List<DayCount> byDay;

  factory AdminOverview.fromJson(Map<String, dynamic> j) => AdminOverview(
        totalScans: _i(j['total_scans']),
        genuineCount: _i(j['genuine_count']),
        counterfeitCount: _i(j['counterfeit_count']),
        counterfeitRate: _d(j['counterfeit_rate']),
        totalUsers: _i(j['total_users']),
        adminCount: _i(j['admin_count']),
        scansLast24h: _i(j['scans_last_24h']),
        avgLatencyMs: _d(j['avg_latency_ms']),
        byDay: (j['by_day'] as List? ?? const []).map((e) => DayCount.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class ServerHealth {
  const ServerHealth({
    required this.online,
    required this.modelLoaded,
    this.version = '',
    this.device = '',
    this.ttaEnabled = false,
    this.threshold = 0.5,
    this.maxUploadMb = 0,
    this.error,
  });

  final bool online;
  final bool modelLoaded;
  final String version;
  final String device;
  final bool ttaEnabled;
  final double threshold;
  final double maxUploadMb;
  final String? error;

  bool get ready => online && modelLoaded;

  static const unknown = ServerHealth(online: false, modelLoaded: false);

  factory ServerHealth.fromJson(Map<String, dynamic> j) => ServerHealth(
        online: j['status'] == 'online',
        modelLoaded: j['model_loaded'] == true,
        version: j['version']?.toString() ?? '',
        device: j['device']?.toString() ?? '',
        ttaEnabled: j['tta_enabled'] == true,
        threshold: _d(j['decision_threshold']),
        maxUploadMb: _d(j['max_upload_mb']),
      );
}
