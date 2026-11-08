import 'dart:async';

import 'package:flutter/services.dart';

/// The result of a background-sync pass in the native layer.
class SyncResult {
  const SyncResult({required this.ok, this.notModified = false, this.errorCode, this.error, this.armedCount = 0, this.armedThrough, this.syncedAtMs});
  final bool ok;
  final bool notModified;

  /// unauthorized | upgrade_required | rate_limited | network | server | not_signed_in
  final String? errorCode;
  final String? error;
  final int armedCount;
  final String? armedThrough;
  final int? syncedAtMs;

  bool get unauthorized => errorCode == 'unauthorized';
  bool get upgradeRequired => errorCode == 'upgrade_required';

  factory SyncResult.fromMap(Map<dynamic, dynamic>? m) => m == null
      ? const SyncResult(ok: false, errorCode: 'server')
      : SyncResult(
          ok: m['ok'] == true,
          notModified: m['notModified'] == true,
          errorCode: m['errorCode'] as String?,
          error: m['error'] as String?,
          armedCount: (m['armedCount'] as num?)?.toInt() ?? 0,
          armedThrough: m['armedThrough'] as String?,
          syncedAtMs: (m['syncedAtMs'] as num?)?.toInt(),
        );
}

/// Alarm and sync health as the native layer sees it (shown in Profile).
class SyncStatus {
  const SyncStatus({
    this.signedIn = false,
    this.lastSyncMs,
    this.armedCount = 0,
    this.armedThrough,
    this.nextAlarmMs,
    this.pendingActions = 0,
    this.lastError,
    this.lastErrorCode,
    this.exactAlarmAllowed = true,
    this.notificationsAllowed = true,
    this.fullScreenIntentAllowed = true,
  });
  final bool signedIn;
  final int? lastSyncMs;
  final int armedCount;
  final String? armedThrough;
  final int? nextAlarmMs;
  final int pendingActions;
  final String? lastError;
  final String? lastErrorCode;
  final bool exactAlarmAllowed;
  final bool notificationsAllowed;
  final bool fullScreenIntentAllowed;

  bool get permissionsOk => exactAlarmAllowed && notificationsAllowed && fullScreenIntentAllowed;

  factory SyncStatus.fromMap(Map<dynamic, dynamic> m) => SyncStatus(
        signedIn: m['signedIn'] == true,
        lastSyncMs: (m['lastSyncMs'] as num?)?.toInt(),
        armedCount: (m['armedCount'] as num?)?.toInt() ?? 0,
        armedThrough: m['armedThrough'] as String?,
        nextAlarmMs: (m['nextAlarmMs'] as num?)?.toInt(),
        pendingActions: (m['pendingActions'] as num?)?.toInt() ?? 0,
        lastError: m['lastError'] as String?,
        lastErrorCode: m['lastErrorCode'] as String?,
        exactAlarmAllowed: m['exactAlarmAllowed'] != false,
        notificationsAllowed: m['notificationsAllowed'] != false,
        fullScreenIntentAllowed: m['fullScreenIntentAllowed'] != false,
      );
}

class Permissions {
  const Permissions({this.notifications = true, this.exactAlarm = true, this.fullScreenIntent = true});
  final bool notifications;
  final bool exactAlarm;
  final bool fullScreenIntent;
  bool get allGranted => notifications && exactAlarm && fullScreenIntent;
}

class SharedText {
  const SharedText({this.subject, this.text});
  final String? subject;
  final String? text;

  /// A sensible task title from shared text: the subject, or the first non-empty line, capped at 200 characters.
  String get title {
    final candidates = [subject, ...?text?.split('\n')].map((s) => (s ?? '').trim()).where((s) => s.isNotEmpty);
    final first = candidates.isEmpty ? '' : candidates.first;
    return first.length > 200 ? first.substring(0, 200) : first;
  }

  /// The rest of the shared text goes into the task's notes.
  String get notes {
    final all = [subject, text].where((s) => s != null && s.trim().isNotEmpty).map((s) => s!.trim()).join('\n');
    final t = title;
    final rest = all.startsWith(t) ? all.substring(t.length).trim() : all;
    return rest.length > 4000 ? rest.substring(0, 4000) : rest;
  }
}

// ── the app blocker (settings live on the phone only; the native layer enforces them) ──

/// How the blocked apps are held back.
enum BlockMode {
  /// Blocked while any task is left today; everything unlocks when the last one is done.
  untilDone('until_done'),

  /// Blocked only while a task with a start time is running; free the rest of the time.
  freeTime('free_time'),

  /// Blocked except inside the use times the user set (a running task still blocks).
  setTimes('set_times');

  const BlockMode(this.wire);
  final String wire;

  static BlockMode fromWire(Object? v) => values.firstWhere((m) => m.wire == v, orElse: () => untilDone);
}

/// A window in which the blocked apps may be used, on the given weekdays (1=Mon..7=Sun).
class UseWindow {
  const UseWindow({required this.start, required this.end, this.days = const [1, 2, 3, 4, 5, 6, 7]});
  final String start; // 'HH:mm'
  final String end; // 'HH:mm', after [start] on the same day
  final List<int> days;

