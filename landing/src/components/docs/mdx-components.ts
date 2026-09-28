import Callout from './Callout.astro';
import DocCard from './DocCard.astro';
import DocCardGrid from './DocCardGrid.astro';
import DocLinkButton from './DocLinkButton.astro';
import ShortcutTable from './ShortcutTable.astro';
import Steps from './Steps.astro';

/**
 * Components available to every docs page without an import, passed to
 * `<Content components={...} />` by the docs route.
 */
export const docsMdxComponents = {
  Callout,
  DocCard,
  DocCardGrid,
  DocLinkButton,
  ShortcutTable,
  Steps,
};
