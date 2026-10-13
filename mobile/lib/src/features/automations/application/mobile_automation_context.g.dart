// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_automation_context.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mobileAutomationContext)
final mobileAutomationContextProvider = MobileAutomationContextFamily._();

final class MobileAutomationContextProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileAutomationContext>,
          MobileAutomationContext,
          FutureOr<MobileAutomationContext>
        >
    with
        $FutureModifier<MobileAutomationContext>,
        $FutureProvider<MobileAutomationContext> {
  MobileAutomationContextProvider._({
    required MobileAutomationContextFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationContextProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationContextHash();

  @override
  String toString() {
    return r'mobileAutomationContextProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileAutomationContext> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileAutomationContext> create(Ref ref) {
    final argument = this.argument as String;
    return mobileAutomationContext(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationContextProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationContextHash() =>
    r'2937b6dc05321b03eb7a6c201cab023244fa6c7e';

final class MobileAutomationContextFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<MobileAutomationContext>, String> {
  MobileAutomationContextFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationContextProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileAutomationContextProvider call(String hostId) =>
      MobileAutomationContextProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAutomationContextProvider';
}
