// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'git_hosting_provider.dart';

class GitHostingProviderMapper extends EnumMapper<GitHostingProvider> {
  GitHostingProviderMapper._();

  static GitHostingProviderMapper? _instance;
  static GitHostingProviderMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GitHostingProviderMapper._());
    }
    return _instance!;
  }

  static GitHostingProvider fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  GitHostingProvider decode(dynamic value) {
    switch (value) {
      case r'github':
        return GitHostingProvider.github;
      case r'azureDevops':
        return GitHostingProvider.azureDevops;
      case r'gitlab':
        return GitHostingProvider.gitlab;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(GitHostingProvider self) {
    switch (self) {
      case GitHostingProvider.github:
        return r'github';
      case GitHostingProvider.azureDevops:
        return r'azureDevops';
      case GitHostingProvider.gitlab:
        return r'gitlab';
    }
  }
}

extension GitHostingProviderMapperExtension on GitHostingProvider {
  String toValue() {
    GitHostingProviderMapper.ensureInitialized();
    return MapperContainer.globals.toValue<GitHostingProvider>(this) as String;
  }
}

