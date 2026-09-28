// One delegated listener for every framed code block on the page, so blocks
// rendered anywhere (docs, blog, MDX components) get the same behavior.
const RESET_AFTER_MS = 1600;

document.addEventListener('click', async (event) => {
  const button = (event.target as HTMLElement | null)?.closest<HTMLButtonElement>('[data-code-copy]');
  if (!button) return;
  const code = button.closest('[data-code-block]')?.querySelector('pre');
  if (!code) return;

  try {
    await navigator.clipboard.writeText(code.innerText.replace(/\n$/, ''));
    button.textContent = 'Copied';
  } catch {
    button.textContent = 'Copy Failed';
  }
  window.setTimeout(() => {
    button.textContent = 'Copy';
  }, RESET_AFTER_MS);
});
