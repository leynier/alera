// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automation_workbench_context.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(automationWorkbenchContext)
final automationWorkbenchContextProvider =
    AutomationWorkbenchContextProvider._();

final class AutomationWorkbenchContextProvider
    extends
        $FunctionalProvider<
          AutomationWorkbenchContext,
          AutomationWorkbenchContext,
          AutomationWorkbenchContext
        >
    with $Provider<AutomationWorkbenchContext> {
  AutomationWorkbenchContextProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'automationWorkbenchContextProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$automationWorkbenchContextHash();

  @$internal
  @override
  $ProviderElement<AutomationWorkbenchContext> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AutomationWorkbenchContext create(Ref ref) {
    return automationWorkbenchContext(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AutomationWorkbenchContext value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AutomationWorkbenchContext>(value),
    );
  }
}

String _$automationWorkbenchContextHash() =>
    r'64b67f86f07c177493807014c513324e74cdb541';
