# Alera patches

This directory vendors `gpui-component` 0.5.1 because the GPUI experiment is pinned to GPUI 0.2.2 and no compatible upstream patch release exists.

The only behavioral patch computes the editor line-number gutter from the actual line count. It backports the upstream fix introduced by `longbridge/gpui-component` commit `9aedbb8779a833c114bbfffbc308bda1d2dc6778` without adopting later incompatible GPUI or folding API changes. The 0.5.1 six-pixel inset remains because this version has no folding gutter and Alera's normalized Flutter comparison requires that spacing.
