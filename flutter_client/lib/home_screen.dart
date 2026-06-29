import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'feature_flag.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _userIdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _userIdCtrl.text = FeatureFlag.currentUser.userId;
  }

  @override
  void dispose() {
    _userIdCtrl.dispose();
    super.dispose();
  }

  void _applyUser(UserContext u) {
    FeatureFlag.setUser(u);
    if (_userIdCtrl.text != u.userId) _userIdCtrl.text = u.userId;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: FeatureFlag.stream,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final u       = FeatureFlag.currentUser;
    final isDark  = FeatureFlag.isEnabled('dark_mode_beta');
    final wsLive  = FeatureFlag.isWebSocketConnected;
    final welcome = FeatureFlag.getString('welcome_message') ?? '…';
    final maxTries= FeatureFlag.getNumber('max_login_attempts');
    final flags   = FeatureFlag.allFlags;

    final bg      = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
    final surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final border  = isDark ? Colors.white12 : Colors.black12;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.indigo,
        foregroundColor: Colors.white,
        title: const Text('Feature Flag Engine'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(children: [
              Icon(wsLive ? Icons.bolt : Icons.wifi_off,
                  color: wsLive ? Colors.greenAccent : Colors.orangeAccent,
                  size: 18),
              const SizedBox(width: 5),
              Text(wsLive ? 'Live (WS)' : 'Polling',
                  style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome banner
            _Banner(message: welcome, dark: isDark),
            const SizedBox(height: 16),

            // User Simulation Console
            _SimConsole(
              user: u,
              userIdCtrl: _userIdCtrl,
              onApply: _applyUser,
              dark: isDark,
            ),
            const SizedBox(height: 20),

            // Gated features
            _SectionHeader('Evaluated Gated Features', isDark),
            if (FeatureFlag.isEnabled('new_checkout_flow'))
              _FeatureCard(
                icon: Icons.shopping_cart_checkout,
                title: 'New Checkout Flow',
                subtitle: 'Redesigned purchase experience (Beta group only).',
                reason: 'Group: beta | Rollout: ${(flags['new_checkout_flow']?['rollout'] ?? 20)}%',
                color: Colors.green,
              ),
            if (FeatureFlag.isEnabled('ai_recommendations'))
              _FeatureCard(
                icon: Icons.auto_awesome,
                title: 'AI Recommendations',
                subtitle: 'Personalised picks — 10% rollout.',
                reason: 'Bucket: ${FeatureFlag.bucketFor("ai_recommendations")}% < 10%',
                color: Colors.purple,
              ),
            if (isDark)
              _FeatureCard(
                icon: Icons.dark_mode,
                title: 'Dark Mode Active',
                subtitle: 'Theme toggled via remote flag.',
                reason: 'Group: everyone | Rollout: 100%',
                color: Colors.blueGrey,
              ),
            if (!FeatureFlag.isEnabled('new_checkout_flow') &&
                !FeatureFlag.isEnabled('ai_recommendations') &&
                !isDark)
              _Empty(dark: isDark),

            const SizedBox(height: 16),

            // Remote configs
            _SectionHeader('Remote Configs', isDark),
            _Tile(label: 'welcome_message',   value: '"$welcome"',  dark: isDark, surface: surface, border: border),
            _Tile(label: 'max_login_attempts', value: '$maxTries',   dark: isDark, surface: surface, border: border),

            const SizedBox(height: 16),

            // All flags
            _SectionHeader('Live Flag Configurations', isDark),
            ...flags.entries.map((e) {
              final name      = e.key;
              final flag      = e.value as Map<String, dynamic>;
              final active    = FeatureFlag.isEnabled(name);
              final rollout   = flag['rollout'] ?? 100;
              final groups    = (flag['groups'] as List?)?.join(', ') ?? 'everyone';
              final bucket    = FeatureFlag.bucketFor(name);
              return _FlagRow(
                name: name, flag: flag, active: active,
                rollout: rollout, groups: groups, bucket: bucket,
                dark: isDark, surface: surface, border: border,
              );
            }),

            const SizedBox(height: 16),

            // Audit log
            _SectionHeader('Recent Audit Log', isDark),
            _AuditPanel(dark: isDark, surface: surface, border: border),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool dark;
  const _SectionHeader(this.title, this.dark);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(title.toUpperCase(),
        style: TextStyle(fontSize: 11, letterSpacing: 1.4,
            fontWeight: FontWeight.bold,
            color: dark ? Colors.white54 : Colors.black45)),
  );
}

class _Banner extends StatelessWidget {
  final String message;
  final bool dark;
  const _Banner({required this.message, required this.dark});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: dark
          ? [const Color(0xFF1A237E), const Color(0xFF311B92)]
          : [Colors.indigo, Colors.purple]),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('welcome_message  (Remote Config)',
          style: TextStyle(color: Colors.white54, fontSize: 11)),
      const SizedBox(height: 6),
      Text(message, style: const TextStyle(
          color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
    ]),
  );
}

class _SimConsole extends StatelessWidget {
  final UserContext user;
  final TextEditingController userIdCtrl;
  final ValueChanged<UserContext> onApply;
  final bool dark;
  const _SimConsole({required this.user, required this.userIdCtrl,
      required this.onApply, required this.dark});

  @override
  Widget build(BuildContext context) {
    final bg     = dark ? const Color(0xFF1E1E1E) : Colors.white;
    final border = dark ? Colors.white12 : Colors.black15;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(Icons.badge, size: 16, color: dark ? Colors.amber : Colors.indigo),
            const SizedBox(width: 8),
            Text('USER CONTEXT SIMULATOR',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: dark ? Colors.white70 : Colors.black87)),
          ]),
          _Pill(user.group == 'beta' || user.isBeta ? 'BETA' : 'REGULAR',
              user.isBeta ? Colors.orange : Colors.blue),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: userIdCtrl,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'User ID', isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => onApply(user.copyWith(userId: v)),
            ),
          ),
          const SizedBox(width: 10),
          const Text('Beta:', style: TextStyle(fontSize: 13)),
          Switch(
            value: user.isBeta,
            activeColor: Colors.orange,
            onChanged: (v) => onApply(user.copyWith(
                isBeta: v, group: v ? 'beta' : 'everyone')),
          ),
        ]),
        const Divider(height: 20),
        Text('Quick profiles', style: TextStyle(
            fontSize: 11, color: dark ? Colors.white38 : Colors.black45)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Chip('Alice (beta, bucket 0)', user.userId == 'alice',
              () => onApply(const UserContext(userId: 'alice', group: 'beta', isBeta: true)), dark),
          _Chip('Bob (regular, bucket 25)', user.userId == 'bob',
              () => onApply(const UserContext(userId: 'bob', group: 'everyone', isBeta: false)), dark),
          _Chip('Charlie (bucket 70)', user.userId == 'charlie',
              () => onApply(const UserContext(userId: 'charlie', group: 'everyone', isBeta: false)), dark),
          _Chip('🎲 Random', false, () {
            final id = 'user_${Random().nextInt(9999)}';
            onApply(UserContext(userId: id, group: 'everyone', isBeta: false));
          }, dark),
        ]),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
    child: Text(label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dark;
  const _Chip(this.label, this.selected, this.onTap, this.dark);
  @override
  Widget build(BuildContext context) {
    final active = dark ? Colors.indigoAccent : Colors.indigo;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? active.withOpacity(0.12) : Colors.transparent,
          border: Border.all(
              color: selected ? active : (dark ? Colors.white24 : Colors.black26),
              width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? (dark ? Colors.white : active)
                    : (dark ? Colors.white70 : Colors.black87))),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle, reason;
  final Color color;
  const _FeatureCard({required this.icon, required this.title,
      required this.subtitle, required this.reason, required this.color});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.3))),
    child: ListTile(
      leading: CircleAvatar(backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color, size: 20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(subtitle, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 3),
        Text('✓ $reason',
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ]),
      trailing: _Pill('ACTIVE', Colors.green),
    ),
  );
}

