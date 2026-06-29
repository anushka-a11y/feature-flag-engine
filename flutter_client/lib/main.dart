import 'package:flutter/material.dart';
import 'feature_flag.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise the SDK — connects WebSocket & fetches initial config.
  // Change the URL to your machine's IP when testing on a real device,
  // e.g. 'http://192.168.1.42:8080'
  await FeatureFlag.initialize(
    'http://localhost:8080',
    userId: 'alice',
    group:  'beta',
    isBeta: true,
  );

  runApp(const FlagApp());
}

class FlagApp extends StatelessWidget {
  const FlagApp({super.key});

  @override
  Widget build(BuildContext context) {
    // StreamBuilder at the root — any server push rebuilds the whole tree.
    return StreamBuilder<Map<String, dynamic>>(
      stream: FeatureFlag.stream,
      builder: (context, _) {
        final isDark = FeatureFlag.isEnabled('dark_mode_beta');
        return MaterialApp(
          title: 'Feature Flag Engine',
          debugShowCheckedModeBanner: false,
          theme: isDark ? ThemeData.dark() : ThemeData.light(),
          home: const HomeScreen(),
        );
      },
    );
  }
}