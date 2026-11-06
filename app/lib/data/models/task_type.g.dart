// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_type.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TaskTypeAdapter extends TypeAdapter<TaskType> {
  @override
  final int typeId = 3;

  @override
  TaskType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TaskType.task;
      case 1:
        return TaskType.bug;
      case 2:
        return TaskType.feature;
      case 3:
        return TaskType.story;
      case 4:
        return TaskType.epic;
      case 5:
        return TaskType.improvement;
      case 6:
        return TaskType.subtask;
      case 7:
        return TaskType.research;
      default:
        return TaskType.task;
    }
  }

  @override
  void write(BinaryWriter writer, TaskType obj) {
    switch (obj) {
      case TaskType.task:
        writer.writeByte(0);
        break;
      case TaskType.bug:
        writer.writeByte(1);
        break;
      case TaskType.feature:
        writer.writeByte(2);
        break;
      case TaskType.story:
        writer.writeByte(3);
        break;
      case TaskType.epic:
        writer.writeByte(4);
        break;
      case TaskType.improvement:
        writer.writeByte(5);
        break;
      case TaskType.subtask:
        writer.writeByte(6);
        break;
      case TaskType.research:
        writer.writeByte(7);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
