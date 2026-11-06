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

  Future<void> refreshWidget() => _call('refreshWidget');
}
