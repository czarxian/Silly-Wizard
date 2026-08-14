Drop raw source `.abc` files here (one per tune, named `<Whatever>.abc`).

Then in-game:
  I         scan and report  — matches each file to a tune folder, changes nothing
  Shift+I   apply            — copies matched files to datafiles/tunes/<Tune>/<Tune>.abc

Matching normalises case, punctuation and a leading "The", and checks both the filename
and the ABC `T:` title against existing tune folder names.

Files reported as `new` or `ambiguous` are never copied — resolve those by renaming the
file to match the intended tune folder.

This folder is a staging area only. The authoritative source for a tune is
`datafiles/tunes/<Tune>/<Tune>.abc` — see TUNE_PIPELINE_CONTRACT.md §7.
