# Editing dive, surfacing and companion motion in Godot

Open **scenes/sea_area.tscn** and expand **Sea → Points**.

Each named motion has two editable controls:

- Select its child **Path** (a Godot **Path2D**) and reshape the Bézier points and handles in the 2D viewport. This controls **where** the actor moves.
- Select the parent **SeaMotionPath** node and edit **Duration Seconds** for total travel time or **Speed Curve** for velocity over time. The curve's X axis is normalized time and its Y axis is *instantaneous speed*, not position. Motion is integrated and normalized to finish at the authored destination.

| Motion | What it animates |
| --- | --- |
| PenniDiveJump | **One continuous movement**, from the dock through the surface to the deep-water destination |
| CompanionDiveJump | One continuous movement for each guest, with individual starting positions and underwater destinations |
| PenniSurface | Penni's return from the sea to the dock |
| CompanionSurface | Companion fish returning from the sea to human-form dock landing, including Silas's first-land reveal |

**There is no separate descent path.** When the player or companion crosses the sea surface (from `DivingWorld.SEA_TOP`), the splash happens. Penni switches to her underwater swim pose and the companion's temporary human sprite is replaced by its fish sprite **without restarting or replacing the movement tween**. The path then continues underwater to its final point. The existing water visuals can respond to world position/depth independently.

Companions use the same authored path shape with their real starting positions and index-spaced underwater endpoints. Their entry animations run with short overlapping start staggers instead of finishing one at a time. The per-companion surface return remains a separate movement, with individual dock landing positions.

The **Entry** and **SilasSurfaceApproach** markers are retained for legacy reference, not for entry motion geometry. **SilasDockWait** still controls the human landing slots.

Edit the path's *last point* to change where the dive ends. Speed curves only affect the rate of movement along the same path; they do not introduce additional movement phases.
