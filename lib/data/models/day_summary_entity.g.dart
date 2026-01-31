// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'day_summary_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DaySummaryEntityAdapter extends TypeAdapter<DaySummaryEntity> {
  @override
  final int typeId = 2;

  @override
  DaySummaryEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DaySummaryEntity(
      date: fields[0] as String,
      totalTasks: fields[1] as int,
      completedTasks: fields[2] as int,
      totalWeight: fields[3] as int,
      completedWeight: fields[4] as int,
      carriedOverTasks: fields[5] as int,
      isFullyCompleted: fields[6] as bool,
      hasTasks: fields[7] as bool,
      lastUpdated: fields[8] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, DaySummaryEntity obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.totalTasks)
      ..writeByte(2)
      ..write(obj.completedTasks)
      ..writeByte(3)
      ..write(obj.totalWeight)
      ..writeByte(4)
      ..write(obj.completedWeight)
      ..writeByte(5)
      ..write(obj.carriedOverTasks)
      ..writeByte(6)
      ..write(obj.isFullyCompleted)
      ..writeByte(7)
      ..write(obj.hasTasks)
      ..writeByte(8)
      ..write(obj.lastUpdated);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DaySummaryEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
