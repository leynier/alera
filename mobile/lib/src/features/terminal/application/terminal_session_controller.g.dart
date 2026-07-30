// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'terminal_session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TerminalSessionController)
final terminalSessionControllerProvider = TerminalSessionControllerFamily._();

final class TerminalSessionControllerProvider
    extends
        $AsyncNotifierProvider<TerminalSessionController, TerminalTabSession> {
  TerminalSessionControllerProvider._({
    required TerminalSessionControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'terminalSessionControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$terminalSessionControllerHash();

  @override
  String toString() {
    return r'terminalSessionControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  TerminalSessionController create() => TerminalSessionController();

  @override
  bool operator ==(Object other) {
    return other is TerminalSessionControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$terminalSessionControllerHash() =>
    r'29ea54e2fefbca91a8dcae1c220d6cf4f130f2ec';

final class TerminalSessionControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          TerminalSessionController,
          AsyncValue<TerminalTabSession>,
          TerminalTabSession,
          FutureOr<TerminalTabSession>,
          (String, String)
        > {
  TerminalSessionControllerFamily._()
    : super(
        retry: null,
        name: r'terminalSessionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TerminalSessionControllerProvider call(String hostId, String tabId) =>
      TerminalSessionControllerProvider._(
        argument: (hostId, tabId),
        from: this,
      );

  @override
  String toString() => r'terminalSessionControllerProvider';
}

abstract class _$TerminalSessionController
    extends $AsyncNotifier<TerminalTabSession> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get tabId => _$args.$2;

  FutureOr<TerminalTabSession> build(String hostId, String tabId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<TerminalTabSession>, TerminalTabSession>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<TerminalTabSession>, TerminalTabSession>,
              AsyncValue<TerminalTabSession>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
