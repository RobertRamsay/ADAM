/// Async - HTTP: the FS-UAE download and the "new version" check
/// Runs whenever an http_* request finishes or reports progress; each
/// handler checks async_load's id against its own request and ignores the rest.

fsuae_download_async();
update_async();
