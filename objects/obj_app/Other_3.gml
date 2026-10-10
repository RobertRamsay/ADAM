/// Game end - keep the session safe

file_write_text(autosave_path(), project_to_json(proj));
settings_save();
