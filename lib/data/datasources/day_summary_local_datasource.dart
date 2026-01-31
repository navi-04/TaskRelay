import 'package:hive/hive.dart';
import '../models/day_summary_entity.dart';

/// Local data source for DaySummary operations using Hive
class DaySummaryLocalDataSource {
  static const String _boxName = 'day_summary_box';
  
  Box<DaySummaryEntity>? _box;
  
  /// Initialize Hive box
  Future<void> init() async {
    try {
      _box = await Hive.openBox<DaySummaryEntity>(_boxName);
    } catch (e) {
      // If box fails to open (likely due to schema changes), delete and recreate
      print('Error opening day summary box: $e');
      print('Deleting corrupted box and creating new one...');
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox<DaySummaryEntity>(_boxName);
    }
  }
  
  Box<DaySummaryEntity> get _summaryBox {
    if (_box == null || !_box!.isOpen) {
      throw Exception('DaySummary box not initialized. Call init() first.');
    }
    return _box!;
  }
  
  /// Get summary for a specific date
  DaySummaryEntity? getSummaryForDate(String date) {
    return _summaryBox.get(date);
  }
  
  /// Get summaries for date range
  Map<String, DaySummaryEntity> getSummariesInRange(String startDate, String endDate) {
    final summaries = <String, DaySummaryEntity>{};
    
    for (var entry in _summaryBox.toMap().entries) {
      final date = entry.key;
      if (date.compareTo(startDate) >= 0 && date.compareTo(endDate) <= 0) {
        summaries[date] = entry.value;
      }
    }
    
    return summaries;
  }
  
  /// Save or update summary
  Future<void> saveSummary(DaySummaryEntity summary) async {
    await _summaryBox.put(summary.date, summary);
  }
  
  /// Save multiple summaries
  Future<void> saveSummaries(List<DaySummaryEntity> summaries) async {
    final Map<String, DaySummaryEntity> summaryMap = {
      for (var summary in summaries) summary.date: summary
    };
    await _summaryBox.putAll(summaryMap);
  }
  
  /// Delete summary for date
  Future<void> deleteSummary(String date) async {
    await _summaryBox.delete(date);
  }
  
  /// Get all summaries
  List<DaySummaryEntity> getAllSummaries() {
    return _summaryBox.values.toList();
  }
  
  /// Clear all summaries
  Future<void> clearAllSummaries() async {
    await _summaryBox.clear();
  }
  
  /// Get summaries for month
  List<DaySummaryEntity> getSummariesForMonth(int year, int month) {
    return _summaryBox.values.where((summary) {
      final dateParts = summary.date.split('-');
      return dateParts[0] == year.toString() && 
             dateParts[1] == month.toString().padLeft(2, '0');
    }).toList();
  }
}
