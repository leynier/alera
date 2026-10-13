// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'activity_section.dart';

class ActivitySectionMapper extends EnumMapper<ActivitySection> {
  ActivitySectionMapper._();

  static ActivitySectionMapper? _instance;
  static ActivitySectionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ActivitySectionMapper._());
    }
    return _instance!;
  }

  static ActivitySection fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ActivitySection decode(dynamic value) {
    switch (value) {
      case r'runs':
        return ActivitySection.runs;
      case r'questions':
        return ActivitySection.questions;
      case r'automations':
        return ActivitySection.automations;
      case r'chatTasks':
        return ActivitySection.chatTasks;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ActivitySection self) {
    switch (self) {
      case ActivitySection.runs:
        return r'runs';
      case ActivitySection.questions:
        return r'questions';
      case ActivitySection.automations:
        return r'automations';
      case ActivitySection.chatTasks:
        return r'chatTasks';
    }
  }
}

extension ActivitySectionMapperExtension on ActivitySection {
  String toValue() {
    ActivitySectionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ActivitySection>(this) as String;
  }
}
