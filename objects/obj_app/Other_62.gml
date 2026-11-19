/// Async - HTTP: the FS-UAE download, the "new version" check, and the answer
/// to a 'Submit your game' or crash report post (scr_report)
/// Runs whenever an http_* request finishes or reports progress; each
/// handler checks async_load's id against its own request and ignores the rest.

fsuae_download_async();
update_async();
report_async();
