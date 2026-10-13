# Documents, revisions and files

Code: `DocumentAddForm`, `ProcessDocumentAdd`, `AddFilesForm`, `AddFiles`,
`ReserveHome`, `ModifyHome`, `ShowDocument`, `RetrieveFile`,
`RetrieveArchive`, `DeleteConfirm`/`DeleteDocument`, `Resecure`, `XMLUpload`,
`XMLClone`, `XMLOutput.pm`, `XSearch`, and the modules `DocumentSQL.pm`,
`RevisionSQL.pm`, `DocumentUtilities.pm`, `RevisionUtilities.pm`,
`FileSQL.pm`, `FileUtilities.pm`, `FSUtilities.pm`, `DocumentHTML.pm`,
`RevisionHTML.pm`, `FileHTML.pm`, `XRefSQL.pm`, `XRefHTML.pm`.

## Data model

A **Document** is a stable identity: `DocumentID`, `RequesterID` (the Author
who created it), `RequestDate`, and `Alias`, the human identifier such as
`T2500123` (document-type letter plus serial number from
`DocumentType.NextDocNumber`). Everything else lives on a
**DocumentRevision**: title, abstract, keywords, note, publication info,
document type, `VersionNumber`, `SubmitterID` (Author), `RevisionDate`,
`Obsolete`, `QAcheck`. Version 0 is a reserved placeholder ("x0") created by
`ReserveHome` or by reserving a talk. Revisions link to authors
(`RevisionAuthor`, `RevisionAuthorGroup`), topics (`RevisionTopic`), events
(`RevisionEvent`), journals (`RevisionReference`), cross-references
(`DocXRef`) and access lists (`RevisionSecurity`, `RevisionModify`). Each
revision owns zero or more **DocumentFile** rows (`FileName`, `RootFile`
flag for the main file, `Description`, `Date`); a file whose description
contains "delete", "remove" or "ignore" is treated as deleted.

Identifiers in URLs may be either the numeric `DocumentID` or the alias;
`ShowDocument` and `RetrieveFile` accept both (`GetDocumentIDByAlias`).

## Storage

`FSUtilities.pm::GetDirectory` maps (document, version) to
`$file_root/<DocumentID div 1000, 4 digits>/<Alias>/<version, 3 digits>/`
because `$UseAliasAsFileName` is set; `GetURLDir` gives the matching URL
under `/DocDB/`. `MakeDirectory` creates the three levels. Public revisions
get a symlink of the same relative path under `$public_root`
(`MakeLinkDirectory`/`UnlinkDirectory`, driven by
`UpdateRevisionPublicSecurity`). `ProtectDirectory` computes the set of
users and groups that may read a directory, a relic of the per-directory
`.htaccess` scheme; its file writing is commented out and
`RemoteUserHasAccess` now authorizes downloads dynamically.

## Adding a document or a new version

1. `DocumentAddForm` (`mode=add|update|updatedb|reserve`) renders the form:
   title, abstract, keywords, note, document type, dates, authors
   (scroll list or manual text), topics, events, journals, cross-references
   (`xrefs`), view groups (`security`), modify groups (`modify`), sign-off
   list, and `$NumFilesPref` upload slots (`upload1..n`, `main1..n`,
   `description1..n`, or `url1..n`/`newname1..n` for URL upload, or `copy1..n`
   to carry files over). Defaults come from the preference cookies.
2. `ProcessDocumentAdd` validates (`@ErrorStack` stops the page), resolves
   manual authors (`ProcessManualAuthors`), then calls
   `DocumentUtilities.pm::AddDocument` or `UpdateDocument`:
   * `AddDocument` inserts the `Document` row, allocates the alias from
     `NextDocNumber`, and creates revision 1 (or 0 for a reservation).
   * `UpdateDocument` creates the next `DocumentRevision` (or, for
     `updatedb`, rewrites the metadata of the existing version), marks the
     previous one obsolete where appropriate, and copies forward sign-offs.
   * Both insert authors, topics, events, references, cross-references
     (`InsertXRefs`) and the access lists (`InsertSecurity`), make the
     directory, and call `FileUtilities.pm::AddFiles`.
3. `AddFiles` loops over the upload slots: a browser upload goes through
   `ProcessUpload` (name sanity check, write to the version directory); a
   `copy` reuses the previous version's file; a URL would be fetched by
   `DownloadURLs` (disabled, `$Wget` is empty). Each file gets a
   `DocumentFile` row and is handed to the GLIMPSE incremental indexer.
4. `MailNotices` sends Immediate notifications; the browser is redirected to
   `ShowDocument`.

`AddFilesForm`/`AddFiles` add or replace files on an existing revision
(requires `CanModify`); doing so unsigns the revision. `ModifyHome` and
`ReserveHome` are the entry pages for updating and reserving.
`XMLUpload`/`XMLClone` create documents from DocDB XML (from another DocDB
or `XSearch`), reusing the same utilities; `XMLOutput.pm` produces the XML
that `ShowDocument?outformat=xml` and `XSearch` return.

## Viewing and retrieving

`ShowDocument` resolves the revision (explicit `version`, `asof` date, or
the newest version the caller may see via `LastAccess`), checks `CanAccess`,
and renders the document page (`RevisionHTML.pm::PrintRevisionInfo`,
`FileHTML.pm` for the file list with sizes and links, `XRefHTML.pm`,
`SignoffHTML.pm`). Administrators also see the QA-check, update and
add-files buttons. The `mode=qacheck` branch toggles public status (see
review finding C2).

`RetrieveFile` picks a file by `filename`, by `extension`, or the main
file, checks `CanAccess`, and redirects to the file's URL under `/DocDB/`
where Apache serves it after the `RemoteUserHasAccess` check. The
short-URL rewrites (`/T2500123-v2.pdf`, `/T2500123/main`) land here.
`RetrieveArchive` would bundle a version's files into a tar or zip but the
archiver paths are empty in configuration, so it is disabled.

## Deleting and re-securing

`DeleteConfirm` then `DeleteDocument` (administrators only) remove the
document, its revisions and several link tables and delete the files on
disk; some dependent tables are left behind (review L6). `Resecure` is an
administrative tool to rewrite access lists for ranges of documents.

## Cross-references and external DocDBs

`xrefs` entries of the form `T2500123-v2` or `LIGO-T1200001` are stored in
`DocXRef` with an optional external project; `ExternalDocDB` rows map a
project name to another DocDB's URLs so `XRefHTML.pm` can link to it. The
parsing and storage of external project names is review finding H2.
