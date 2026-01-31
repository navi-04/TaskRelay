import 'package:intl/intl.dart';

/// Utility class for date operations
class DateHelper {
  /// Returns today's date with time set to midnight
  static DateTime getToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
  
  /// Returns yesterday's date
  static DateTime getYesterday() {
    return getToday().subtract(const Duration(days: 1));
  }
  
  /// Formats date to string (yyyy-MM-dd)
  static String formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }
  
  /// Parses string to date
  static DateTime parseDate(String dateString) {
    return DateFormat('yyyy-MM-dd').parse(dateString);
  }
  
  /// Formats date for display (e.g., "Jan 29, 2026")
  static String formatDateForDisplay(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }
  
  /// Checks if two dates are the same day
  static bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
  
  /// Gets the start of the month
  static DateTime getStartOfMonth(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }
  
  /// Gets the end of the month
  static DateTime getEndOfMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0);
  }
  
  /// Checks if date is today
  static bool isToday(DateTime date) {
    return isSameDay(date, getToday());
  }
  
  /// Checks if date is in the past
  static bool isPast(DateTime date) {
    return date.isBefore(getToday());
  }
  
  /// Checks if date is in the future
  static bool isFuture(DateTime date) {
    return date.isAfter(getToday());
  }
  
  /// Gets list of dates between two dates (inclusive)
  static List<DateTime> getDateRange(DateTime start, DateTime end) {
    final dates = <DateTime>[];
    DateTime current = start;
    
    while (!current.isAfter(end)) {
      dates.add(current);
      current = current.add(const Duration(days: 1));
    }
    
    return dates;
  }
  
  /// Gets day name (e.g., "Monday")
  static String getDayName(DateTime date) {
    return DateFormat('EEEE').format(date);
  }
  
  /// Gets short day name (e.g., "Mon")
  static String getShortDayName(DateTime date) {
    return DateFormat('EEE').format(date);
  }
}
