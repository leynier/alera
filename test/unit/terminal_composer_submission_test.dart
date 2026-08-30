import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_submission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('classifies ACP-compatible image extensions', () {
    expect(
      terminalComposerAttachmentKindForPath('/tmp/image.WEBP'),
      TerminalComposerAttachmentKind.image,
    );
    expect(
      terminalComposerAttachmentKindForPath('/tmp/report.pdf'),
      TerminalComposerAttachmentKind.file,
    );
  });

  test('builds grouped image and file sections after the prompt', () {
    expect(
      buildTerminalComposerSubmission(
        prompt: 'Review these',
        attachments: const <TerminalComposerAttachment>[
          TerminalComposerAttachment(
            id: 'image',
            kind: .image,
            path: '/tmp/before\x1b[201~after.png',
            displayName: 'after.png',
          ),
          TerminalComposerAttachment(
            id: 'file',
            kind: .file,
            path: '/tmp/report.pdf',
            displayName: 'report.pdf',
          ),
        ],
      ),
      'Review these\n\n'
      'Attached images:\n'
      '/tmp/before\u241b[201~after.png\n'
      'Attached files:\n'
      '/tmp/report.pdf',
    );
  });

  test('supports attachment-only and text-only submissions', () {
    expect(
      buildTerminalComposerSubmission(
        prompt: '',
        attachments: const <TerminalComposerAttachment>[
          TerminalComposerAttachment(
            id: 'file',
            kind: .file,
            path: '/tmp/report.pdf',
            displayName: 'report.pdf',
          ),
        ],
      ),
      'Attached files:\n/tmp/report.pdf',
    );
    expect(
      buildTerminalComposerSubmission(
        prompt: 'Text only',
        attachments: const <TerminalComposerAttachment>[],
      ),
      'Text only',
    );
  });

  test('relativizes attachment paths inside the workspace', () {
    expect(
      buildTerminalComposerSubmission(
        prompt: 'Review these',
        workspacePath: '/tmp/project',
        attachments: const <TerminalComposerAttachment>[
          TerminalComposerAttachment(
            id: 'image',
            kind: .image,
            path: '/tmp/project/assets/before.png',
            displayName: 'before.png',
          ),
          TerminalComposerAttachment(
            id: 'file',
            kind: .file,
            path: '/tmp/project/docs/report.pdf',
            displayName: 'report.pdf',
          ),
          TerminalComposerAttachment(
            id: 'outside',
            kind: .file,
            path: '/tmp/other/notes.txt',
            displayName: 'notes.txt',
          ),
        ],
      ),
      'Review these\n\n'
      'Attached images:\n'
      '${p.join('assets', 'before.png')}\n'
      'Attached files:\n'
      '${p.join('docs', 'report.pdf')}\n'
      '/tmp/other/notes.txt',
    );
  });
}