class _Empty extends StatelessWidget {
  final bool dark;
  const _Empty({required this.dark});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    decoration: BoxDecoration(
        color: dark ? Colors.white10 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: dark ? Colors.white12 : Colors.black12)),
    child: Column(children: [
      Icon(Icons.dashboard_customize_outlined, size: 40,
          color: dark ? Colors.white24 : Colors.black26),
      const SizedBox(height: 10),
      Text('No Gated Features Active for This User',
          style: TextStyle(fontWeight: FontWeight.bold,
              color: dark ? Colors.white60 : Colors.black54)),
      const SizedBox(height: 4),
      Text('Change user context above or toggle flags in the TUI dashboard.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12,
              color: dark ? Colors.white30 : Colors.black38)),
    ]),
  );
}

class _Tile extends StatelessWidget {
  final String label, value;
  final bool dark;
  final Color surface, border;
  const _Tile({required this.label, required this.value,
      required this.dark, required this.surface, required this.border});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 13,
          color: dark ? Colors.white70 : Colors.black87)),
      Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 13,
          fontWeight: FontWeight.bold,
          color: dark ? Colors.amber : Colors.indigo)),
    ]),
  );
}

class _FlagRow extends StatelessWidget {
  final String name, groups;
  final Map<String, dynamic> flag;
  final bool active, dark;
  final int rollout, bucket;
  final Color surface, border;
  const _FlagRow({required this.name, required this.flag, required this.active,
      required this.rollout, required this.groups, required this.bucket,
      required this.dark, required this.surface, required this.border});
  @override
  Widget build(BuildContext context) {
    final enabled = flag['enabled'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border)),
      child: Row(children: [
        Icon(enabled ? Icons.toggle_on : Icons.toggle_off,
            color: enabled ? Colors.green : Colors.red, size: 26),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(fontFamily: 'monospace', fontSize: 13,
              fontWeight: FontWeight.bold,
              color: dark ? Colors.white70 : Colors.black87)),
          const SizedBox(height: 2),
          Text('rollout: $rollout%  |  groups: $groups  |  your bucket: $bucket%',
              style: TextStyle(fontSize: 10,
                  color: dark ? Colors.white38 : Colors.black45)),
        ])),
        _Pill(active ? 'YOU: ON' : 'YOU: OFF',
            active ? Colors.green : Colors.grey),
      ]),
    );
  }
}

