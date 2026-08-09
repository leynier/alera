part of 'mobile_codex_chat_screen.dart';

class _MobileComposerAttachments extends StatelessWidget {
  const _MobileComposerAttachments({
    required this.attachments,
    required this.onRemove,
  });

  final List<Map<String, Object?>> attachments;
  final ValueChanged<Map<String, Object?>> onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AleraTokens.space8,
      AleraTokens.space8,
      AleraTokens.space8,
      0,
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final attachment in attachments) ...<Widget>[
              InputChip(
                avatar: Icon(
                  attachment['type'] == 'localImage'
                      ? Icons.image_outlined
                      : _mobileFileIcon(attachment['path']?.toString() ?? ''),
                  size: AleraTokens.space16,
                ),
                label: Text(
                  attachment['name']?.toString() ??
                      _mobileBaseName(attachment['path']?.toString() ?? ''),
                ),
                onPressed: () => unawaited(
                  _openMobileCodexPath(
                    context,
                    attachment['path']?.toString() ?? '',
                    cwd: attachment['origin'] == 'mention'
                        ? attachment['cwd']?.toString()
                        : null,
                  ),
                ),
                onDeleted: () => onRemove(attachment),
              ),
              const SizedBox(width: AleraTokens.space6),
            ],
          ],
        ),
      ),
    ),
  );
}
