import 'dart:async';

import 'package:image_picker/image_picker.dart';

class const PromptImageFile({
  required final String name,
  required final int sizeBytes,
  required final Stream<List<int>> Function() openRead,
});

abstract interface class PromptImagePicker {
  Future<List<PromptImageFile>> pickImages();
}

class ImagePickerPromptImagePicker({ImagePicker? picker})
    implements PromptImagePicker {
  this : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<List<PromptImageFile>> pickImages() async {
    final selected = await _picker.pickMultiImage();
    return <PromptImageFile>[
      for (final file in selected)
        PromptImageFile(
          name: file.name,
          sizeBytes: await file.length(),
          openRead: () => file.openRead().map<List<int>>((bytes) => bytes),
        ),
    ];
  }
}

String promptImageFormatForFileName(String name) {
  final separator = name.lastIndexOf('.');
  final extension = separator < 0
      ? ''
      : name.substring(separator + 1).toLowerCase();
  return switch (extension) {
    'png' => 'png',
    'jpg' || 'jpeg' => 'jpeg',
    'gif' => 'gif',
    'webp' => 'webp',
    _ => throw UnsupportedError(
      'Choose PNG, JPEG, GIF, or WebP images to continue.',
    ),
  };
}
