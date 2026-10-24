//! Small host adapters for the unmodified Anki inference interfaces.
use std::{fs::File, io, path::Path};
#[derive(Clone, Copy)]
#[allow(dead_code)]
pub enum ReviewCardOrder { IntervalsAscending, IntervalsDescending, EaseAscending, EaseDescending,
    RetrievabilityAscending, RetrievabilityDescending, RelativeOverdueness, Random, Added, ReverseAdded,
    Day, DayThenDeck, DeckThenDay }
pub fn new_tempfile_in_parent_of(path: &Path) -> io::Result<tempfile::NamedTempFile> {
    tempfile::NamedTempFile::new_in(path.parent().unwrap_or(Path::new(".")))
}
pub fn atomic_rename(file: tempfile::NamedTempFile, path: &Path, _: bool) -> io::Result<()> {
    file.persist(path).map(|_| ()).map_err(|e| e.error)
}
pub fn open_file(path: &Path) -> io::Result<File> { File::open(path) }
pub fn remove_file(path: &Path) -> io::Result<()> { std::fs::remove_file(path) }
