import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_check_icon.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Success', group: 'PR check icon')
Widget pullRequestCheckIconSuccessPreview() =>
    const PullRequestCheckIcon(status: .completed, conclusion: .success);

@AleraPreview(name: 'Failure', group: 'PR check icon')
Widget pullRequestCheckIconFailurePreview() =>
    const PullRequestCheckIcon(status: .completed, conclusion: .failure);

@AleraPreview(name: 'Running', group: 'PR check icon')
Widget pullRequestCheckIconRunningPreview() =>
    const PullRequestCheckIcon(status: .inProgress, conclusion: .pending);

@AleraPreview(name: 'Skipped', group: 'PR check icon')
Widget pullRequestCheckIconSkippedPreview() =>
    const PullRequestCheckIcon(status: .completed, conclusion: .skipped);