class _AuditPanel extends StatefulWidget {
  final bool dark;
  final Color surface, border;
  const _AuditPanel({required this.dark, required this.surface, required this.border});
  @override
  State<_AuditPanel> createState() => _AuditPanelState();
}

class _AuditPanelState extends State<_AuditPanel> {
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh audit log on every WS push
    FeatureFlag.stream.listen((_) => _load());
  }

  Future<void> _load() async {
    try {
      final res = await _http('http://localhost:8080/audit');
      if (res != null && mounted) {
        setState(() {
          final raw = res as List;
          _entries = raw.reversed
              .take(10)
              .map((e) => e as Map<String, dynamic>)
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<dynamic> _http(String url) async {
    try {
      final res = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: widget.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.border)),
        child: Text('No audit entries yet. Toggle a flag to see logs here.',
            style: TextStyle(fontSize: 12,
                color: widget.dark ? Colors.white38 : Colors.black45)),
      );
    }
    return Column(
      children: _entries.map((e) {
        final isFlag = e['action'] == 'flag_update';
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(color: widget.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.border)),
          child: Row(children: [
            Icon(isFlag ? Icons.flag : Icons.settings,
                size: 16, color: isFlag ? Colors.indigo : Colors.teal),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['target']}',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: widget.dark ? Colors.white70 : Colors.black87)),
              Text('${e['old']} → ${e['new']}',
                  style: TextStyle(fontSize: 11,
                      color: widget.dark ? Colors.white38 : Colors.black45)),
            ])),
            Text('${e['time']}'.substring(11, 19),
                style: TextStyle(fontSize: 10, fontFamily: 'monospace',
                    color: widget.dark ? Colors.white24 : Colors.black38)),
          ]),
        );
      }).toList(),
    );
  }
}
