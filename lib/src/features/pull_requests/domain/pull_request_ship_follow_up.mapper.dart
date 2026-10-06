// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'pull_request_ship_follow_up.dart';

class PullRequestShipFollowUpMapper
    extends EnumMapper<PullRequestShipFollowUp> {
  PullRequestShipFollowUpMapper._();

  static PullRequestShipFollowUpMapper? _instance;
  static PullRequestShipFollowUpMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = PullRequestShipFollowUpMapper._(),
      );
    }
    return _instance!;
  }

  static PullRequestShipFollowUp fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  PullRequestShipFollowUp decode(dynamic value) {
    switch (value) {
      case r'none':
        return PullRequestShipFollowUp.none;
      case r'watchAndFix':
        return PullRequestShipFollowUp.watchAndFix;
      case r'watchFixAndMerge':
        return PullRequestShipFollowUp.watchFixAndMerge;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(PullRequestShipFollowUp self) {
    switch (self) {
      case PullRequestShipFollowUp.none:
        return r'none';
      case PullRequestShipFollowUp.watchAndFix:
        return r'watchAndFix';
      case PullRequestShipFollowUp.watchFixAndMerge:
        return r'watchFixAndMerge';
    }
  }
}

extension PullRequestShipFollowUpMapperExtension on PullRequestShipFollowUp {
  String toValue() {
    PullRequestShipFollowUpMapper.ensureInitialized();
    return MapperContainer.globals.toValue<PullRequestShipFollowUp>(this)
        as String;
  }
}
