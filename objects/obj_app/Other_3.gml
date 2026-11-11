/// Game end - keep the session safe
/// Runs once as the app closes: writes the project to the autosave file
/// (reopened next launch by Create_0) and saves the settings ini.

// dev page screenshots (-adam_shots) loaded someone else's project: save nothing
if (shot_on) { exit; }
file_write_text(autosave_path(), project_to_json(proj));
settings_save();
