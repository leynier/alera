// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'run_detail_tab.dart';

class RunDetailTabMapper extends EnumMapper<RunDetailTab> {
  RunDetailTabMapper._();

  static RunDetailTabMapper? _instance;
  static RunDetailTabMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunDetailTabMapper._());
    }
    return _instance!;
  }

  static RunDetailTab fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  RunDetailTab decode(dynamic value) {
    switch (value) {
      case r'overview':
        return RunDetailTab.overview;
      case r'tasks':
        return RunDetailTab.tasks;
      case r'timeline':
        return RunDetailTab.timeline;
      case r'resources':
        return RunDetailTab.resources;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(RunDetailTab self) {
    switch (self) {
      case RunDetailTab.overview:
        return r'overview';
      case RunDetailTab.tasks:
        return r'tasks';
      case RunDetailTab.timeline:
        return r'timeline';
      case RunDetailTab.resources:
        return r'resources';
    }
  }
}

extension RunDetailTabMapperExtension on RunDetailTab {
  String toValue() {
    RunDetailTabMapper.ensureInitialized();
    return MapperContainer.globals.toValue<RunDetailTab>(this) as String;
  }
}
