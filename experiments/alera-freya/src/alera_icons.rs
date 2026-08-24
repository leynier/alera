use freya::prelude::Bytes;

macro_rules! embedded_svg {
    ($name:ident, $path:literal) => {
        pub fn $name() -> Bytes {
            Bytes::from_static(include_bytes!($path))
        }
    };
}

// Flutter uses the bundled VS Code Codicons font for source-control actions.
// Reuse the exact SVG outlines already exported for the GPUI client so the
// Freya client does not substitute similar Lucide glyphs.
embedded_svg!(git_commit, "../../alera-gpui/assets/codicons/check.svg");
embedded_svg!(git_stage, "../../alera-gpui/assets/codicons/add.svg");
embedded_svg!(git_unstage, "../../alera-gpui/assets/codicons/remove.svg");
embedded_svg!(git_discard, "../../alera-gpui/assets/codicons/discard.svg");
embedded_svg!(git_fetch, "../../alera-gpui/assets/codicons/git-fetch.svg");
embedded_svg!(git_pull, "../../alera-gpui/assets/codicons/repo-pull.svg");
embedded_svg!(git_push, "../../alera-gpui/assets/codicons/repo-push.svg");
embedded_svg!(git_sync, "../../alera-gpui/assets/codicons/sync.svg");
embedded_svg!(
    git_publish,
    "../../alera-gpui/assets/codicons/cloud-upload.svg"
);
embedded_svg!(git_stash, "../../alera-gpui/assets/codicons/git-stash.svg");
embedded_svg!(
    git_stash_pop,
    "../../alera-gpui/assets/codicons/git-stash-pop.svg"
);
embedded_svg!(git_refresh, "../../alera-gpui/assets/codicons/refresh.svg");
