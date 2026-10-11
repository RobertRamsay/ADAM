/// Game end - keep the session safe

// dev page screenshots (-adam_shots) loaded someone else's project: save nothing
if (shot_on) { exit; }
file_write_text(autosave_path(), project_to_json(proj));
settings_save();
