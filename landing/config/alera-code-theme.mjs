// Shiki theme for fenced code on the docs and the blog, derived from the
// app's `_aleraEditorSyntaxTheme` (lib/src/features/settings/domain/
// editor_syntax_theme_catalog.dart) so code on the site reads like code in
// Alera. Comments use the landing's faint #8c8c8c instead of the app's
// #606060, which fails 4.5:1 contrast on the #181818 block background.
const keyword = '#C792EA';
const operator = '#89DDFF';
const fn = '#82AAFF';
const literal = '#FFCB6B';
const variable = '#FFCC80';
const string = '#22C55E';
const number = '#F59E0B';
const deletion = '#F87171';
const muted = '#A1A1A1';
const comment = '#8C8C8C';

export const aleraCodeTheme = {
  name: 'alera-dark',
  type: 'dark',
  colors: {
    'editor.background': '#181818',
    'editor.foreground': '#F5F5F5',
  },
  tokenColors: [
    {
      scope: ['comment', 'punctuation.definition.comment', 'markup.quote'],
      settings: { foreground: comment },
    },
    {
      scope: ['keyword', 'keyword.control', 'storage', 'storage.type', 'storage.modifier'],
      settings: { foreground: keyword },
    },
    {
      scope: ['keyword.operator', 'punctuation.accessor', 'entity.name.type', 'support.type', 'entity.other.inherited-class'],
      settings: { foreground: operator },
    },
    {
      scope: ['entity.name.function', 'support.function', 'meta.function-call', 'markup.heading', 'entity.name.tag'],
      settings: { foreground: fn },
    },
    {
      scope: ['string', 'markup.inline.raw', 'markup.inserted', 'punctuation.definition.string'],
      settings: { foreground: string },
    },
    {
      scope: ['constant.numeric'],
      settings: { foreground: number },
    },
    {
      scope: [
        'constant.language',
        'constant.other',
        'support.constant',
        'variable.language',
        'entity.name.class',
        'entity.name.type.class',
        'entity.other.attribute-name',
      ],
      settings: { foreground: literal },
    },
    {
      scope: ['variable', 'variable.other', 'variable.parameter', 'support.type.property-name', 'meta.object-literal.key'],
      settings: { foreground: variable },
    },
    {
      scope: ['meta.preprocessor', 'punctuation.definition.tag', 'punctuation.section'],
      settings: { foreground: muted },
    },
    {
      scope: ['markup.deleted', 'invalid'],
      settings: { foreground: deletion },
    },
  ],
};
