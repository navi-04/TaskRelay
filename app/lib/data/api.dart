import 'api_client.dart';
import 'models.dart';

/// Every call the app makes, typed. Thin on purpose: the server owns the logic.
class Api {
  const Api(this._c);
  final ApiClient _c;

  Json _map(dynamic v) => v as Json;

  // ── account ──────────────────────────────────────────────────────────────────────────────────
  /// Returns the session token (apps get it in the body; the web gets a cookie instead).
  Future<String> login(String email, String password) async => _map(await _c.post('/auth/login', body: {'email': email, 'password': password}))['token'] as String;

  Future<String> register(String email, String password, String timezone) async =>
      _map(await _c.post('/auth/register', body: {'email': email, 'password': password, 'timezone': timezone}))['token'] as String;

  Future<void> logout() => _c.post('/auth/logout');

  Future<Me> me() async => Me.fromJson(_map(await _c.get('/me')));

  Future<Me> setTimezone(String tz) async => Me.fromJson(_map(await _c.patch('/me', body: {'timezone': tz})));

  Future<Me> setAiEnabled(bool enabled) async => Me.fromJson(_map(await _c.patch('/me/ai-access', body: {'enabled': enabled})));

  Future<String> regenerateAiAccess() async => _map(await _c.post('/me/ai-access/regenerate'))['ai_access_id'] as String;

  Future<void> changePassword(String current, String next) => _c.post('/me/password', body: {'current_password': current, 'new_password': next});

  Future<void> deleteAccount(String password) => _c.delete('/me', body: {'password': password});

  Future<void> deleteAllTasks() => _c.delete('/me/data');

  Future<List<int>> exportData() => _c.download('/me/export');

  // ── tasks ────────────────────────────────────────────────────────────────────────────────────
  /// One day's tasks. `null` = today in the user's timezone (the server decides).
  Future<DayView> dayView(String? date) async => DayView.fromJson(_map(await _c.get('/tasks', query: date == null ? null : {'date': date})));

  /// The client chooses `id`, so a retried request after a timeout cannot create a duplicate.
  Future<Task> createTask(Json body) async => Task.fromJson(_map(await _c.post('/tasks', body: body, idempotent: true)));

  Future<Task> updateTask(String id, Json patch) async => Task.fromJson(_map(await _c.patch('/tasks/$id', body: patch)));

  /// scope: `all` | `day:YYYY-MM-DD` | `from:YYYY-MM-DD`.
  Future<void> deleteTask(String id, String scope) => _c.delete('/tasks/$id', query: {'scope': scope});

  Future<Task> restoreTask(String id) async => Task.fromJson(_map(await _c.post('/tasks/$id/restore', idempotent: true)));

  /// Set one task's state on one day: done | skipped | open. Idempotent, never a toggle.
  Future<Task> setDay(String id, String date, String status, {String? note, bool withNote = false}) async => Task.fromJson(
        _map(await _c.put('/tasks/$id/days/$date', body: {'status': status, if (withNote) 'note': note})),
      );

  /// Move open one-off tasks (up to 50) to another day. Returns the ids that were moved.
  Future<List<String>> moveTasks(List<String> ids, String to) async =>
      ((_map(await _c.post('/tasks/move', body: {'ids': ids, 'to': to}))['moved']) as List).cast<String>();

  Future<DayView> setTop(String date, List<String> taskIds) async => DayView.fromJson(_map(await _c.put('/days/$date/top', body: {'task_ids': taskIds})));

  // ── labels & settings ────────────────────────────────────────────────────────────────────────
  Future<Labels> labels() async => Labels.fromJson(_map(await _c.get('/labels')));

  Future<Label> createLabel(String kind, String label) async => Label.fromJson(_map(await _c.post('/labels', body: {'kind': kind, 'label': label})));

  Future<Label> renameLabel(String id, String label) async => Label.fromJson(_map(await _c.patch('/labels/$id', body: {'label': label})));

  Future<void> deleteLabel(String id) => _c.delete('/labels/$id');

  Future<Settings> settings() async => Settings.fromJson(_map(await _c.get('/settings')));

  Future<Settings> patchSettings(Json patch) async => Settings.fromJson(_map(await _c.patch('/settings', body: patch)));

  // ── insights ─────────────────────────────────────────────────────────────────────────────────
  Future<StatsView> stats({String? from, String? to}) async =>
      StatsView.fromJson(_map(await _c.get('/stats', query: {if (from != null) 'from': from, if (to != null) 'to': to})));

  Future<List<Habit>> habits({int days = 90}) async {
    final j = _map(await _c.get('/habits', query: {'days': '$days'}));
    return ((j['habits'] as List?) ?? const []).map((h) => Habit.fromJson(h as Json)).toList();
  }

  Future<Review> review({String? weekStart}) async => Review.fromJson(_map(await _c.get('/review', query: weekStart == null ? null : {'week_start': weekStart})));

  Future<SearchPage> search(String q, {int offset = 0, int limit = 20}) async =>
      SearchPage.fromJson(_map(await _c.get('/search', query: {'q': q, 'offset': '$offset', 'limit': '$limit'})));

  Future<List<ActivityItem>> activity({int limit = 8}) async {
    final j = _map(await _c.get('/activity', query: {'limit': '$limit'}));
    return ((j['items'] as List?) ?? const []).map((i) => ActivityItem.fromJson(i as Json)).toList();
  }
}
