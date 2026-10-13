import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter/painting.dart';

/// Status letter and tone shared by every list of changed files.
(String, Color) gitChangeStatusStyle(GitChangeStatus status) =>
    switch (status) {
      GitChangeStatus.added => ('A', AleraTokens.success),
      GitChangeStatus.untracked => ('U', AleraTokens.success),
      GitChangeStatus.deleted => ('D', AleraTokens.error),
      GitChangeStatus.renamed => ('R', AleraTokens.warning),
      GitChangeStatus.copied => ('C', AleraTokens.warning),
      GitChangeStatus.modified => ('M', AleraTokens.warning),
    };
