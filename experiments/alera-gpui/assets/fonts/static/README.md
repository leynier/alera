# Static font instances

These are full instances of the exact variable fonts in the repository's `assets/fonts/`, generated with `uv run experiments/alera-gpui/tool/instantiate_fonts.py` and FontTools 4.63.0. Inter retains its default optical-size coordinate (14); both families retain original outlines, glyph coverage, copyright and license records. The OFL files remain in the parent directory.

The pinned GPUI/font-kit backend selects registered faces rather than instantiating variable weight axes. Registering only the variable file therefore selected the regular outline for every requested weight on macOS. These instances cover all hundred-step weights exposed by the terminal settings (JetBrains Mono's source maximum is 800).

Run `cargo run --manifest-path experiments/alera-gpui/Cargo.toml --example check_font_faces --locked` to verify distinct native face selection without opening a window or runtime. `-- --variable-baseline` reports the old variable-only behavior. The small macOS weight-200 matching adapter compensates for the pinned font-kit's CoreText conversion; it does not apply to user-installed families.
