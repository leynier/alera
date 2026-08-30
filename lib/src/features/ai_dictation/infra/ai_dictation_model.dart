class const AiDictationModel({
  required final String id,
  required final String label,
  required final String description,
  required final String fileName,
  required final String sha256,
  required final String uri,
  required final int sizeBytes,
  final AiDictationCoreMlEncoder? coreMlEncoder,
  final int storageVersion = 1,
});

class const AiDictationCoreMlEncoder({
  required final String directoryName,
  required final String archiveUri,
  required final String archiveSha256,
  required final int archiveSizeBytes,
});

class const AiDictationDownloadCancelled() implements Exception;
