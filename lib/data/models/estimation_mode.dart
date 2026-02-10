/// How tasks are estimated/measured for daily progress.
enum EstimationMode {
  /// Track by time duration (hours & minutes). Default.
  timeBased,

  /// Track by weight (numeric weight per task).
  weightBased,

  /// Track by simple task count (no extra field needed).
  countBased;

  String get label {
    switch (this) {
      case EstimationMode.timeBased:
        return 'Time Based';
      case EstimationMode.weightBased:
        return 'Weight Based';
      case EstimationMode.countBased:
        return 'Count Based';
    }
  }

  String get description {
    switch (this) {
      case EstimationMode.timeBased:
        return 'Estimate tasks by hours & minutes';
      case EstimationMode.weightBased:
        return 'Estimate tasks by weight (1–100)';
      case EstimationMode.countBased:
        return 'Track by number of tasks completed';
    }
  }

  IconLabel get iconLabel {
    switch (this) {
      case EstimationMode.timeBased:
        return IconLabel('schedule', label);
      case EstimationMode.weightBased:
        return IconLabel('fitness_center', label);
      case EstimationMode.countBased:
        return IconLabel('format_list_numbered', label);
    }
  }
}

class IconLabel {
  final String iconName;
  final String text;
  const IconLabel(this.iconName, this.text);
}
