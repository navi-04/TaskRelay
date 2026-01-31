// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_task_type.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CustomTaskTypeAdapter extends TypeAdapter<CustomTaskType> {
  @override
  final int typeId = 5;

  @override
  CustomTaskType read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CustomTaskType(
      id: fields[0] as String,
      label: fields[1] as String,
      emoji: fields[2] as String,
      isDefault: fields[3] as bool,
      sortOrder: fields[4] as int,
    );
  }

  @override
  void write(BinaryWriter writer, CustomTaskType obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.label)
      ..writeByte(2)
      ..write(obj.emoji)
      ..writeByte(3)
      ..write(obj.isDefault)
      ..writeByte(4)
      ..write(obj.sortOrder);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomTaskTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class CustomPriorityAdapter extends TypeAdapter<CustomPriority> {
  @override
  final int typeId = 6;

  @override
  CustomPriority read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CustomPriority(
      id: fields[0] as String,
      label: fields[1] as String,
      emoji: fields[2] as String,
      colorValue: fields[3] as int,
      isDefault: fields[4] as bool,
      sortOrder: fields[5] as int,
    );
  }

  @override
  void write(BinaryWriter writer, CustomPriority obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.label)
      ..writeByte(2)
      ..write(obj.emoji)
      ..writeByte(3)
      ..write(obj.colorValue)
      ..writeByte(4)
      ..write(obj.isDefault)
      ..writeByte(5)
      ..write(obj.sortOrder);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomPriorityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
