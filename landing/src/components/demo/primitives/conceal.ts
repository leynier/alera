/**
 * Attributes for a node that starts out of the picture and is brought in by a
 * storyboard show key: out of the layout, invisible, and marked so seeking
 * back before its key restores exactly this.
 */
export function concealedAttributes(concealed: boolean | undefined) {
  return concealed ? { hidden: true, 'data-demo-concealed': '', style: 'opacity: 0; visibility: hidden' } : {};
}
