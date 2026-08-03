part of 'mobile_codex_chat_screen.dart';

class _MobileCodexMarkdown extends StatelessWidget {
  const _MobileCodexMarkdown({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => GptMarkdown(
    text,
    style: Theme.of(context).textTheme.bodyMedium,
    onLinkTap: (url, _) => unawaited(_openMarkdownLink(url)),
  );
}

Future<void> _openMarkdownLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null && await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
