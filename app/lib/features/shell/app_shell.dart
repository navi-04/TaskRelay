import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../platform/permissions_flow.dart';
import '../../platform/platform_bridge.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';
import '../calendar/calendar_screen.dart';
import '../profile/profile_screen.dart';
import '../sheet/sheet_screen.dart';
import '../today/today_screen.dart';

/// The signed-in app: three tabs, a sync on launch and on resume, and the glue to the native layer.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  final _subs = <StreamSubscription<dynamic>>[];
  DateTime? _lastSync;
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final bridge = ref.read(bridgeProvider);
    _subs
      // a task was completed natively (lock-screen alarm, notification, widget): show it
      ..add(bridge.actionsChanged.listen((_) => ref.read(taskActionsProvider).refresh()))
      ..add(bridge.shares.listen(_onShare))
      ..add(bridge.syncFinished.listen((r) {
        ref.invalidate(syncStatusProvider);
        _handle(r);
      }));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _launchInputs();
      _foregroundSync(force: true);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(taskActionsProvider).refresh();
      _foregroundSync();
      unawaited(_checkLaunchAction()); // the widget's "+" brings a running app forward with no push to Dart
    }
  }

  /// Text shared into the app, or the widget's "+": open the add form on the Today tab.
  Future<void> _launchInputs() async {
    final bridge = ref.read(bridgeProvider);
    final share = await bridge.initialShare();
    if (share != null && mounted) _onShare(share);
    await _checkLaunchAction();
  }

  /// "add" when the widget's + button started or resumed the app. Reading it consumes it, so it fires once.
  Future<void> _checkLaunchAction() async {
    if (await ref.read(bridgeProvider).launchAction() == 'add' && mounted) {
      ref.read(tabIndexProvider.notifier).state = 0;
      ref.read(addRequestProvider.notifier).state = const AddRequest();
    }
  }

  void _onShare(SharedText s) {
    ref.read(tabIndexProvider.notifier).state = 0;
    ref.read(addRequestProvider.notifier).state = AddRequest(s);
  }

  /// Sync alarms and reminders with the server (at most every 30 s unless forced) and keep the timezone right.
  Future<void> _foregroundSync({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastSync != null && now.difference(_lastSync!) < const Duration(seconds: 30)) return;
    _lastSync = now;
    final session = ref.read(sessionProvider.notifier);
    unawaited(session.syncTimezone());
    final result = await ref.read(bridgeProvider).syncNow();
    if (!mounted) return;
    ref.invalidate(syncStatusProvider);
    _handle(result);
  }

  void _handle(SyncResult r) {
    if (r.unauthorized) unawaited(ref.read(sessionProvider.notifier).expire());
    if (r.upgradeRequired) ref.read(sessionProvider.notifier).upgradeRequired();
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(tabIndexProvider);
    final status = ref.watch(syncStatusProvider).valueOrNull;
    // Only nag when there is something to ring: someone with no alarms is not asked for permissions on first launch.
    final missing = status == null || status.armedCount == 0 ? null : firstMissingPermission(Permissions(notifications: status.notificationsAllowed, exactAlarm: status.exactAlarmAllowed, fullScreenIntent: status.fullScreenIntentAllowed));

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(tabIndexProvider.notifier).state = 0; // back from another tab goes to Today first
      },
      child: Scaffold(
        body: Column(children: [
          if (missing != null && !_bannerDismissed)
            _PermissionBanner(
              what: permissionTitle(missing),
              onFix: () async {
                await fixPermission(context, ref.read(bridgeProvider), missing);
                ref.invalidate(syncStatusProvider);
              },
              onDismiss: () => setState(() => _bannerDismissed = true),
            ),
          Expanded(
            child: IndexedStack(index: index, children: const [TodayScreen(), CalendarScreen(), SheetScreen(), ProfileScreen()]),
          ),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => ref.read(tabIndexProvider.notifier).state = i,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.check_circle_outline), selectedIcon: Icon(Icons.check_circle), label: 'Today'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Calendar'),
            NavigationDestination(icon: Icon(Icons.grid_on_outlined), selectedIcon: Icon(Icons.grid_on), label: 'Sheet'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.what, required this.onFix, required this.onDismiss});
  final String what;
  final VoidCallback onFix;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Material(
      color: t.input,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 6), bottom: BorderSide(color: t.border))),
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(children: [
            Expanded(child: IconText(Icons.warning_amber_outlined, 'Allow “$what” so your reminders and alarms can ring.', iconSize: 16, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            TextButton(onPressed: onFix, child: const Text('Fix')),
            IconButton(tooltip: 'Dismiss', icon: const Icon(Icons.close, size: 18), onPressed: onDismiss),
          ]),
        ),
      ),
    );
  }
}
