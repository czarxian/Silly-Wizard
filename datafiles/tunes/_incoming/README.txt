Drop raw source `.abc` files here (one per tune). Filenames don't matter — the tune folder
is taken from the ABC `T:` title.

Then in-game press **N**.

For each file it writes, into `datafiles/tunes/<T: title>/`:
    <Tune>.abc             your source, verbatim
    <Tune>.compiled.json   compiled layers L0/L1/L2 + provenance
    <Tune>.meta.json       defaults for rhythm rule, variant set, pulse, annotations

The folder is created if absent and updated if present. Legacy `<Tune>.json`, `score/` and
snippet files are never written — those are what the current runtime plays, and they stay
untouched until the new path can play a tune.

Because the folder name comes from the `T:` title, a title that differs from an existing folder
produces a *new folder* rather than overwriting the wrong tune. If an unexpected folder appears,
the `T:` title and the existing folder name disagree — fix the title, delete the stray folder,
and press N again.

See TUNE_PIPELINE_CONTRACT.md §7.
