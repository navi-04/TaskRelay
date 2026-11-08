import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/time.dart';
import '../data/api.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../platform/platform_bridge.dart';

// ── plumbing ─────────────────────────────────────────────────────────────────────────────────────

final httpClientProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

/// Overridden in main() so the first request already carries the right `X-App-Version`.
final appVersionProvider = Provider<String>((ref) => '2.0.0');

/// The clock. Screens CALL it when they build (so the time is current, not the time the app started); tests pin it by overriding
/// the provider with a fixed value.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final bridgeProvider = Provider<PlatformBridge>((ref) => PlatformBridge());

// ── session ──────────────────────────────────────────────────────────────────────────────────────

sealed class Session {
  const Session();
}

class SessionLoading extends Session {
  const SessionLoading();
}

class SignedOut extends Session {
  const SignedOut();
}

class SignedIn extends Session {
  const SignedIn(this.token);
  final String token;
}

/// The server told us this app version is too old.
class UpgradeRequired extends Session {
  const UpgradeRequired();
}

/// The signed-in state. The token itself lives in the native layer (Android Keystore), which is also what lets the
/// background sync and the alarms keep working when the app is closed.
class SessionNotifier extends Notifier<Session> {
  @override
  Session build() {
    unawaited(_load());
    return const SessionLoading();
  }

  Future<void> _load() async {
    final s = await ref.read(bridgeProvider).getSession();
    state = s == null ? const SignedOut() : SignedIn(s.token);
  }

  Api _anonymous() => Api(ApiClient(
        client: ref.read(httpClientProvider),
        baseUrl: Config.apiBase,
        token: () => null,
        appVersion: () => ref.read(appVersionProvider),
        onUpgradeRequired: upgradeRequired,
      ));

  Future<void> authenticate({required String email, required String password, required bool register}) async {
    final bridge = ref.read(bridgeProvider);
    final tz = await bridge.timeZone() ?? 'UTC';
    final api = _anonymous();
    final token = register ? await api.register(email, password, tz) : await api.login(email, password);
    await bridge.setSession(Config.apiBase, token);
    state = SignedIn(token);
    unawaited(syncTimezone());
  }

  /// Keep the server's notion of "today" equal to this phone's timezone. Best effort.
  Future<void> syncTimezone() async {
    try {
      final tz = await ref.read(bridgeProvider).timeZone();
      if (tz == null || state is! SignedIn) return;
      final api = ref.read(apiProvider);
      final me = await api.me();
      if (me.timezone != tz) {
        await api.setTimezone(tz);
        ref.invalidate(dayViewProvider);
        ref.invalidate(statsProvider);
        ref.invalidate(meProvider);
      }
    } catch (_) {
      // offline: it will be retried on the next resume
    }
  }

  Future<void> signOut() async {
    try {
      await ref.read(apiProvider).logout();
    } catch (_) {
      // sign out locally even if the server can't be reached
    }
    await _clear();
  }

  /// A request got 401: the session expired or was revoked.
  Future<void> expire() async {
    if (state is SignedIn) await _clear();
  }

  void upgradeRequired() => state = const UpgradeRequired();

