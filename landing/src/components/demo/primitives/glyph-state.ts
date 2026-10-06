/** The states `AgentRunStateIndicator` can draw, plus the idle dot in its two colors. */
export type GlyphState = 'idle' | 'idle-active' | 'working' | 'waiting' | 'blocked' | 'done' | 'interrupted';

/**
 * The workspace badge (`agentRunStatusBadge`), which sums up every agent in
 * the workspace rather than the one the leading glyph draws.
 */
export type BadgeState = 'none' | 'waiting' | 'blocked' | 'interrupted' | 'done';

/** The badge a workspace with one agent in [state] shows. */
export function badgeStateFor(state: GlyphState): BadgeState {
  return state === 'waiting' || state === 'blocked' || state === 'interrupted' || state === 'done' ? state : 'none';
}
