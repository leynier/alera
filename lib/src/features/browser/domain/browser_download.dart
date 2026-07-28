enum BrowserDownloadStatus {
  pending,
  downloading,
  completed,
  cancelled,
  failed,
}

final class BrowserDownloadRequest {
  const BrowserDownloadRequest({
    required this.pageId,
    required this.url,
    required this.requestedAt,
    this.suggestedFileName,
    this.mimeType,
    this.totalBytes,
  });

  final String pageId;
  final Uri url;
  final DateTime requestedAt;
  final String? suggestedFileName;
  final String? mimeType;
  final int? totalBytes;
}

final class BrowserDownloadDecision {
  const BrowserDownloadDecision.deny() : destinationPath = null;

  const BrowserDownloadDecision.accept(this.destinationPath);

  final String? destinationPath;

  bool get accepted =>
      destinationPath != null && destinationPath!.trim().isNotEmpty;
}

final class BrowserDownload {
  const BrowserDownload({
    required this.id,
    required this.pageId,
    required this.fileName,
    required this.status,
    required this.receivedBytes,
    required this.startedAt,
    this.totalBytes,
    this.savePath,
    this.error,
  });

  factory BrowserDownload.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final pageId = json['pageId'];
    final fileName = json['fileName'];
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    if (id is! String ||
        pageId is! String ||
        fileName is! String ||
        startedAt == null) {
      throw const FormatException('Browser Download Payload Is Invalid.');
    }
    return BrowserDownload(
      id: id,
      pageId: pageId,
      fileName: fileName,
      status: BrowserDownloadStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => BrowserDownloadStatus.failed,
      ),
      receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt(),
      savePath: json['savePath'] as String?,
      error: json['error'] as String?,
      startedAt: startedAt.toUtc(),
    );
  }

  final String id;
  final String pageId;
  final String fileName;
  final BrowserDownloadStatus status;
  final int receivedBytes;
  final int? totalBytes;
  final String? savePath;
  final String? error;
  final DateTime startedAt;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  bool get isTerminal =>
      status == BrowserDownloadStatus.completed ||
      status == BrowserDownloadStatus.cancelled ||
      status == BrowserDownloadStatus.failed;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'pageId': pageId,
    'fileName': fileName,
    'status': status.name,
    'receivedBytes': receivedBytes,
    if (totalBytes != null) 'totalBytes': totalBytes,
    if (savePath != null) 'savePath': savePath,
    if (error != null) 'error': error,
    'startedAt': startedAt.toUtc().toIso8601String(),
  };
}
