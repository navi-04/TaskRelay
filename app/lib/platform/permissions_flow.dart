import 'package:flutter/material.dart';

import 'platform_bridge.dart';

/// Which permission needs attention first (null when everything is allowed).
String? firstMissingPermission(Permissions p) {
  if (!p.notifications) return 'notifications';
  if (!p.exactAlarm) return 'exactAlarm';
  if (!p.fullScreenIntent) return 'fullScreenIntent';
  return null;
}

String permissionTitle(String key) => switch (key) {
      'notifications' => 'Notifications',
      'exactAlarm' => 'Exact alarms',
      _ => 'Full-screen alarms',
    };

String permissionWhy(String key) => switch (key) {
      'notifications' => 'TaskRelay needs notifications to show your reminders and alarms.',
      'exactAlarm' => 'Android needs this so alarms ring at the exact minute. Turn on “Alarms & reminders” for TaskRelay on the next screen.',
      _ => 'This lets an alarm take over the lock screen so you can’t miss it. Turn it on for TaskRelay on the next screen.',
    };

/// Fix ONE permission: explain it, then ask or open the right Android settings screen.
/// (Each screen leaves the app, so the caller calls this again after the user comes back, e.g. from a button or on resume.)
Future<void> fixPermission(BuildContext context, PlatformBridge bridge, String key) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(permissionTitle(key)),
      content: Text(permissionWhy(key)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue'))],
    ),
  );
  if (go != true) return;
  switch (key) {
    case 'notifications':
      final granted = await bridge.requestNotifications();
      if (!granted) await bridge.openNotificationSettings(); // permanently denied: only settings can change it
    case 'exactAlarm':
      await bridge.openExactAlarmSettings();
    default:
      await bridge.openFullScreenIntentSettings();
  }
}
