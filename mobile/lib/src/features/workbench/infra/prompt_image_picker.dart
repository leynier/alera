import 'dart:async';

import 'package:image_picker/image_picker.dart';

class PromptImageFile {
  const PromptImageFile({
    required this.name,
    required this.sizeBytes,
    required this.openRead,
  });

  final String name;
  final int sizeBytes;
  final Stream<List<int>> Function() openRead;
}

abstract interface class PromptImagePicker {
  Future<List<PromptImageFile>> pickImages();
}

class ImagePickerPromptImagePicker implements PromptImagePicker {
  ImagePickerPromptImagePicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

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
