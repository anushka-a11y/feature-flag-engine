import 'package:flutter/material.dart';
import 'flag_service.dart';

class HomeScreen extends StatelessWidget {
  final FlagSnapshot? snapshot;
  final String connectionStatus;

  const HomeScreen({
    super.key,
    required this.snapshot,
    required this.connectionStatus,
  });

  @override
  Widget build(BuildContext context) {
    final flags = snapshot?.flags ?? [];
    final configs = snapshot?.configs ?? [];
    final isDarkMode = snapshot?.isEnabled('dark_mode_beta') ?? false;
    final welcomeMsg =
        snapshot?.configValue('welcome_message') as String? ?? 'Loading...';
    final maxAttempts =
        snapshot?.configValue('max_login_attempts') ?? '—';

    return Theme(
      data: isDarkMode ? ThemeData.dark() : ThemeData.light(),
      child: Scaffold(
        backgroundColor: isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text('Feature Flag Demo'),
          backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.indigo,
          foregroundColor: Colors.white,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Row(
                  children: [
                    Icon(
                      connectionStatus == 'Connected'
                          ? Icons.wifi
                          : Icons.wifi_off,
                      color: connectionStatus == 'Connected'
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      connectionStatus,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: snapshot == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome message from remote config
                    _WelcomeBanner(message: welcomeMsg, dark: isDarkMode),
                    const SizedBox(height: 20),

                    // Feature-gated UI sections
                    if (snapshot!.isEnabled('new_checkout_flow'))
                      _FeatureCard(
                        icon: Icons.shopping_cart_checkout,
                        title: 'New Checkout Flow',
                        subtitle: 'You are on the redesigned checkout experience.',
                        color: Colors.green,
                      ),

                    if (snapshot!.isEnabled('ai_recommendations'))
                      _FeatureCard(
                        icon: Icons.auto_awesome,
                        title: 'AI Recommendations',
                        subtitle:
                            'Personalised picks powered by AI — rolling out to ${_rollout(snapshot!, "ai_recommendations")}% of users.',
                        color: Colors.purple,
                      ),

                    if (isDarkMode)
                      _FeatureCard(
                        icon: Icons.dark_mode,
                        title: 'Dark Mode Active',
                        subtitle: 'UI theme switched by remote flag.',
                        color: Colors.blueGrey,
                      ),

                    const SizedBox(height: 8),

                    // Remote configs display
                    _SectionHeader(title: 'Remote Configs', dark: isDarkMode),
                    _ConfigTile(
                      label: 'max_login_attempts',
                      value: '$maxAttempts',
                      dark: isDarkMode,
                    ),
                    _ConfigTile(
                      label: 'welcome_message',
                      value: '"$welcomeMsg"',
                      dark: isDarkMode,
                    ),

                    const SizedBox(height: 20),

                    // All flags raw list
                    _SectionHeader(title: 'All Flags', dark: isDarkMode),
                    ...flags.map((f) => _FlagRow(flag: f, dark: isDarkMode)),

                    const SizedBox(height: 12),
                    if (snapshot != null)
                      Center(
                        child: Text(
                          'Last synced: ${_fmt(snapshot!.fetchedAt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  int _rollout(FlagSnapshot snap, String id) =>
      snap.flags
          .where((f) => f.id == id)
          .map((f) => f.rolloutPercentage)
          .firstOrNull ??
      100;

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _WelcomeBanner extends StatelessWidget {
  final String message;
  final bool dark;
  const _WelcomeBanner({required this.message, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? [const Color(0xFF1A237E), const Color(0xFF4A148C)]
              : [Colors.indigo, Colors.deepPurple],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('welcome_message',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            message,
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  const _FeatureCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.4), width: 1),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color, size: 20),
        ),
        title:
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('ACTIVE',
              style: TextStyle(
                  color: Colors.green,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool dark;
  const _SectionHeader({required this.title, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.4,
          fontWeight: FontWeight.bold,
          color: dark ? Colors.white54 : Colors.black45,
        ),
      ),
    );
  }
}

class _ConfigTile extends StatelessWidget {
  final String label;
  final String value;
  final bool dark;
  const _ConfigTile(
      {required this.label, required this.value, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: dark ? Colors.white12 : Colors.black12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: dark ? Colors.white70 : Colors.black87)),
          Text(value,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: dark ? Colors.amber : Colors.indigo,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  final FeatureFlag flag;
  final bool dark;
  const _FlagRow({required this.flag, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dark ? Colors.white12 : Colors.black12),
      ),
      child: Row(
        children: [
          Icon(
            flag.enabled ? Icons.toggle_on : Icons.toggle_off,
            color: flag.enabled ? Colors.green : Colors.red,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(flag.id,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: dark ? Colors.white70 : Colors.black87)),
          ),
          Text(flag.rule,
              style: TextStyle(
                  fontSize: 11,
                  color: dark ? Colors.white38 : Colors.black38)),
          const SizedBox(width: 8),
          Text('${flag.rolloutPercentage}%',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: dark ? Colors.white54 : Colors.indigo)),
        ],
      ),
    );
  }
}