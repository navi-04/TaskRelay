import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'platform/platform_bridge.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final bridge = PlatformBridge();
  final version = await bridge.appVersion(); // sent as X-App-Version so the server can ask old apps to update

  runApp(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      bridgeProvider.overrideWithValue(bridge),
      appVersionProvider.overrideWithValue(version),
    ],
    child: const TaskRelayApp(),
  ));
}
