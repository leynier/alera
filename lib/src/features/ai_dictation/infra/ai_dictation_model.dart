class AiDictationModel {
  const AiDictationModel({
    required this.id,
    required this.label,
    required this.description,
    required this.fileName,
    required this.sha256,
    required this.uri,
    required this.sizeBytes,
    this.coreMlEncoder,
    this.storageVersion = 1,
  });

  final String id;
  final String label;
  final String description;
  final String fileName;
  final String sha256;
  final String uri;
  final int sizeBytes;
  final AiDictationCoreMlEncoder? coreMlEncoder;
  final int storageVersion;
}

class AiDictationCoreMlEncoder {
  const AiDictationCoreMlEncoder({
    required this.directoryName,
    required this.archiveUri,
    required this.archiveSha256,
    required this.archiveSizeBytes,
  });

  final String directoryName;
  final String archiveUri;
  final String archiveSha256;
  final int archiveSizeBytes;
}

class AiDictationDownloadCancelled implements Exception {
  const AiDictationDownloadCancelled();
}
