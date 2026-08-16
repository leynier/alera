// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prompt_attachment_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Platform pickers behind providers so a widget test can swap them for fakes
/// instead of driving the real gallery and file plugins.

@ProviderFor(promptImagePicker)
final promptImagePickerProvider = PromptImagePickerProvider._();

/// Platform pickers behind providers so a widget test can swap them for fakes
/// instead of driving the real gallery and file plugins.

final class PromptImagePickerProvider
    extends
        $FunctionalProvider<
          PromptImagePicker,
          PromptImagePicker,
          PromptImagePicker
        >
    with $Provider<PromptImagePicker> {
  /// Platform pickers behind providers so a widget test can swap them for fakes
  /// instead of driving the real gallery and file plugins.
  PromptImagePickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'promptImagePickerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$promptImagePickerHash();

  @$internal
  @override
  $ProviderElement<PromptImagePicker> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PromptImagePicker create(Ref ref) {
    return promptImagePicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PromptImagePicker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PromptImagePicker>(value),
    );
  }
}

String _$promptImagePickerHash() => r'80909c1fdc38f8cbd5ffa95d2429e3691f855e39';

@ProviderFor(promptFilePicker)
final promptFilePickerProvider = PromptFilePickerProvider._();

final class PromptFilePickerProvider
    extends
        $FunctionalProvider<
          PromptFilePicker,
          PromptFilePicker,
          PromptFilePicker
        >
    with $Provider<PromptFilePicker> {
  PromptFilePickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'promptFilePickerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$promptFilePickerHash();

  @$internal
  @override
  $ProviderElement<PromptFilePicker> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PromptFilePicker create(Ref ref) {
    return promptFilePicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PromptFilePicker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PromptFilePicker>(value),
    );
  }
}

String _$promptFilePickerHash() => r'2a865b5ef7cf920b69001fec6b3c59d9de8f8a27';
