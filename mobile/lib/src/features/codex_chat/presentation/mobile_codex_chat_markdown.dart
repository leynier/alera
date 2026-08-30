part of 'mobile_codex_chat_screen.dart';

class const _MobileCodexMarkdown({required final String text})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GptMarkdown(
    text,
    style: Theme.of(context).textTheme.bodyMedium,
    onLinkTap: (url, _) => unawaited(_openMarkdownLink(context, url)),
  );
}

Future<void> _openMarkdownLink(BuildContext context, String url) =>
    _openMobileCodexPath(context, url, parseLineReferences: true);
