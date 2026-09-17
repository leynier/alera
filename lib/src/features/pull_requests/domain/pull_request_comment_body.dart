// Converts the GitHub HTML subset found in review comment bodies into
// Markdown that GptMarkdown renders. gpt_markdown only understands standard
// Markdown plus <u>, so raw tags like <picture>, <img>, <a>, <sub> or <br>
// would otherwise show up as literal text (bot footers are the usual case).
// Fenced code blocks and inline code spans pass through untouched so code
// samples that mention HTML stay exact. HTML width/height attributes are
// intentionally dropped: the comment image builder caps dimensions through
// AleraTokens. Keep in sync with the mobile copy in
// mobile/lib/src/features/workbench/domain/pull_request_comment_body.dart.

final _htmlComment = RegExp(r'<!--.*?-->', dotAll: true);
final _fenceLine = RegExp(r'^[ \t]{0,3}(`{3,}|~{3,})');
final _inlineCode = RegExp(r'(`+)(.+?)\1', dotAll: true);
final _codePlaceholder = RegExp('\uE000(\\d+)\uE001');
final _picture = RegExp(
  r'<picture\b[^>]*>(.*?)</picture\s*>',
  dotAll: true,
  caseSensitive: false,
);
final _img = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final _sourceTag = RegExp(r'<source\b[^>]*>', caseSensitive: false);
final _imgTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final _anchor = RegExp(
  r'<a\b([^>]*)>(.*?)</a\s*>',
  dotAll: true,
  caseSensitive: false,
);
final _pre = RegExp(
  r'<pre\b[^>]*>(.*?)</pre\s*>',
  dotAll: true,
  caseSensitive: false,
);
final _attribute = RegExp(
  '\\b([a-zA-Z][a-zA-Z0-9-]*)\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
);
final _br = RegExp(r'<br\s*/?>', caseSensitive: false);
final _imageMarkdown = RegExp(r'^!\[[^\[\]]*\]\([^()\s]+\)$');
final _blankLines = RegExp(r'\n{3,}');
final _uOpen = RegExp(r'<u\b[^>]*>', caseSensitive: false);

// Stripped after conversion. <u> stays because GptMarkdown renders it, and
// CommonMark autolinks stay because stripping them would eat the URL.
final _remainingTag = RegExp(
  r'<(?!(?:u(?:\s|/?>|$)|/u(?:\s|>|$)|https?://))[^>]*>',
  caseSensitive: false,
);

/// Sanitizes [body] for display in the Comments section.
String sanitizePullRequestCommentBody(String body) {
  final lines = body.split('\n');
  final buffer = <String>[];
  var segment = <String>[];
  var inFence = false;

  void flush() {
    if (segment.isEmpty) {
      return;
    }
    buffer.add(_sanitizeSegment(segment.join('\n')));
    segment = <String>[];
  }

  for (final line in lines) {
    final stripped = line.endsWith('\r')
        ? line.substring(0, line.length - 1)
        : line;
    if (_fenceLine.hasMatch(stripped)) {
      if (!inFence) {
        flush();
        inFence = true;
      } else {
        inFence = false;
      }
      buffer.add(line);
    } else if (inFence) {
      buffer.add(line);
    } else {
      segment.add(line);
    }
  }
  flush();
  return buffer.join('\n');
}

String _sanitizeSegment(String segment) {
  if (!segment.contains('<') && !segment.contains('&')) {
    return segment;
  }
  final codeSpans = <String>[];
  var text = segment.replaceAllMapped(_inlineCode, (match) {
    codeSpans.add(match.group(0)!);
    return '\uE000${codeSpans.length - 1}\uE001';
  });
  text = _sanitizeHtml(text);
  return text.replaceAllMapped(
    _codePlaceholder,
    (match) => codeSpans[int.parse(match.group(1)!)],
  );
}

String _sanitizeHtml(String text) {
  var result = text.replaceAll(_htmlComment, '');
  result = result.replaceAllMapped(
    _picture,
    (match) => _pictureReplacement(match.group(1)!),
  );
  result = result.replaceAllMapped(
    _img,
    (match) => _imageMarkdownForTag(match.group(0)!),
  );
  var previous = '';
  while (previous != result) {
    previous = result;
    result = result.replaceAllMapped(
      _anchor,
      (match) => _anchorReplacement(match),
    );
  }
  result = result.replaceAllMapped(
    _pre,
    (match) => _preReplacement(match.group(1)!),
  );
  result = _replaceFormatting(result);
  result = result.replaceAll(_br, '  \n');
  result = _replaceBlocks(result);
  result = result.replaceAllMapped(_uOpen, (_) => '<u>');
  result = result.replaceAll(_remainingTag, '');
  result = _decodeEntities(result);
  result = result.replaceAll(_blankLines, '\n\n');
  return result;
}