  bool get isEveryDay => days.length == 7;

  Map<String, Object?> toMap() => {'start': start, 'end': end, 'days': days};

  factory UseWindow.fromMap(Map<dynamic, dynamic> m) => UseWindow(
        start: m['start'] as String,
        end: m['end'] as String,
        days: ((m['days'] as List?) ?? const [1, 2, 3, 4, 5, 6, 7]).map((e) => (e as num).toInt()).toList(),
      );

  @override
  bool operator ==(Object other) => other is UseWindow && other.start == start && other.end == end && other.days.join(',') == days.join(',');

  @override
  int get hashCode => Object.hash(start, end, days.join(','));
}

class BlockerConfig {
  const BlockerConfig({
    this.enabled = false,
    this.mode = BlockMode.untilDone,
    this.countOverdue = true,
    this.unlockWhenDone = false,
    this.packages = const [],
    this.windows = const [],
  });
  final bool enabled;
  final BlockMode mode;

  /// "Until my tasks are done": do overdue tasks count as work left?
  final bool countOverdue;

  /// "Only at set times": also unlock everything once all tasks are done.
  final bool unlockWhenDone;
  final List<String> packages;
  final List<UseWindow> windows;

  BlockerConfig copyWith({bool? enabled, BlockMode? mode, bool? countOverdue, bool? unlockWhenDone, List<String>? packages, List<UseWindow>? windows}) => BlockerConfig(
        enabled: enabled ?? this.enabled,
        mode: mode ?? this.mode,
        countOverdue: countOverdue ?? this.countOverdue,
        unlockWhenDone: unlockWhenDone ?? this.unlockWhenDone,
        packages: packages ?? this.packages,
        windows: windows ?? this.windows,
      );

  Map<String, Object?> toMap() => {
        'enabled': enabled,
        'mode': mode.wire,
        'count_overdue': countOverdue,
        'unlock_when_done': unlockWhenDone,
        'packages': packages,
        'windows': windows.map((w) => w.toMap()).toList(),
      };

  factory BlockerConfig.fromMap(Map<dynamic, dynamic>? m) => m == null
      ? const BlockerConfig()
      : BlockerConfig(
          enabled: m['enabled'] == true,
          mode: BlockMode.fromWire(m['mode']),
          countOverdue: m['count_overdue'] != false,
          unlockWhenDone: m['unlock_when_done'] == true,
          packages: ((m['packages'] as List?) ?? const []).cast<String>(),
          windows: ((m['windows'] as List?) ?? const []).map((w) => UseWindow.fromMap(w as Map<dynamic, dynamic>)).toList(),
        );
}

/// What the phone's blocker decides about the blocked apps right now (see BlockerPolicy.kt).
class BlockerDecision {
  const BlockerDecision({this.blocked = false, this.code = 'off', this.left = 0, this.overdue = 0, this.title, this.untilMin, this.nextStartMin});
  final bool blocked;

  /// off | no_data | all_done | free_time | in_window | tasks_left | task_block | outside_windows
  final String code;
  final int left;
  final int overdue;

  /// The running task's title, for `task_block`.
  final String? title;

  /// Minute of the day (0..1440) the current state lasts until, when known.
  final int? untilMin;

  /// Minute of the day the next use time starts, for `outside_windows`.
  final int? nextStartMin;

  factory BlockerDecision.fromMap(Map<dynamic, dynamic>? m) => m == null
      ? const BlockerDecision()
      : BlockerDecision(
          blocked: m['blocked'] == true,
          code: (m['code'] as String?) ?? 'off',
          left: (m['left'] as num?)?.toInt() ?? 0,
          overdue: (m['overdue'] as num?)?.toInt() ?? 0,
          title: m['title'] as String?,
          untilMin: (m['until_min'] as num?)?.toInt(),
          nextStartMin: (m['next_start_min'] as num?)?.toInt(),
        );
}

class BlockerStatus {
  const BlockerStatus({this.serviceEnabled = false, this.enabled = false, this.hasData = false, this.snapshotDate, this.decision = const BlockerDecision()});

  /// Is TaskRelay switched on in Android's Accessibility settings? Nothing is blocked until it is.
  final bool serviceEnabled;
  final bool enabled;
  final bool hasData;
  final String? snapshotDate;
  final BlockerDecision decision;

  factory BlockerStatus.fromMap(Map<dynamic, dynamic>? m) => m == null
      ? const BlockerStatus()
      : BlockerStatus(
          serviceEnabled: m['serviceEnabled'] == true,
          enabled: m['enabled'] == true,
          hasData: m['hasData'] == true,
          snapshotDate: m['snapshotDate'] as String?,
          decision: BlockerDecision.fromMap(m['decision'] as Map<dynamic, dynamic>?),
        );
}

/// An app that can be opened from the launcher (and so can be blocked).
class InstalledApp {
  const InstalledApp({required this.package, required this.label});
  final String package;
  final String label;
}

