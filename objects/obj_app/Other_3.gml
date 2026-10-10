/// Game end - keep the session safe

file_write_text(autosave_path(), json_stringify(proj));
settings_save();
