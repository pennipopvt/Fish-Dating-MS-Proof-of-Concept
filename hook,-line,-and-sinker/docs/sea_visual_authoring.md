# Sea visual authoring — reusable lighting and decorations

These scenes are **tools** for level design, not additional gameplay systems.
Existing SeaTerrain shapes, fish, collisions, waterline, and camera are unchanged.

## Decoration library
- Drag `res://scenes/sea_decoration.tscn` into `sea_area.tscn` under **Details**, or any visual-only grouping.
- Select the **SeaDecoration** instance. Use its native **Animation** dropdown to select the look, plus **Speed Scale**, **Flip H**, **Modulate**, and **Z Index** for per-instance variations.
- All instances reference `res://resources/animations/sea_decorations.tres`. Select the **Sprite Frames** resource in the Inspector to open the SpriteFrames editor and add named animations plus their individual frames/FPS. Adding a name there makes it selectable in every SeaDecoration instance; leave the library shared (don't Make Unique).
- Static props are simply one-frame animations. Animation playback works when the scene runs; **Preview In Editor** can be disabled for a quieter editing experience.
- The current **placeholder** animation is a single 16×16 sand swatch so you can see and test the scene immediately. **No kelp/coral artwork was invented**. Replace the placeholder and create named animations when your art is ready.
- No collision nodes are included.

## Sunlight shafts
- Drag `res://scenes/sea_sunbeam.tscn` into `sea_area.tscn` (under a **Sunbeams** Node2D if you want them organized). **No existing scene decorations have been moved or automatically placed.**
- Position its origin near the waterline and use the built-in **Rotation** setting to point it diagonally. Shape, Light, and Movement groups expose **Beam Width**, **Beam Length**, **Strength**, **Beam Color**, **Sway Pixels**, **Sway Speed**, and **Follow Day Night**.
- The child Polygon2D is drawn with a small additive shader, with feathered edges and distance falloff; it's non-collidable and can't change fishing mechanics.
- When running in World, `world_day_night.gd` tells registered beams the current clock's sunlight intensity, color, and the real waterline. Night fades them almost entirely; turning **Follow Day Night** off preserves manual strength.
- Beam colors and widths work independently per instance; no editing or duplicating shader files needed.
- The shader clips rays above the actual water surface in gameplay, and their default Z Index draws ahead of background terrain but behind fish.
- For a simple visual preview, open `res://scenes/sea_visual_preview.tscn` in the editor. This is **not** the main sea scene.

## Underwater brightness
- Daytime water palette is slightly lighter in `scripts/world_day_night.gd`; this is important because its clock animates the Water shader's color and overrides static material settings.
- The underwater camera tint opacity is lower, and the existing translucent Water shader contributes a little less haze when submerged. Dawn/sunset and night are retained.
- No changes to the existing reflected water surface, terrain textures, lighting collisions, or waterline transition.
