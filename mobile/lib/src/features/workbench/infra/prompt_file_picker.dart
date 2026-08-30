import 'dart:async';

import 'package:file_selector/file_selector.dart';

class const PromptFile({
  required final String name,
  required final int sizeBytes,
  required final Stream<List<int>> Function() openRead,
});

/// Seam over the platform file picker, mirroring [PromptImagePicker] so widget
/// tests never reach the real plugin.
abstract interface class PromptFilePicker {
  Future<PromptFile?> pickFile();
}

class const FileSelectorPromptFilePicker() implements PromptFilePicker {
  @override
  Future<PromptFile?> pickFile() async {
    final file = await openFile();
    if (file == null) {
      return null;
    }
    return PromptFile(
      name: file.name,
      sizeBytes: await file.length(),
      openRead: file.openRead,
    );
  }
}
