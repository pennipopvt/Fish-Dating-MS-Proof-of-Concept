# Spline sand terrain — isolated preview

This is a **prototype**, not a replacement for the existing sea tiles.

## Try it
1. Open `res://scenes/sea_terrain_preview.tscn` and run **Current Scene (F6)**.
2. Open `res://scenes/sea_terrain.tscn` to edit the reusable **SeaTerrain (Path2D)** node.
3. Select the root `SeaTerrain`, use Godot's **Edit Curve** tool in the 2D toolbar, and move Bézier points or handles. The **editable Path2D curve is closed**: Godot uses a matching first/last control point. You don't need to add or maintain that seam yourself. New control points automatically gain two smooth Bézier handles after a short editor settle (~0.1 sec). Keep the seam on a less-visible bottom/side section if possible.
4. The **Fill** and **Edge** nodes preview the curve while editing. The matching **StaticBody2D/CollisionPolygon2D** is generated at runtime. Edit only the curve, not the generated polygon vertices.
5. Set `fill_texture` and `edge_texture` on SeaTerrain. The initial textures are the user's original 16x16 sand PNGs. `edge_width = 16`, `edge_inset = 8` (pixels) are tunable.
6. For decorative background shapes, select that individual **SeaTerrain** instance and turn **Collision Enabled** off. Turn **Show Edge Texture** off if you want only the filled silhouette. Both are on by default; textures and curves remain editable. Change the built-in **Z Index** for foreground/background layering. Fish, Penni and the net ignore disabled terrain collision.

The editor preview updates at most every 50 ms and samples the curve at 4 px for responsive handles. It skips the physics-polygon rebuild entirely while editing; on play, the original curve's 2 px resolution (or your chosen `bake_interval`) is used for the visual and collision geometry.  The edge uses Godot's robust polygon inset instead of shifting individual vertices, avoiding self-crossing at sharp bends. The native `Line2D.closed` option joins the seam. Godot still shows one Bézier handle at each overlapping start/end seam point (a native Path2D limitation); new interior points start with both handles. Position the seam somewhere unimportant, like the bottom of a seabed. The fill is tiled in local-pixel UV coordinates, the edge is a nearest-filtered `Line2D` texture strip, and the collision is built from the same baked `Curve2D` points.

**Safety:** `scenes/sea_area.tscn`, `Solids`, the underwater fish checks, and the existing sea gameplay are not modified. Integrating the new terrain into the sea requires updating `DivingWorld._is_open_water` to respect the spline collision instead of reading only tile cells. This prototype deliberately does not do that yet.
