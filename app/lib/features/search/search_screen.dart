import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api_exception.dart';
import '../../data/models.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';

/// Search every task by title or notes, across all dates.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _text = TextEditingController();
  Timer? _debounce;
  int _latest = 0;
  List<Task> _items = const [];
  bool _hasMore = false;
  String? _searched;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      _latest++;
      setState(() {
        _items = const [];
        _searched = null;
        _hasMore = false;
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(q, 0));
  }

  Future<void> _load(String q, int offset) async {
    final mine = ++_latest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(apiProvider).search(q, offset: offset);
      if (!mounted || mine != _latest) return; // a newer search replaced this one
      setState(() {
        _items = offset == 0 ? page.items : [..._items, ...page.items];
        _hasMore = page.hasMore;
        _searched = q;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted && mine == _latest) {
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  void _openDay(Task t) {
    ref.read(todayDateProvider.notifier).state = t.dueDate;
    ref.read(tabIndexProvider.notifier).state = 0;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(hintText: 'Search titles and notes…', prefixIcon: Icon(Icons.search)),
            onChanged: _onChanged,
          ),
          Padding(padding: const EdgeInsets.only(top: 6, bottom: 12), child: Text('Searches every date, including finished tasks.', style: TextStyle(color: t.muted, fontSize: 12))),
          if (_error != null) ErrorBanner(message: _error!, onRetry: () => _load(_text.text.trim(), 0)),
          if (_loading && _items.isEmpty) const SkeletonRows(rows: 3),
          if (_searched != null && !_loading && _items.isEmpty && _error == null) SurfaceCard(child: EmptyState(title: 'No tasks match “$_searched”', message: 'Try a different word.', icon: Icons.search_off)),
          if (_items.isNotEmpty)
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                for (final task in _items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(task.title, style: TextStyle(fontWeight: FontWeight.w600, decoration: task.isDone ? TextDecoration.lineThrough : null)),
                    subtitle: Text([fmtDay(task.dueDate), task.isDone ? '✓ done' : (task.status == 'skipped' ? 'skipped' : 'open'), fmtMinutes(task.durationMin), if (task.isRepeating) '↻ ${repeatLabel(repeating: true, days: task.recurDays)}'].join(' · ')),
                    trailing: TextButton(onPressed: () => _openDay(task), child: const Text('Open day')),
                    onTap: () => _openDay(task),
                  ),
                if (_hasMore) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: OutlinedButton(onPressed: _loading ? null : () => _load(_text.text.trim(), _items.length), child: Text(_loading ? 'Loading…' : 'Load more'))),
              ]),
            ),
        ],
      ),
    );
  }
}
