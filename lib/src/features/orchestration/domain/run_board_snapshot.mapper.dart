// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'run_board_snapshot.dart';

class RunBoardBucketMapper extends EnumMapper<RunBoardBucket> {
  RunBoardBucketMapper._();

  static RunBoardBucketMapper? _instance;
  static RunBoardBucketMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunBoardBucketMapper._());
    }
    return _instance!;
  }

  static RunBoardBucket fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  RunBoardBucket decode(dynamic value) {
    switch (value) {
      case r'attention':
        return RunBoardBucket.attention;
      case r'active':
        return RunBoardBucket.active;
      case r'history':
        return RunBoardBucket.history;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(RunBoardBucket self) {
    switch (self) {
      case RunBoardBucket.attention:
        return r'attention';
      case RunBoardBucket.active:
        return r'active';
      case RunBoardBucket.history:
        return r'history';
    }
  }
}

extension RunBoardBucketMapperExtension on RunBoardBucket {
  String toValue() {
    RunBoardBucketMapper.ensureInitialized();
    return MapperContainer.globals.toValue<RunBoardBucket>(this) as String;
  }
}
