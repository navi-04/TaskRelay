// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TaskEntityAdapter extends TypeAdapter<TaskEntity> {
  @override
  final int typeId = 0;

  @override
  TaskEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TaskEntity(
      id: fields[0] as String,
      title: fields[1] as String,
      description: fields[2] as String?,
      durationMinutes: fields[3] as int,
      isCompleted: fields[4] as bool,
      createdDate: fields[5] as String,
      originalDate: fields[6] as String,
      currentDate: fields[7] as String,
      isCarriedOver: fields[8] as bool,
      completedAt: fields[9] as DateTime?,
      taskType: fields[10] as TaskType,
      priority: fields[11] as TaskPriority,
      notes: fields[12] as String?,
      tags: (fields[13] as List).cast<String>(),
      isPermanent: fields[14] as bool,
      alarmTime: fields[15] as DateTime?,
      weight: fields[16] as int? ?? 1,
      reminderTypeIndex: fields[17] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, TaskEntity obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.durationMinutes)
      ..writeByte(4)
      ..write(obj.isCompleted)
      ..writeByte(5)
      ..write(obj.createdDate)
      ..writeByte(6)
      ..write(obj.originalDate)
      ..writeByte(7)
      ..write(obj.currentDate)
      ..writeByte(8)
      ..write(obj.isCarriedOver)
      ..writeByte(9)
      ..write(obj.completedAt)
      ..writeByte(10)
      ..write(obj.taskType)
      ..writeByte(11)
      ..write(obj.priority)
      ..writeByte(12)
      ..write(obj.notes)
      ..writeByte(13)
      ..write(obj.tags)
      ..writeByte(14)
      ..write(obj.isPermanent)
      ..writeByte(15)
      ..write(obj.alarmTime)
      ..writeByte(16)
      ..write(obj.weight)
      ..writeByte(17)
      ..write(obj.reminderTypeIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