  Future<void> _clear() async {
    await ref.read(bridgeProvider).clearSession();
    state = const SignedOut();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session>(SessionNotifier.new);

/// The API for the signed-in user. Rebuilt on sign-in/out, so every provider that watches it refreshes with it.
final apiProvider = Provider<Api>((ref) {
  final session = ref.watch(sessionProvider);
  final token = session is SignedIn ? session.token : null;
  return Api(ApiClient(
    client: ref.watch(httpClientProvider),
    baseUrl: Config.apiBase,
    token: () => token,
    appVersion: () => ref.read(appVersionProvider),
    onUnauthorized: () => Future.microtask(() => ref.read(sessionProvider.notifier).expire()),
    onUpgradeRequired: () => Future.microtask(() => ref.read(sessionProvider.notifier).upgradeRequired()),
  ));
});

// ── data ─────────────────────────────────────────────────────────────────────────────────────────

/// One day. `null` = today (as the server computes it for the user's timezone).
final dayViewProvider = FutureProvider.autoDispose.family<DayView, String?>((ref, date) => ref.watch(apiProvider).dayView(date));

final labelsProvider = FutureProvider<Labels>((ref) => ref.watch(apiProvider).labels());

final settingsProvider = FutureProvider<Settings>((ref) => ref.watch(apiProvider).settings());

final meProvider = FutureProvider<Me>((ref) => ref.watch(apiProvider).me());

typedef DateRange = ({String? from, String? to});

/// Per-day totals for a range (up to 62 days), plus the streak and the rolling week. `(from: null, to: null)` = last 7 days.
final statsProvider = FutureProvider.autoDispose.family<StatsView, DateRange>((ref, r) => ref.watch(apiProvider).stats(from: r.from, to: r.to));

final habitsProvider = FutureProvider.autoDispose.family<List<Habit>, int>((ref, days) => ref.watch(apiProvider).habits(days: days));

final sheetProvider = FutureProvider.autoDispose.family<SheetView, DateRange>((ref, r) => ref.watch(apiProvider).sheet(from: r.from, to: r.to));

final reviewProvider = FutureProvider.autoDispose.family<Review, String?>((ref, weekStart) => ref.watch(apiProvider).review(weekStart: weekStart));

final activityProvider = FutureProvider.autoDispose<List<ActivityItem>>((ref) => ref.watch(apiProvider).activity());

final syncStatusProvider = FutureProvider.autoDispose<SyncStatus>((ref) => ref.watch(bridgeProvider).syncStatus());

// ── the app blocker: its settings live in the native layer (it enforces them), so these only mirror it ──

class BlockerController extends AsyncNotifier<BlockerConfig> {
  @override
  Future<BlockerConfig> build() {
    ref.watch(sessionProvider); // signing out wipes the native copy, so start over on the next sign-in
    return ref.read(bridgeProvider).blockerConfig();
  }

  /// Shows the change at once, then keeps whatever the native side stored (it drops protected apps and bad windows).
  Future<void> save(BlockerConfig next) async {
    state = AsyncData(next);
    final stored = await ref.read(bridgeProvider).setBlockerConfig(next);
    state = AsyncData(stored);
    ref.invalidate(blockerStatusProvider);
  }
}

final blockerConfigProvider = AsyncNotifierProvider<BlockerController, BlockerConfig>(BlockerController.new);

/// Is the accessibility service on, and is the blocker holding apps back right now? Re-read after changes and on resume.
final blockerStatusProvider = FutureProvider.autoDispose<BlockerStatus>((ref) => ref.watch(bridgeProvider).blockerStatus());

final installedAppsProvider = FutureProvider<List<InstalledApp>>((ref) => ref.watch(bridgeProvider).blockerApps());

/// One app's icon, loaded once and kept for the session.
final appIconProvider = FutureProvider.family<Uint8List?, String>((ref, package) => ref.watch(bridgeProvider).blockerAppIcon(package));

// ── actions ──────────────────────────────────────────────────────────────────────────────────────

/// A message plus the call that reverses what just happened (shown as a snackbar "Undo").
class UndoAction {
  const UndoAction(this.message, this.undo);
  final String message;
  final Future<void> Function() undo;
}

/// Every change the user makes goes through here: call the server, then refresh what depends on it and ask the native
/// layer to re-sync alarms. Failures throw an [ApiException] and nothing pretends to have worked.
class TaskActions {
  TaskActions(this._ref);
  final Ref _ref;

  Api get _api => _ref.read(apiProvider);

  /// Re-read what is on screen (without asking the native layer to sync again, e.g. after IT told us something changed).
  void refresh() {
    _ref.invalidate(dayViewProvider);
    _ref.invalidate(statsProvider);
    _ref.invalidate(habitsProvider);
    _ref.invalidate(sheetProvider);
    _ref.invalidate(reviewProvider);
    _ref.invalidate(syncStatusProvider);
  }

  void changed() {
    _ref.invalidate(dayViewProvider);
    _ref.invalidate(statsProvider);
    _ref.invalidate(habitsProvider);
    _ref.invalidate(sheetProvider);
    _ref.invalidate(reviewProvider);
    unawaited(_ref.read(bridgeProvider).requestSync());
  }

  Future<T> _run<T>(Future<T> Function() fn) async {
    final r = await fn();
    changed();
    return r;
  }

  Future<Task> create(Json body) => _run(() => _api.createTask(body));

  Future<Task> update(String id, Json patch) => _run(() => _api.updateTask(id, patch));

  /// Tick or untick one task on one day, from the spreadsheet (which knows ids and dates but holds no [Task]).
  Future<void> setCell(String taskId, String date, bool done) => _run(() => _api.setDay(taskId, date, done ? 'done' : 'open'));

  Future<void> setDone(Task t, bool done) => _run(() => _api.setDay(t.id, t.date, done ? 'done' : 'open'));

  Future<void> setNote(Task t, String? note) => _run(() => _api.setDay(t.id, t.date, t.status, note: note, withNote: true));

  Future<Task> restore(String id) => _run(() => _api.restoreTask(id));

  Future<void> setTop(String date, List<String> ids) => _run(() => _api.setTop(date, ids));

  /// Delete with a [scope] (`all` | `day:D` | `from:D`) and get back how to undo exactly that.
  Future<UndoAction> delete(Task t, String scope) async {
    await _run(() => _api.deleteTask(t.id, scope));
    final wholeTask = scope == 'all' || !t.isRepeating || (scope.startsWith('from:') && scope.substring(5).compareTo(t.dueDate) <= 0);
    if (wholeTask) return UndoAction('Deleted “${t.title}”', () => restore(t.id));
    if (scope.startsWith('day:')) {
      final day = scope.substring(4);
      return UndoAction('Skipped that day', () => _run(() => _api.setDay(t.id, day, 'open')));
    }
    return UndoAction('Series ended', () => update(t.id, {'recur_until': t.recurUntil})); // put the old end date back
  }

  /// Move the overdue tasks to today; undo moves each back to its own day.
  Future<UndoAction> moveOverdue(List<Task> items, String today) async {
    final byDay = <String, List<String>>{};
    for (final t in items) {
      (byDay[t.dueDate] ??= []).add(t.id);
    }
    await _run(() => _api.moveTasks(items.map((t) => t.id).toList(), today));
    return UndoAction('Moved ${items.length} to today', () async {
      for (final e in byDay.entries) {
        await _api.moveTasks(e.value, e.key);
      }
      changed();
    });
  }

  Future<void> deleteAllTasks() => _run(() => _api.deleteAllTasks());
}

final taskActionsProvider = Provider<TaskActions>((ref) => TaskActions(ref));

/// The date the Today tab shows (null = today). Kept here so deep links (calendar day, search result) can set it.
final todayDateProvider = StateProvider<String?>((ref) => null);

/// "Today" for UI that only needs a date before the server's answer arrives: the device's date.
String deviceToday() => todayYmd();

/// Something outside the Today screen (the share target, the widget's "+") asks it to open the add form.
class AddRequest {
  const AddRequest([this.prefill]);
  final SharedText? prefill;
}

final addRequestProvider = StateProvider<AddRequest?>((ref) => null);

/// The selected bottom-navigation tab (0 Today, 1 Calendar, 2 Profile).
final tabIndexProvider = StateProvider<int>((ref) => 0);
