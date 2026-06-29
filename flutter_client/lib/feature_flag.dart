/// Feature Flag SDK — Flutter Client
///
/// Usage
/// -----
/// ```dart
/// // Once at startup (before runApp):
/// await FeatureFlag.initialize(
///   'http://localhost:8080',
///   userId: 'alice',
///   group: 'beta',
/// );
///
/// // Anywhere (synchronous – reads from cache):
/// bool enabled = FeatureFlag.isEnabled('dark_mode_beta');
/// String? msg  = FeatureFlag.getString('welcome_message');
/// num?   tries = FeatureFlag.getNumber('max_login_attempts');
///
/// // Reactive rebuilds – listen for pushes:
/// StreamBuilder(
///   stream: FeatureFlag.stream,
///   builder: (ctx, _) => FeatureFlag.isEnabled('new_ui')
///       ? NewHomePage()
///       : OldHomePage(),
/// );
/// ```
library feature_flag;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

// ── Public model ──────────────────────────────────────────────────────────────

class UserContext {
  final String userId;
  final String group; // e.g. "everyone", "beta", "staff"
  final bool isBeta;

  const UserContext({
    required this.userId,
    this.group = 'everyone',
    this.isBeta = false,
  });

  UserContext copyWith({String? userId, String? group, bool? isBeta}) =>
      UserContext(
        userId: userId ?? this.userId,
        group: group ?? this.group,
        isBeta: isBeta ?? this.isBeta,
      );
}

// ── SDK singleton ─────────────────────────────────────────────────────────────

class FeatureFlag {
  FeatureFlag._();

  // ── State ─────────────────────────────────────────────────────────────────

  static String _serverUrl = 'http://localhost:8080';
  static UserContext _user =
      const UserContext(userId: 'anonymous', group: 'everyone');

  static Map<String, dynamic> _flags   = {};
  static Map<String, dynamic> _configs = {};

  static WebSocketChannel? _channel;
  static Timer?             _pollTimer;
  static bool               _wsConnected = false;

  static final _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  // Public stream — fires whenever config is updated (push or poll)
  static Stream<Map<String, dynamic>> get stream => _controller.stream;

  /// True while a WebSocket connection is active
  static bool get isWebSocketConnected => _wsConnected;

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Call once before [runApp].
  static Future<void> initialize(
    String serverUrl, {
    String userId = 'anonymous',
    String group  = 'everyone',
    bool   isBeta = false,
  }) async {
    _serverUrl = serverUrl;
    _user = UserContext(userId: userId, group: group, isBeta: isBeta);

    // Fetch initial config synchronously so first frame is correct
    await _fetchHttp();

    // Connect WebSocket for real-time push
    _connectWebSocket();
  }

  /// Update the simulated user at runtime — triggers a stream event so the UI
  /// rebuilds immediately with the new evaluation results.
  static void setUser(UserContext user) {
    _user = user;
    _controller.add({'flags': _flags, 'configs': _configs});
  }

  static UserContext get currentUser => _user;

  // ── HTTP fallback ─────────────────────────────────────────────────────────

  static Future<void> _fetchHttp() async {
    try {
      final res = await http
          .get(Uri.parse('$_serverUrl/config'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        _applyConfig(jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  static void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _fetchHttp());
  }

  static void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── WebSocket ─────────────────────────────────────────────────────────────

  static void _connectWebSocket() {
    final wsUrl = _serverUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');

    try {
      _channel = WebSocketChannel.connect(Uri.parse('$wsUrl/ws'));
      _channel!.stream.listen(
        (raw) {
          try {
            final msg = jsonDecode(raw as String) as Map<String, dynamic>;
            if (msg['type'] == 'config_update') {
              _applyConfig(msg['data'] as Map<String, dynamic>);
              if (!_wsConnected) {
                _wsConnected = true;
                _stopPolling(); // WS is live — no need to poll
              }
            }
          } catch (_) {}
        },
        onError: (_) => _onWsDisconnect(),
        onDone:  ()  => _onWsDisconnect(),
      );
    } catch (_) {
      _onWsDisconnect();
    }
  }

  static void _onWsDisconnect() {
    _wsConnected = false;
    _startPolling(); // fall back to polling
    // Retry WebSocket after 5 s
    Timer(const Duration(seconds: 5), _connectWebSocket);
  }

  // ── Config application ────────────────────────────────────────────────────

  static void _applyConfig(Map<String, dynamic> data) {
    _flags   = (data['flags']   as Map<String, dynamic>?) ?? {};
    _configs = (data['configs'] as Map<String, dynamic>?) ?? {};
    _controller.add({'flags': _flags, 'configs': _configs});
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns true if [flagId] is active for the current user.
  ///
  /// Evaluation order:
  ///   1. Flag must exist and have `enabled == true`.
  ///   2. User's group must be in `flag.groups` (or groups contains "everyone").
  ///   3. `stableHash(flagId + userId) % 100 < rollout`.
  static bool isEnabled(String flagId, [UserContext? user]) {
    final u    = user ?? _user;
    final flag = _flags[flagId] as Map<String, dynamic>?;
    if (flag == null)                      return false;
    if (flag['enabled'] != true)           return false;

    // Group check
    final groups = (flag['groups'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList() ?? ['everyone'];
    final groupsPass = groups.contains('everyone') ||
        groups.contains(u.group) ||
        (u.isBeta && groups.contains('beta'));
    if (!groupsPass) return false;

    // Rollout check
    final rollout = (flag['rollout'] as num?)?.toInt() ?? 100;
    if (rollout < 100) {
      final bucket = _stableHash('${flagId}_${u.userId}');
      if (bucket >= rollout) return false;
    }

    return true;
  }

  /// Returns the raw config value for [key] (may be String, num, bool, …).
  static dynamic getValue(String key) => _configs[key];

  /// Convenience — returns [key] as String, or null.
  static String? getString(String key) {
    final v = _configs[key];
    return v != null ? v.toString() : null;
  }

  /// Convenience — returns [key] as num, or null.
  static num? getNumber(String key) {
    final v = _configs[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  /// All flags snapshot (raw map).
  static Map<String, dynamic> get allFlags   => Map.unmodifiable(_flags);

  /// All configs snapshot (raw map).
  static Map<String, dynamic> get allConfigs => Map.unmodifiable(_configs);

  // ── Rollout hashing ───────────────────────────────────────────────────────

  /// Deterministic, stable hash in [0, 99].
  /// Identical algorithm used in the Python validator.
  static int _stableHash(String key) {
    int hash = 0;
    for (final codeUnit in key.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0xFFFFFFFF;
    }
    // Treat as signed 32-bit int
    if (hash >= 0x80000000) hash -= 0x100000000;
    return hash.abs() % 100;
  }

  /// Expose hash for UI display purposes (shows "your bucket").
  static int bucketFor(String flagId, [UserContext? user]) =>
      _stableHash('${flagId}_${(user ?? _user).userId}');

  // ── Cleanup ───────────────────────────────────────────────────────────────

  static void dispose() {
    _channel?.sink.close();
    _pollTimer?.cancel();
    _controller.close();
  }
}
