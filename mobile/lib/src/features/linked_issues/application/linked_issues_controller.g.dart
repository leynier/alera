// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'linked_issues_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every linked issue on one host, refreshed on `linkedIssuesChanged`.

@ProviderFor(LinkedIssuesController)
final linkedIssuesControllerProvider = LinkedIssuesControllerFamily._();

/// Every linked issue on one host, refreshed on `linkedIssuesChanged`.
final class LinkedIssuesControllerProvider
    extends
        $AsyncNotifierProvider<
          LinkedIssuesController,
          MobileLinkedIssueSnapshot
        > {
  /// Every linked issue on one host, refreshed on `linkedIssuesChanged`.
  LinkedIssuesControllerProvider._({
    required LinkedIssuesControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'linkedIssuesControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$linkedIssuesControllerHash();

  @override
  String toString() {
    return r'linkedIssuesControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  LinkedIssuesController create() => LinkedIssuesController();

  @override
  bool operator ==(Object other) {
    return other is LinkedIssuesControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$linkedIssuesControllerHash() =>
    r'bb6407f4814954a037efb56a604fb7d8075d3a45';

/// Every linked issue on one host, refreshed on `linkedIssuesChanged`.

final class LinkedIssuesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          LinkedIssuesController,
          AsyncValue<MobileLinkedIssueSnapshot>,
          MobileLinkedIssueSnapshot,
          FutureOr<MobileLinkedIssueSnapshot>,
          String
        > {
  LinkedIssuesControllerFamily._()
    : super(
        retry: null,
        name: r'linkedIssuesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every linked issue on one host, refreshed on `linkedIssuesChanged`.

  LinkedIssuesControllerProvider call(String hostId) =>
      LinkedIssuesControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'linkedIssuesControllerProvider';
}

/// Every linked issue on one host, refreshed on `linkedIssuesChanged`.

abstract class _$LinkedIssuesController
    extends $AsyncNotifier<MobileLinkedIssueSnapshot> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<MobileLinkedIssueSnapshot> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<MobileLinkedIssueSnapshot>,
              MobileLinkedIssueSnapshot
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<MobileLinkedIssueSnapshot>,
                MobileLinkedIssueSnapshot
              >,
              AsyncValue<MobileLinkedIssueSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
