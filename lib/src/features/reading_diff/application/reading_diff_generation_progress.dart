enum ReadingDiffGenerationStage {
  preparing,
  cached,
  generating,
  repairing,
  combining,
}

class ReadingDiffGenerationProgress {
  const ReadingDiffGenerationProgress({
    required this.stage,
    required this.completedChunks,
    required this.totalChunks,
    this.currentChunk,
  });

  final ReadingDiffGenerationStage stage;
  final int completedChunks;
  final int totalChunks;
  final int? currentChunk;

  double? get fraction {
    if (totalChunks <= 0) {
      return null;
    }
    return (completedChunks / totalChunks).clamp(0, 1);
  }

  String get label => switch (stage) {
    ReadingDiffGenerationStage.preparing => 'Preparing reading diff',
    ReadingDiffGenerationStage.cached => 'Loading cached reading diff',
    ReadingDiffGenerationStage.generating =>
      'Generating chunk ${currentChunk ?? completedChunks + 1} of $totalChunks',
    ReadingDiffGenerationStage.repairing =>
      'Repairing chunk ${currentChunk ?? completedChunks + 1} of $totalChunks',
    ReadingDiffGenerationStage.combining =>
      'Combining $totalChunks ${totalChunks == 1 ? 'chunk' : 'chunks'}',
  };
}
