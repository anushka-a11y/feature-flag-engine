import 'package:flutter/material.dart';
import 'flag_service.dart';
import 'home_screen.dart';

void main() {
  runApp(const FlagApp());
}

class FlagApp extends StatefulWidget {
  const FlagApp({super.key});

  @override
  State<FlagApp> createState() => _FlagAppState();
}

class _FlagAppState extends State<FlagApp> {
  final _service = FlagService();
  FlagSnapshot? _snapshot;
  String _status = 'Connecting...';

  @override
  void initState() {
    super.initState();
    _service.start();
    _service.stream.listen(
      (snapshot) => setState(() {
        _snapshot = snapshot;
        _status = 'Connected';
      }),
      onError: (_) => setState(() => _status = 'Error'),
    );

    // If no response within 5s, show disconnected
    Future.delayed(const Duration(seconds: 5), () {
      if (_snapshot == null && mounted) {
        setState(() => _status = 'Disconnected');
      }
    });
  }

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Feature Flag Demo',
      debugShowCheckedModeBanner: false,
      home: HomeScreen(snapshot: _snapshot, connectionStatus: _status),
    );
  }
}