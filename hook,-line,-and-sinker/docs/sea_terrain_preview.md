# Spline sand terrain — isolated preview

This is a **prototype**, not a replacement for the existing sea tiles.

## Try it
1. Open `res://scenes/sea_terrain_preview.tscn` and run **Current Scene (F6)**.
2. Open `res://scenes/sea_terrain.tscn` to edit the reusable **SeaTerrain (Path2D)** node.
3. Select the root `SeaTerrain`, use Godot's **Edit Curve** tool in the 2D toolbar, and move Bézier points or handles. The component **closes the shape automatically**, so do not add another point on top of the first point. Keep the two endpoints on a less-visible bottom/side segment; both are still normal Path2D endpoints.
4. The **Fill** and **Edge** nodes preview the curve while editing. The matching **StaticBody2D/CollisionPolygon2D** is generated at runtime. Edit only the curve, not the generated polygon vertices.
5. Set `fill_texture` and `edge_texture` on SeaTerrain. The initial textures are the user's original 16x16 sand PNGs. `edge_width = 16`, `edge_inset = 8` (pixels) are tunable.

The editor preview updates at most every 50 ms and samples the curve at 4 px for responsive handles. It skips the physics-polygon rebuild entirely while editing; on play, the original curve's 2 px resolution (or your chosen `bake_interval`) is used for the visual and collision geometry.  The edge uses Godot's robust polygon inset instead of shifting individual vertices, avoiding self-crossing at sharp bends. The native `Line2D.closed` option joins the seam. Godot's first and last Path2D points show one Bézier handle each; all **interior** points can have two. Put the endpoints somewhere unimportant, like the bottom of a seabed. The fill is tiled in local-pixel UV coordinates, the edge is a nearest-filtered `Line2D` texture strip, and the collision is built from the same baked `Curve2D` points.

**Safety:** `scenes/sea_area.tscn`, `Solids`, the underwater fish checks, and the existing sea gameplay are not modified. Integrating the new terrain into the sea requires updating `DivingWorld._is_open_water` to respect the spline collision instead of reading only tile cells. This prototype deliberately does not do that yet.
