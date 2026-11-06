import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TimerState {
  final String? activeTaskId;
  final bool isRunning;
  final Map<String, int> taskElapsed; // taskId -> accumulated seconds

  const TimerState({
    this.activeTaskId,
    this.isRunning = false,
    this.taskElapsed = const {},
  });

  TimerState copyWith({
    Object? activeTaskId = _unset,
    bool? isRunning,
    Map<String, int>? taskElapsed,
  }) {
    return TimerState(
      activeTaskId: activeTaskId is _Unset ? this.activeTaskId : activeTaskId as String?,
      isRunning: isRunning ?? this.isRunning,
      taskElapsed: taskElapsed ?? this.taskElapsed,
    );
  }
}

class _Unset {
  const _Unset();
}
const _unset = _Unset();

class TimerNotifier extends StateNotifier<TimerState> {
  Timer? _ticker;

  TimerNotifier() : super(const TimerState());

  void startTimer(String taskId) {
    if (state.activeTaskId == taskId && state.isRunning) return;

    // Pause any active timer first
    if (state.isRunning && state.activeTaskId != null) {
      _ticker?.cancel();
    }

    state = state.copyWith(activeTaskId: taskId, isRunning: true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = Map<String, int>.from(state.taskElapsed);
      current[taskId] = (current[taskId] ?? 0) + 1;
      state = state.copyWith(taskElapsed: current);
    });
  }

  void pauseTimer() {
    _ticker?.cancel();
    state = state.copyWith(isRunning: false);
  }

  void stopTimer(String taskId) {
    _ticker?.cancel();
    final current = Map<String, int>.from(state.taskElapsed);
    current.remove(taskId);
    state = TimerState(taskElapsed: current);
  }

  void resetTimer(String taskId) {
    final wasCurrent = state.activeTaskId == taskId;
    if (wasCurrent) {
      _ticker?.cancel();
    }
    final current = Map<String, int>.from(state.taskElapsed);
    current[taskId] = 0;
    state = state.copyWith(
      activeTaskId: wasCurrent ? null : state.activeTaskId,
      isRunning: wasCurrent ? false : state.isRunning,
      taskElapsed: current,
    );
  }

  int getElapsedForTask(String taskId) => state.taskElapsed[taskId] ?? 0;

  static String formatElapsed(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final timerProvider = StateNotifierProvider<TimerNotifier, TimerState>(
  (ref) => TimerNotifier(),
);
