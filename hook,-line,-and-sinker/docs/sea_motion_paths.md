# Editing dive, surfacing and companion motion in Godot

Open **scenes/sea_area.tscn** and expand **Sea → Points → MotionPaths**.
Each named animation has two different controls:

- Select its child **Path** (a Godot **Path2D**) and use the 2D viewport's path tools to move its Bézier points and handles. This determines the **shape** of the movement. The **final point of PenniDiveDescent** is Penni's actual underwater destination. It is no longer replaced by an automatic search or a hidden X offset.
- Select the parent animation node (a **SeaMotionPath**) in the Inspector. **Duration Seconds** controls total travel time. Click **Speed Curve** to edit a native Godot **Curve**: X is normalized time (0→1), and Y is **instantaneous velocity**, not location. Raise a section to make that part faster; lower it to slow down. The speed graph is integrated and normalized so the animation always finishes at its endpoint in the chosen duration.

| Motion | What it animates |
| --- | --- |
| PenniDiveJump | Penni's jump from dock to splash (ends exactly where the splash appears) |
| PenniDiveDescent | Penni sinking into deep open water after the splash |
| CompanionDiveJump | Each selected companion jumping from the dock; the curve is shifted to their actual start/landing to avoid snapping |
| CompanionDiveDescent | Temporary fish descending alongside Penni after their splash |
| PenniSurface | Penni returning from the sea to the dock |
| CompanionSurface | **All** companion fish returning from underwater to their human-form dock landing; Silas's first-land reveal uses this exact same path |

The motions stay in the existing scene; there is no separate player, world or camera. For companions, the shape is smoothly anchored to their **actual starting position** and their exact human sprite landing center, so the final poof stays aligned with the land actor even if you reshape the curve.

The **Entry** and **SilasSurfaceApproach** markers are retained as reference points for older scene data/tests, but the *movement trajectory* is controlled by the paths above, not those markers. **SilasDockWait** still controls the human landing slot. The animation speed curves and paths can be tuned independently without changing combat speeds, recruitment dialogue or follow behavior.
