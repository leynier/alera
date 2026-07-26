// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_lifecycle_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's foreground/background state.
///
/// `AppLifecycleListener` rather than a `WidgetsBindingObserver` so this stays a
/// generated provider instead of leaking lifecycle wiring into a widget.

@ProviderFor(AppLifecycleController)
final appLifecycleControllerProvider = AppLifecycleControllerProvider._();

/// The app's foreground/background state.
///
/// `AppLifecycleListener` rather than a `WidgetsBindingObserver` so this stays a
/// generated provider instead of leaking lifecycle wiring into a widget.
final class AppLifecycleControllerProvider
    extends $NotifierProvider<AppLifecycleController, AppLifecycleState> {
  /// The app's foreground/background state.
  ///
  /// `AppLifecycleListener` rather than a `WidgetsBindingObserver` so this stays a
  /// generated provider instead of leaking lifecycle wiring into a widget.
  AppLifecycleControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appLifecycleControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appLifecycleControllerHash();

  @$internal
  @override
  AppLifecycleController create() => AppLifecycleController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppLifecycleState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppLifecycleState>(value),
    );
  }
}

String _$appLifecycleControllerHash() =>
    r'e674f5e07850909fe1ab8c3967a8f68c2621446d';

/// The app's foreground/background state.
///
/// `AppLifecycleListener` rather than a `WidgetsBindingObserver` so this stays a
/// generated provider instead of leaking lifecycle wiring into a widget.

abstract class _$AppLifecycleController extends $Notifier<AppLifecycleState> {
  AppLifecycleState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AppLifecycleState, AppLifecycleState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppLifecycleState, AppLifecycleState>,
              AppLifecycleState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