// Anchor labels, table cells and other inline contexts: no links, blocks or
// code fences, only images, formatting and plain text.
String _sanitizeInline(String text) {
  var result = text.replaceAll(_htmlComment, '');
  result = result.replaceAllMapped(
    _picture,
    (match) => _pictureReplacement(match.group(1)!),
  );
  result = result.replaceAllMapped(
    _img,
    (match) => _imageMarkdownForTag(match.group(0)!),
  );
  result = _replaceFormatting(result);
  result = result.replaceAll(_br, ' ');
  result = result.replaceAllMapped(_uOpen, (_) => '<u>');
  result = result.replaceAll(_remainingTag, '');
  result = _decodeEntities(result);
  return result;
}

String _anchorReplacement(Match match) {
  final inner = _sanitizeInline(match.group(2)!);
  final href = _attributeValue(match.group(1)!, 'href');
  if (href == null || href.isEmpty || !_isWebUrl(href)) {
    return inner;
  }
  final label = inner.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (label.isEmpty) {
    return '';
  }
  if (_imageMarkdown.hasMatch(label)) {
    // A linked image cannot render inside a link label (a WidgetSpan inside
    // a WidgetSpan does not paint on iOS), so keep the image and drop the
    // outer link.
    return label;
  }
  return '[$label]($href)';
}

String _pictureReplacement(String inner) {
  var darkUrl = '';
  var firstUrl = '';
  for (final match in _sourceTag.allMatches(inner)) {
    final url = _firstSrcsetUrl(_attributeValue(match.group(0)!, 'srcset'));
    if (url.isEmpty) {
      continue;
    }
    if (firstUrl.isEmpty) {
      firstUrl = url;
    }
    final media = _attributeValue(match.group(0)!, 'media') ?? '';
    if (darkUrl.isEmpty && media.toLowerCase().contains('dark')) {
      // The app is dark-only, so the dark source is the right pick.
      darkUrl = url;
    }
  }
  final imgMatch = _imgTag.firstMatch(inner);
  final imgSrc = imgMatch == null
      ? ''
      : _attributeValue(imgMatch.group(0)!, 'src') ?? '';
  final imgAlt = imgMatch == null
      ? ''
      : _attributeValue(imgMatch.group(0)!, 'alt') ?? '';
  final chosen = darkUrl.isNotEmpty
      ? darkUrl
      : imgSrc.isNotEmpty
      ? imgSrc
      : firstUrl;
  if (chosen.isEmpty) {
    return _sanitizeInline(inner);
  }
  return _imageMarkdownFor(src: chosen, alt: imgAlt);
}

String _imageMarkdownForTag(String tag) {
  return _imageMarkdownFor(
    src: _attributeValue(tag, 'src') ?? '',
    alt: _attributeValue(tag, 'alt') ?? '',
  );
}

String _imageMarkdownFor({required String src, required String alt}) {
  final url = _decodeEntities(src).trim().replaceAll(' ', '%20');
  final cleanAlt = _decodeEntities(alt)
      .replaceAll('[', '(')
      .replaceAll(']', ')')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (url.isEmpty) {
    return cleanAlt;
  }
  return '![$cleanAlt]($url)';
}

String _preReplacement(String inner) {
  var code = inner.replaceAll(
    RegExp(r'</?code\b[^>]*>', caseSensitive: false),
    '',
  );
  code = _decodeEntities(code).replaceAll('\r\n', '\n').trim();
  if (code.isEmpty) {
    return '';
  }
  return '\n\n```\n$code\n```\n\n';
}

