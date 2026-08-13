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

  String get description => switch (stage) {
    ReadingDiffGenerationStage.preparing =>
      'Loading the immutable diff and splitting it at safe boundaries.',
    ReadingDiffGenerationStage.cached =>
      'Using a previously generated and validated result.',
    ReadingDiffGenerationStage.generating =>
      'The agent is proposing safe elisions; Rust validates the plan.',
    ReadingDiffGenerationStage.repairing =>
      'Rust rejected the plan; the agent is replacing it once.',
    ReadingDiffGenerationStage.combining =>
      'Rust is merging the validated chunks into the final reading diff.',
  };
}
