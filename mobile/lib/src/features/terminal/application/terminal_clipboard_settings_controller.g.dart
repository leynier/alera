// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'terminal_clipboard_settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether terminal programs may replace the phone's clipboard through OSC 52.
///
/// Off by default, mirroring the desktop's `allowOsc52Clipboard`: any byte
/// stream the terminal renders could otherwise swap the clipboard under the
/// user, and a SnackBar is easy to miss.

@ProviderFor(TerminalClipboardSettingsController)
final terminalClipboardSettingsControllerProvider =
    TerminalClipboardSettingsControllerProvider._();

/// Whether terminal programs may replace the phone's clipboard through OSC 52.
///
/// Off by default, mirroring the desktop's `allowOsc52Clipboard`: any byte
/// stream the terminal renders could otherwise swap the clipboard under the
/// user, and a SnackBar is easy to miss.
final class TerminalClipboardSettingsControllerProvider
    extends $AsyncNotifierProvider<TerminalClipboardSettingsController, bool> {
  /// Whether terminal programs may replace the phone's clipboard through OSC 52.
  ///
  /// Off by default, mirroring the desktop's `allowOsc52Clipboard`: any byte
  /// stream the terminal renders could otherwise swap the clipboard under the
  /// user, and a SnackBar is easy to miss.
  TerminalClipboardSettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'terminalClipboardSettingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$terminalClipboardSettingsControllerHash();

  @$internal
  @override
  TerminalClipboardSettingsController create() =>
      TerminalClipboardSettingsController();
}

String _$terminalClipboardSettingsControllerHash() =>
    r'dca7effbf8cc08f1cd668b48929ad86b8b0b7428';

/// Whether terminal programs may replace the phone's clipboard through OSC 52.
///
/// Off by default, mirroring the desktop's `allowOsc52Clipboard`: any byte
/// stream the terminal renders could otherwise swap the clipboard under the
/// user, and a SnackBar is easy to miss.

abstract class _$TerminalClipboardSettingsController
    extends $AsyncNotifier<bool> {
  FutureOr<bool> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<bool>, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<bool>, bool>,
              AsyncValue<bool>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
