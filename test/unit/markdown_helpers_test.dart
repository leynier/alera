import 'package:alera/src/features/session/presentation/widgets/markdown_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeMarkdownNewlines', () {
    test('joins single-newline sentences into one paragraph', () {
      expect(
        normalizeMarkdownNewlines('First sentence.\nSecond sentence.'),
        'First sentence. Second sentence.',
      );
    });

    test('preserves paragraph breaks', () {
      expect(
        normalizeMarkdownNewlines('Paragraph one.\n\nParagraph two.'),
        'Paragraph one.\n\nParagraph two.',
      );
    });

    test('preserves newlines before unordered list items', () {
      expect(
        normalizeMarkdownNewlines('Intro:\n- Item one\n- Item two'),
        'Intro:\n- Item one\n- Item two',
      );
    });

    test('preserves newlines before ordered list items', () {
      expect(
        normalizeMarkdownNewlines('Intro:\n1. First\n2. Second'),
        'Intro:\n1. First\n2. Second',
      );
    });

    test('preserves newlines before headings', () {
      expect(
        normalizeMarkdownNewlines('Some text.\n# Heading'),
        'Some text.\n# Heading',
      );
    });

    test('preserves newlines before blockquotes', () {
      expect(
        normalizeMarkdownNewlines('Some text.\n> Quote'),
        'Some text.\n> Quote',
      );
    });

    test('preserves content inside code blocks', () {
      expect(
        normalizeMarkdownNewlines(
          'Before.\n```\nline1\nline2\n```\nAfter.',
        ),
        'Before. ```\nline1\nline2\n``` After.',
      );
    });

    test('preserves newlines between table rows', () {
      expect(
        normalizeMarkdownNewlines('Header\n| A | B |\n| 1 | 2 |'),
        'Header\n| A | B |\n| 1 | 2 |',
      );
    });

    test('joins word-wrapped table cell content starting with pipe', () {
      expect(
        normalizeMarkdownNewlines(
          '| Seguimiento | Falta de visibilidad\n'
          '| Indicadores semanales | Mejor control |',
        ),
        '| Seguimiento | Falta de visibilidad '
        '| Indicadores semanales | Mejor control |',
      );
    });

    test('preserves horizontal rules', () {
      expect(
        normalizeMarkdownNewlines('Above\n---\nBelow'),
        'Above\n---\nBelow',
      );
    });

    test('normalizes real LLM output with mixed content', () {
      final input = 'Aquí tienes un texto pequeño con listas:\n\n'
          'Mi rutina de la mañana es simple y ordenada.\n'
          'Primero preparo lo necesario para empezar bien el día:\n\n'
          '- Agua\n- Café\n- Fruta\n\n'
          'También quiero seguir este orden:\n\n'
          '1. Trabajar en la mañana\n'
          '2. Descansar después de comer\n\n'
          'Si quieres, puedo escribir otro más formal,\n'
          'más creativo o más largo.';
      final expected = 'Aquí tienes un texto pequeño con listas:\n\n'
          'Mi rutina de la mañana es simple y ordenada. '
          'Primero preparo lo necesario para empezar bien el día:\n\n'
          '- Agua\n- Café\n- Fruta\n\n'
          'También quiero seguir este orden:\n\n'
          '1. Trabajar en la mañana\n'
          '2. Descansar después de comer\n\n'
          'Si quieres, puedo escribir otro más formal, '
          'más creativo o más largo.';
      expect(normalizeMarkdownNewlines(input), expected);
    });

    test('handles empty text', () {
      expect(normalizeMarkdownNewlines(''), '');
    });

    test('handles text without newlines', () {
      expect(normalizeMarkdownNewlines('Hello world'), 'Hello world');
    });

    test('preserves star-prefixed unordered list items', () {
      expect(
        normalizeMarkdownNewlines('Intro:\n* Alpha\n* Beta'),
        'Intro:\n* Alpha\n* Beta',
      );
    });

    test('preserves checkboxes', () {
      expect(
        normalizeMarkdownNewlines('[x] Done\n[ ] Pending'),
        '[x] Done\n[ ] Pending',
      );
    });

    test('does not produce double spaces when line ends with trailing space', () {
      expect(
        normalizeMarkdownNewlines('conviene preparar varios \naspectos con anticipación.'),
        'conviene preparar varios aspectos con anticipación.',
      );
    });

    test('collapses paragraph breaks between consecutive ordered list items', () {
      expect(
        normalizeMarkdownNewlines('1. First\n\n2. Second\n\n3. Third'),
        '1. First\n2. Second\n3. Third',
      );
    });

    test('collapses paragraph breaks between consecutive unordered list items', () {
      expect(
        normalizeMarkdownNewlines('- Alpha\n\n- Beta\n\n- Gamma'),
        '- Alpha\n- Beta\n- Gamma',
      );
    });

    test('preserves paragraph break between list and non-list text', () {
      expect(
        normalizeMarkdownNewlines('1. First\n\n2. Second\n\nSome text.'),
        '1. First\n2. Second\n\nSome text.',
      );
    });

    test('joins list item continuation text with space', () {
      expect(
        normalizeMarkdownNewlines(
          '4. Revisar el equipo.\n\n'
          '5. Realizar una última verificación el día\n'
          'anterior.',
        ),
        '4. Revisar el equipo.\n'
        '5. Realizar una última verificación el día anterior.',
      );
    });

    test('collapses paragraph breaks between consecutive table rows', () {
      expect(
        normalizeMarkdownNewlines(
          '| A | B |\n\n|---|---|\n\n| 1 | 2 |\n\n| 3 | 4 |',
        ),
        '| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |',
      );
    });

    test('collapses triple newlines between table rows', () {
      expect(
        normalizeMarkdownNewlines(
          '| A | B |\n\n\n\n|---|---|\n\n\n\n| 1 | 2 |',
        ),
        '| A | B |\n|---|---|\n| 1 | 2 |',
      );
    });

    test('preserves paragraph break between table and non-table text', () {
      expect(
        normalizeMarkdownNewlines(
          '| A | B |\n\n|---|---|\n\n| 1 | 2 |\n\nSome text.',
        ),
        '| A | B |\n|---|---|\n| 1 | 2 |\n\nSome text.',
      );
    });

    test('normalizes real LLM table output with headers and separators', () {
      final input = '## Informe breve de proyecto\n\n'
          'El proyecto **Aurora** avanza de forma estable.\n\n'
          '### Resumen general\n\n'
          '| Área | Estado | Comentario |\n'
          '|---|---|---|\n'
          '| Diseño | Completado | Interfaz principal aprobada |\n'
          '| Desarrollo | En progreso | Módulo de autenticación casi listo |\n\n'
          '### Métricas principales\n\n'
          '| Indicador | Valor actual | Objetivo |\n'
          '|---|---:|---:|\n'
          '| Avance total | 72% | 100% |\n'
          '| Tareas completadas | 18 | 25 |\n\n'
          '### Próximos pasos\n\n'
          '1. Finalizar el módulo.\n'
          '2. Corregir el error.\n\n'
          'Texto final.';
      final expected = '## Informe breve de proyecto\n\n'
          'El proyecto **Aurora** avanza de forma estable.\n\n'
          '### Resumen general\n\n'
          '| Área | Estado | Comentario |\n'
          '|---|---|---|\n'
          '| Diseño | Completado | Interfaz principal aprobada |\n'
          '| Desarrollo | En progreso | Módulo de autenticación casi listo |\n\n'
          '### Métricas principales\n\n'
          '| Indicador | Valor actual | Objetivo |\n'
          '|---|---:|---:|\n'
          '| Avance total | 72% | 100% |\n'
          '| Tareas completadas | 18 | 25 |\n\n'
          '### Próximos pasos\n\n'
          '1. Finalizar el módulo.\n'
          '2. Corregir el error.\n\n'
          'Texto final.';
      expect(normalizeMarkdownNewlines(input), expected);
    });

    test('preserves content inside unclosed code fence', () {
      // The newline before the fence is joined as a space (same as closed
      // blocks), but internal content stays intact.
      expect(
        normalizeMarkdownNewlines(
          'Before.\n```python\ndef greet(name):\n    return f"Hello {name}"',
        ),
        'Before. ```python\ndef greet(name):\n    return f"Hello {name}"',
      );
    });

    test('handles unclosed code fence after a closed code block', () {
      expect(
        normalizeMarkdownNewlines(
          '```js\nvar x = 1;\n```\nMiddle text.\n```python\ndef foo():\n    pass',
        ),
        '```js\nvar x = 1;\n``` Middle text. ```python\ndef foo():\n    pass',
      );
    });

    test('handles unclosed code fence with no content after fence marker', () {
      expect(
        normalizeMarkdownNewlines('Some intro.\n```'),
        'Some intro. ```',
      );
    });

    test('collapses loose list items from LLM output', () {
      final input = 'Lista numerada de pasos a seguir:\n\n'
          '1. Confirmar la disponibilidad del espacio.\n\n'
          '2. Enviar las invitaciones.\n\n'
          '3. Coordinar la comida y la bebida.\n\n'
          '4. Revisar el equipo técnico necesario.\n\n'
          '5. Realizar una última verificación el día\n'
          'anterior.\n\n'
          'Si quieres, también puedo generarlo.';
      final expected = 'Lista numerada de pasos a seguir:\n\n'
          '1. Confirmar la disponibilidad del espacio.\n'
          '2. Enviar las invitaciones.\n'
          '3. Coordinar la comida y la bebida.\n'
          '4. Revisar el equipo técnico necesario.\n'
          '5. Realizar una última verificación el día anterior.\n\n'
          'Si quieres, también puedo generarlo.';
      expect(normalizeMarkdownNewlines(input), expected);
    });
  });
}