/// The only place that talks to the Android native layer (alarms, background sync, the session token, the widget,
/// permissions and the share target). On other platforms, and in tests, every call degrades to a harmless default.
class PlatformBridge {
  PlatformBridge([MethodChannel? channel]) : _ch = channel ?? const MethodChannel('com.naveenraj.taskrelay/native') {
    _ch.setMethodCallHandler(_fromNative);
  }

  final MethodChannel _ch;
  final _actions = StreamController<void>.broadcast();
  final _shares = StreamController<SharedText>.broadcast();
  final _syncs = StreamController<SyncResult>.broadcast();

  /// A task was completed natively (lock-screen alarm, notification or widget): refresh what is on screen.
  Stream<void> get actionsChanged => _actions.stream;

  /// Text shared into the app while it was already running.
  Stream<SharedText> get shares => _shares.stream;

  Stream<SyncResult> get syncFinished => _syncs.stream;

  Future<dynamic> _fromNative(MethodCall call) async {
    switch (call.method) {
      case 'onActionsChanged':
        _actions.add(null);
      case 'onShare':
        final m = call.arguments as Map<dynamic, dynamic>;
        _shares.add(SharedText(subject: m['subject'] as String?, text: m['text'] as String?));
      case 'onSyncFinished':
        _syncs.add(SyncResult.fromMap(call.arguments as Map<dynamic, dynamic>?));
    }
    return null;
  }

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null; // not Android / not wired (tests)
    } on PlatformException {
      return null;
    }
  }

  // ── session ──
  Future<({String baseUrl, String token})?> getSession() async {
    final m = await _call<Map<dynamic, dynamic>>('getSession');
    if (m == null || m['token'] == null) return null;
    return (baseUrl: m['baseUrl'] as String, token: m['token'] as String);
  }

  Future<void> setSession(String baseUrl, String token) => _call('setSession', {'baseUrl': baseUrl, 'token': token});

  Future<void> clearSession() => _call('clearSession');

  // ── sync ──
  Future<SyncResult> syncNow() async => SyncResult.fromMap(await _call<Map<dynamic, dynamic>>('syncNow'));

  /// Ask for a background sync soon (bursts are coalesced natively).
  Future<void> requestSync() => _call('requestSync');

  Future<SyncStatus> syncStatus() async {
    final m = await _call<Map<dynamic, dynamic>>('getSyncStatus');
    return m == null ? const SyncStatus() : SyncStatus.fromMap(m);
  }

  // ── permissions ──
  Future<Permissions> permissions() async {
    final m = await _call<Map<dynamic, dynamic>>('getPermissionStatus');
    if (m == null) return const Permissions();
    return Permissions(notifications: m['notifications'] != false, exactAlarm: m['exactAlarm'] != false, fullScreenIntent: m['fullScreenIntent'] != false);
  }

  Future<bool> requestNotifications() async => await _call<bool>('requestNotificationPermission') ?? true;

  Future<void> openExactAlarmSettings() => _call('openExactAlarmSettings');

  Future<void> openFullScreenIntentSettings() => _call('openFullScreenIntentSettings');

  Future<void> openNotificationSettings() => _call('openNotificationSettings');

  // ── device ──
  Future<String?> timeZone() => _call<String>('getTimeZone');

  Future<String> appVersion() async => await _call<String>('getAppVersion') ?? '2.0.0';

  // ── launch inputs ──
  Future<SharedText?> initialShare() async {
    final m = await _call<Map<dynamic, dynamic>>('getInitialShare');
    return m == null ? null : SharedText(subject: m['subject'] as String?, text: m['text'] as String?);
  }

  /// "add" when the widget's + button launched the app.
  Future<String?> launchAction() => _call<String>('getLaunchAction');

  // ── app blocker ──
  Future<BlockerConfig> blockerConfig() async => BlockerConfig.fromMap(await _call<Map<dynamic, dynamic>>('blockerGetConfig'));

  /// Stores the config (the native side normalises it) and returns what it kept.
  Future<BlockerConfig> setBlockerConfig(BlockerConfig c) async => BlockerConfig.fromMap(await _call<Map<dynamic, dynamic>>('blockerSetConfig', c.toMap()) ?? c.toMap());

  Future<BlockerStatus> blockerStatus() async => BlockerStatus.fromMap(await _call<Map<dynamic, dynamic>>('blockerStatus'));

  Future<List<InstalledApp>> blockerApps() async {
    final list = await _call<List<dynamic>>('blockerListApps');
    return (list ?? const []).map((e) => e as Map<dynamic, dynamic>).map((m) => InstalledApp(package: m['package'] as String, label: m['label'] as String)).toList();
  }

  /// A small PNG of the app's icon, or null.
  Future<Uint8List?> blockerAppIcon(String package) => _call<Uint8List>('blockerAppIcon', {'package': package});

  Future<void> openAccessibilitySettings() => _call('blockerOpenAccessibilitySettings');

  Future<void> refreshWidget() => _call('refreshWidget');
}
