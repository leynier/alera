import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/pull_requests/application/review_reference_parser.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:flutter/material.dart';

/// Collects existing pull requests in bottom-to-top order. For an existing
/// stack, the entered pull requests are appended to its top.
class PullRequestStackLinkDialog extends StatefulWidget {
  const PullRequestStackLinkDialog({
    super.key,
    required this.currentReviewNumber,
    this.stack,
  });

  final int currentReviewNumber;
  final HostedReviewStack? stack;

  @override
  State<PullRequestStackLinkDialog> createState() =>
      _PullRequestStackLinkDialogState();
}

class _PullRequestStackLinkDialogState
    extends State<PullRequestStackLinkDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  bool get _appending => widget.stack != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _appending ? '' : '#${widget.currentReviewNumber}',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final tokens = _controller.text
        .split(RegExp(r'[\s,]+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      setState(() {
        _errorText = _appending
            ? 'Enter at least one pull request.'
            : 'Enter at least two pull requests.';
      });
      return;
    }
    final numbers = <int>[];
    final seen = <int>{};
    for (final token in tokens) {
      final number = parseReviewReference(token);
      if (number == null) {
        setState(
          () => _errorText = 'Could not parse `$token` as a pull request.',
        );
        return;
      }
      if (!seen.add(number)) {
        setState(() => _errorText = 'Pull request #$number is listed twice.');
        return;
      }
      numbers.add(number);
    }
    if (!_appending && numbers.length < 2) {
      setState(() {
        _errorText = 'A new stack requires at least two pull requests.';
      });
      return;
    }
    if (!_appending && !numbers.contains(widget.currentReviewNumber)) {
      setState(() {
        _errorText =
            'Include the current pull request #${widget.currentReviewNumber}.';
      });
      return;
    }
    Navigator.of(context).pop(numbers);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 520,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: _appending
                  ? 'Add Pull Requests To Stack'
                  : 'Create Pull Request Stack',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space12),
            Text(
              _appending
                  ? 'Enter the pull requests to append to Stack #${widget.stack!.number}, ordered from the next layer to the new top. GitHub may update each pull request base branch to match this order.'
                  : 'Enter pull request numbers or URLs in bottom-to-top order. Separate entries with spaces, commas, or new lines. GitHub may update each pull request base branch to match this order.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            AleraTextField(
              controller: _controller,
              labelText: _appending
                  ? 'Pull Requests To Add'
                  : 'Pull Requests, Bottom To Top',
              hintText: '#41\n#42\n#43',
              errorText: _errorText,
              autofocus: true,
              minLines: 5,
              maxLines: 8,
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
            ),
            const SizedBox(height: AleraTokens.space16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _submit,
                  child: Text(
                    _appending ? 'Add Pull Requests' : 'Create Stack',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
