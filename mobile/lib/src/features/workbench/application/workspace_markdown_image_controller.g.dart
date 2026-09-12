// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_markdown_image_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Bytes of a workspace image that a Markdown preview references, read through
/// the paired runtime. Null when the file is not an image, is larger than
/// [maxMobileMarkdownImageBytes], or cannot be read.

@ProviderFor(workspaceMarkdownImage)
final workspaceMarkdownImageProvider = WorkspaceMarkdownImageFamily._();

/// Bytes of a workspace image that a Markdown preview references, read through
/// the paired runtime. Null when the file is not an image, is larger than
/// [maxMobileMarkdownImageBytes], or cannot be read.

final class WorkspaceMarkdownImageProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List?>,
          Uint8List?,
          FutureOr<Uint8List?>
        >
    with $FutureModifier<Uint8List?>, $FutureProvider<Uint8List?> {
  /// Bytes of a workspace image that a Markdown preview references, read through
  /// the paired runtime. Null when the file is not an image, is larger than
  /// [maxMobileMarkdownImageBytes], or cannot be read.
  WorkspaceMarkdownImageProvider._({
    required WorkspaceMarkdownImageFamily super.from,
    required (String, String, String) super.argument,
  }) : super(
         retry: null,
         name: r'workspaceMarkdownImageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceMarkdownImageHash();

  @override
  String toString() {
    return r'workspaceMarkdownImageProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List?> create(Ref ref) {
    final argument = this.argument as (String, String, String);
    return workspaceMarkdownImage(ref, argument.$1, argument.$2, argument.$3);
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceMarkdownImageProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceMarkdownImageHash() =>
    r'38687d6fd1fd8f4301e1049aa3dec7d15894129b';

/// Bytes of a workspace image that a Markdown preview references, read through
/// the paired runtime. Null when the file is not an image, is larger than
/// [maxMobileMarkdownImageBytes], or cannot be read.

final class WorkspaceMarkdownImageFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Uint8List?>,
          (String, String, String)
        > {
  WorkspaceMarkdownImageFamily._()
    : super(
        retry: null,
        name: r'workspaceMarkdownImageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Bytes of a workspace image that a Markdown preview references, read through
  /// the paired runtime. Null when the file is not an image, is larger than
  /// [maxMobileMarkdownImageBytes], or cannot be read.

  WorkspaceMarkdownImageProvider call(
    String hostId,
    String workspaceId,
    String relativePath,
  ) => WorkspaceMarkdownImageProvider._(
    argument: (hostId, workspaceId, relativePath),
    from: this,
  );

  @override
  String toString() => r'workspaceMarkdownImageProvider';
}
