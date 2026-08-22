import 'package:alera_mobile/src/features/workbench/infra/prompt_file_picker.dart';
import 'package:alera_mobile/src/features/workbench/infra/prompt_image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'prompt_attachment_providers.g.dart';

/// Platform pickers behind providers so a widget test can swap them for fakes
/// instead of driving the real gallery and file plugins.
@riverpod
PromptImagePicker promptImagePicker(Ref ref) => ImagePickerPromptImagePicker();

@riverpod
PromptFilePicker promptFilePicker(Ref ref) =>
    const FileSelectorPromptFilePicker();