String _replaceFormatting(String text) {
  var result = text;
  for (final tag in ['b', 'strong']) {
    result = result.replaceAllMapped(
      RegExp(
        '<$tag\\b[^>]*>(.*?)</$tag\\s*>',
        dotAll: true,
        caseSensitive: false,
      ),
      (match) => '**${_sanitizeInline(match.group(1)!)}**',
    );
  }
  for (final tag in ['i', 'em']) {
    result = result.replaceAllMapped(
      RegExp(
        '<$tag\\b[^>]*>(.*?)</$tag\\s*>',
        dotAll: true,
        caseSensitive: false,
      ),
      (match) => '*${_sanitizeInline(match.group(1)!)}*',
    );
  }
  for (final tag in ['s', 'del', 'strike']) {
    result = result.replaceAllMapped(
      RegExp(
        '<$tag\\b[^>]*>(.*?)</$tag\\s*>',
        dotAll: true,
        caseSensitive: false,
      ),
      (match) => '~~${_sanitizeInline(match.group(1)!)}~~',
    );
  }
  result = result.replaceAllMapped(
    RegExp(r'<code\b[^>]*>(.*?)</code\s*>', dotAll: true, caseSensitive: false),
    (match) {
      final inner = _sanitizeInline(match.group(1)!);
      if (inner.contains('`')) {
        return inner;
      }
      if (inner.contains('\n')) {
        return '\n\n```\n${inner.trim()}\n```\n\n';
      }
      return '`${inner.trim()}`';
    },
  );
  return result;
}

String _replaceBlocks(String text) {
  var result = text;
  result = result.replaceAllMapped(
    RegExp(
      r'<h([1-6])\b[^>]*>(.*?)</h\1\s*>',
      dotAll: true,
      caseSensitive: false,
    ),
    (match) =>
        '\n\n${'#' * int.parse(match.group(1)!)} '
        '${_sanitizeInline(match.group(2)!).trim()}\n\n',
  );
  result = result.replaceAllMapped(
    RegExp(
      r'<summary\b[^>]*>(.*?)</summary\s*>',
      dotAll: true,
      caseSensitive: false,
    ),
    (match) => '\n\n**${_sanitizeInline(match.group(1)!).trim()}**\n\n',
  );
  result = result.replaceAllMapped(
    RegExp(
      r'<blockquote\b[^>]*>(.*?)</blockquote\s*>',
      dotAll: true,
      caseSensitive: false,
    ),
    (match) {
      final inner = _sanitizeInline(match.group(2)!).trim();
      if (inner.isEmpty) {
        return '';
      }
      final quoted = inner
          .split('\n')
          .map((line) => line.trim().isEmpty ? '>' : '> $line')
          .join('\n');
      return '\n\n$quoted\n\n';
    },
  );
  result = result.replaceAll(
    RegExp(r'<hr\b[^>]*/?>', caseSensitive: false),
    '\n\n---\n\n',
  );
  result = result.replaceAllMapped(
    RegExp(r'<li\b[^>]*>', caseSensitive: false),
    (_) => '\n- ',
  );
  result = result.replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '');
  result = result.replaceAll(
    RegExp(r'</?(?:td|th)(?:\s[^>]*)?/?>', caseSensitive: false),
    ' | ',
  );
  result = result.replaceAll(
    RegExp(
      r'</?(?:p|div|section|article|header|footer|details|table|thead|tbody|tfoot|tr|ul|ol|dl|dd|dt)(?:\s[^>]*)?/?>',
      caseSensitive: false,
    ),
    '\n\n',
  );
  return result;
}

String? _attributeValue(String tag, String name) {
  for (final match in _attribute.allMatches(tag)) {
    if (match.group(1)!.toLowerCase() != name.toLowerCase()) {
      continue;
    }
    final value = match.group(3) ?? match.group(4) ?? match.group(5) ?? '';
    return _decodeEntities(value);
  }
  return null;
}

String _firstSrcsetUrl(String? srcset) {
  if (srcset == null || srcset.trim().isEmpty) {
    return '';
  }
  final first = srcset.split(',').first.trim();
  if (first.isEmpty) {
    return '';
  }
  return _decodeEntities(first.split(RegExp(r'\s+')).first.trim());
}

bool _isWebUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.trim().isEmpty) {
    return false;
  }
  return switch (uri.scheme.toLowerCase()) {
    'http' || 'https' => true,
    _ => false,
  };
}

String _decodeEntities(String text) {
  var result = text;
  result = result.replaceAll(RegExp(r'&nbsp;|&#160;|&#x[Aa]0;'), ' ');
  result = result.replaceAll(RegExp(r'&lt;|&#60;|&#x3[Cc];'), '<');
  result = result.replaceAll(RegExp(r'&gt;|&#62;|&#x3[Ee];'), '>');
  result = result.replaceAll(RegExp(r'&quot;|&#34;|&#x22;'), '"');
  result = result.replaceAll(RegExp(r'&apos;|&#39;|&#x27;'), "'");
  result = result.replaceAll(RegExp(r'&amp;|&#38;|&#x26;'), '&');
  return result;
}
