import 'package:alera_mobile/src/core/json_payload_fields.dart';

const int maxPromptImageBytes = 18 * 1024 * 1024;
const int maxPromptImageChunkBytes = 256 * 1024;

class const PromptImageUploadResult({required final String hostPath}) {
  factory fromJson(Map<String, Object?> json) {
    return PromptImageUploadResult(hostPath: json.requiredString('path'));
  }
}
