/// Free everything

sfx_preview_stop();
music_preview_free();
spr_cache_free();
backdrop_gfx_free();
ds_map_destroy(ui_rects);
ds_map_destroy(ui_anim);
ds_map_destroy(ui_scroll);
if (sprite_exists(global.spr_px)) { sprite_delete(global.spr_px); }
if (sprite_exists(global.spr_boing_red)) { sprite_delete(global.spr_boing_red); }
if (sprite_exists(global.spr_boing_white)) { sprite_delete(global.spr_boing_white); }
theme_free();
