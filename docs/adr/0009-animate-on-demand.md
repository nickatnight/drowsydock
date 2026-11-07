# ADR-0009: Animate on demand: paused views, scheduled one-shots, 30 fps loops and rasterized parts

## Status

Accepted (job 003, plan slice 9)

## Context

The spec's CPU budgets are ≤ 1.0% averaged over 60 s while awake and ≤ 3.0% in the looping states (`noddingOff`, `asleep`). An `SKView` that isn't paused runs its update and render loop on every display refresh, whether or not anything moves.

In an offscreen measurement of the asleep loop (`SKRenderer` driving the real `MascotScene` at 30 fps), the first version cost 3.1% CPU. The profile showed SpriteKit re-stroking every `SKShapeNode` path on every frame (`SKCShapeNode::_NEW_copyRenderPathData`), on top of the per-frame Metal submission.

## Decision

- `AmbientSchedule`, in the pure core, returns either a one-shot action after a random pause (blink every 8 to 20 s, slow blink every 10 to 20 s, yawn-and-nod every 40 to 50 s) or a loop (floating "z"s, snore).
- For a one-shot, `MascotScene` sleeps in a main-actor `Task`, unpauses its view, plays the action and pauses again when the action's completion runs. The view never runs between actions.
- A loop keeps the view running. Every view is capped at 30 fps (`preferredFramesPerSecond`).
- While the overlay is hidden or faded out, `MascotScene.setActive(false)` cancels the schedule, stops the actions and pauses the view.
- Parts that never move on their own are drawn once into cached textures (`SKEffectNode.shouldRasterize`): the tail, body and belly; the paws; the head behind the lids; the head in front of the lids; each lid; each "z". Moving, scaling or fading a cached group reuses its texture.

## Alternatives considered

- **Keep the view running and let idle frames be cheap.** A running view still renders at the display's rate.
- **Lower the loop rate to 20 fps instead of rasterizing.** It cuts the cost by a third, but the rasterized loop at 30 fps already measured 2.0 to 2.1%. 20 fps stays available as a one-constant fallback if the on-screen measurement (QA 9.7) exceeds the budget.
- **Bake sprite textures at launch.** It would need a view to render into before the overlay exists. Rasterized effect nodes give the same per-frame cost without that step.

## Consequences

- Measured offscreen (one 60 s run per state, `top` once a second, 55 to 57 samples): awake 0.22%, nodding off 2.10%, asleep 2.03%. After rasterizing, the remaining per-frame cost is mostly SpriteKit's Metal submission (`SKCRenderer::flushRenderOps`). That is fixed per frame, so the loop cost now scales with the frame rate, not with the drawing.
- The offscreen figure leaves out drawable presentation and WindowServer compositing, so the on-screen cost will be somewhat higher. QA 9.6 and 9.7 measure the real app.
- A rasterized group is cached at the scale it is first drawn at. If the cat were ever drawn larger than its canvas (a zoom effect, say), the cached groups would blur.
