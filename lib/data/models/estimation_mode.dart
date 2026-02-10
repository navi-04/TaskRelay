/// How tasks are estimated/measured for daily progress.
enum EstimationMode {
  /// Track by time duration (hours & minutes). Default.
  timeBased,

  /// Track by simple task count (no extra field needed).
  countBased;

  String get label {
    switch (this) {
      case EstimationMode.timeBased:
        return 'Time Based';
      case EstimationMode.countBased:
        return 'Count Based';
    }
  }

  String get description {
    switch (this) {
      case EstimationMode.timeBased:
        return 'Estimate tasks by hours & minutes';
      case EstimationMode.countBased:
        return 'Track by number of tasks completed';
    }
  }

  IconLabel get iconLabel {
    switch (this) {
      case EstimationMode.timeBased:
        return IconLabel('schedule', label);
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
