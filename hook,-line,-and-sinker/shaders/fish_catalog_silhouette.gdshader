shader_type canvas_item;

// Solid silhouette of the fish's actual outline. Kept on the sprite's
// TextureRect only, so terminal text and borders remain legible.
uniform vec4 silhouette_color: source_color = vec4(0.17, 0.22, 0.26, 1.0);

void fragment() {
    vec4 texel = texture(TEXTURE, UV);
    COLOR = vec4(silhouette_color.rgb, texel.a * silhouette_color.a * COLOR.a);
}
