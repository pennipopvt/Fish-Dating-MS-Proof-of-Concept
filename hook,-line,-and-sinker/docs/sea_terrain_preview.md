# Spline sand terrain — isolated preview

This is a **prototype**, not a replacement for the existing sea tiles.

## Try it
1. Open `res://scenes/sea_terrain_preview.tscn` and run **Current Scene (F6)**.
2. Open `res://scenes/sea_terrain.tscn` to edit the reusable **SeaTerrain (Path2D)** node.
3. Select the root `SeaTerrain`, use Godot's **Edit Curve** tool in the 2D toolbar, and move Bézier points or handles. For closed islands/rocks, end the curve at the start position using **Close Curve**.
4. The **Fill**, **Edge**, and **StaticBody2D/CollisionPolygon2D** nodes are generated from the same curve. Edit only the curve, not their polygon vertices.
5. Set `fill_texture` and `edge_texture` on SeaTerrain. The initial textures are the user's original 16x16 sand PNGs. `edge_width = 16`, `edge_inset = 8` (pixels) are tunable.

The material and collider update in the editor via a small `@tool` script. The fill is tiled in local-pixel UV coordinates, the edge is a nearest-filtered `Line2D` texture strip, and the collision is built from the same baked `Curve2D` points.

**Safety:** `scenes/sea_area.tscn`, `Solids`, the underwater fish checks, and the existing sea gameplay are not modified. Integrating the new terrain into the sea requires updating `DivingWorld._is_open_water` to respect the spline collision instead of reading only tile cells. This prototype deliberately does not do that yet.
