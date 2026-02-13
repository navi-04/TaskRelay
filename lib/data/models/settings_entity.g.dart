// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SettingsEntityAdapter extends TypeAdapter<SettingsEntity> {
  @override
  final int typeId = 1;

  @override
  SettingsEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SettingsEntity(
      dailyTimeLimitMinutes: fields[0] as int,
      notificationsEnabled: fields[1] as bool,
      notificationHour: fields[2] as int,
      notificationMinute: fields[3] as int,
      isDarkMode: fields[4] as bool,
      showCarryOverAlerts: fields[5] as bool,
      isFirstLaunch: fields[6] as bool,
      defaultTaskType: fields[7] as TaskType,
      defaultPriority: fields[8] as TaskPriority,
      username: fields[9] as String,
      profilePhoto: fields[10] as String?,
      estimationModeIndex: fields[11] as int,
      dailyWeightLimit: fields[12] as int,
      dailyCountLimit: fields[13] as int,
    );
  }

  @override
  void write(BinaryWriter writer, SettingsEntity obj) {
    writer
      ..writeByte(14)
      ..writeByte(9)
      ..write(obj.username)
      ..writeByte(10)
      ..write(obj.profilePhoto)
      ..writeByte(11)
      ..write(obj.estimationModeIndex)
      ..writeByte(12)
      ..write(obj.dailyWeightLimit)
      ..writeByte(13)
      ..write(obj.dailyCountLimit)
      ..writeByte(0)
      ..write(obj.dailyTimeLimitMinutes)
      ..writeByte(1)
      ..write(obj.notificationsEnabled)
      ..writeByte(2)
      ..write(obj.notificationHour)
      ..writeByte(3)
      ..write(obj.notificationMinute)
      ..writeByte(4)
      ..write(obj.isDarkMode)
      ..writeByte(5)
      ..write(obj.showCarryOverAlerts)
      ..writeByte(6)
      ..write(obj.isFirstLaunch)
      ..writeByte(7)
      ..write(obj.defaultTaskType)
      ..writeByte(8)
      ..write(obj.defaultPriority);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
