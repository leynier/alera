// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'issue_state.dart';

class IssueStateMapper extends EnumMapper<IssueState> {
  IssueStateMapper._();

  static IssueStateMapper? _instance;
  static IssueStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IssueStateMapper._());
    }
    return _instance!;
  }

  static IssueState fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  IssueState decode(dynamic value) {
    switch (value) {
      case r'open':
        return IssueState.open;
      case r'closed':
        return IssueState.closed;
      case r'unknown':
        return IssueState.unknown;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(IssueState self) {
    switch (self) {
      case IssueState.open:
        return r'open';
      case IssueState.closed:
        return r'closed';
      case IssueState.unknown:
        return r'unknown';
    }
  }
}

extension IssueStateMapperExtension on IssueState {
  String toValue() {
    IssueStateMapper.ensureInitialized();
    return MapperContainer.globals.toValue<IssueState>(this) as String;
  }
}
