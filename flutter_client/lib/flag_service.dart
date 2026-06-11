import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ── Data models ──────────────────────────────────────────────────────────────

class FeatureFlag {
  final String id;
  final bool enabled;
  final String rule;
  final int rolloutPercentage;

  const FeatureFlag({
    required this.id,
    required this.enabled,
    required this.rule,
    required this.rolloutPercentage,
  });

  factory FeatureFlag.fromJson(Map<String, dynamic> j) => FeatureFlag(
        id: j['id'] as String,
        enabled: j['enabled'] as bool,
        rule: j['rule'] as String? ?? 'Everyone',
        rolloutPercentage: j['rollout_percentage'] as int? ?? 100,
      );
}

class RemoteConfig {
  final String key;
  final dynamic value;
  final String type;

  const RemoteConfig({
    required this.key,
    required this.value,
    required this.type,
  });

  factory RemoteConfig.fromJson(Map<String, dynamic> j) => RemoteConfig(
        key: j['key'] as String,
        value: j['value'],
        type: j['type'] as String,
      );
}

class FlagSnapshot {
  final List<FeatureFlag> flags;
  final List<RemoteConfig> configs;
  final DateTime fetchedAt;

  const FlagSnapshot({
    required this.flags,
    required this.configs,
    required this.fetchedAt,
  });

  bool isEnabled(String flagId) =>
      flags.where((f) => f.id == flagId).map((f) => f.enabled).firstOrNull ??
      false;

  dynamic configValue(String key) =>
      configs.where((c) => c.key == key).map((c) => c.value).firstOrNull;
}

// ── Service ───────────────────────────────────────────────────────────────────

class FlagService {
  // Change to your machine's local IP if testing on a real device
  // e.g. "http://192.168.1.42:8080"
  static const _baseUrl = 'http://localhost:8080';
  static const _pollInterval = Duration(seconds: 3);

  final _controller = StreamController<FlagSnapshot>.broadcast();
  Timer? _timer;
  FlagSnapshot? _last;

  Stream<FlagSnapshot> get stream => _controller.stream;
  FlagSnapshot? get current => _last;

  void start() {
    _fetch();
    _timer = Timer.periodic(_pollInterval, (_) => _fetch());
  }

  void stop() {
    _timer?.cancel();
    _controller.close();
  }

  Future<void> _fetch() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/flags'))
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final snapshot = FlagSnapshot(
          flags: (json['flags'] as List)
              .map((e) => FeatureFlag.fromJson(e as Map<String, dynamic>))
              .toList(),
          configs: (json['configs'] as List)
              .map((e) => RemoteConfig.fromJson(e as Map<String, dynamic>))
              .toList(),
          fetchedAt: DateTime.now(),
        );
        _last = snapshot;
        _controller.add(snapshot);
      }
    } catch (_) {
      // Network error — keep last known state, don't crash
    }
  }
}