# Photos Statistics

A macOS app in development for exploring photographic metadata in Apple Photos, including library records whose original images are stored only in iCloud.

The first app milestone is a read-only library overview and availability review. Trip detection, album suggestions, approved PhotoKit edits, detailed statistics and ChatGPT integration come later.

## First version

- Load a library and remember its read-only permission.
- See active photo/video totals, photo date range and missing-location count.
- Open the local-original, remote-reported and uncertain-availability groups.
- Break uncertain availability into specific, mutually exclusive reasons.
- Search photos by original filename or camera, and inspect the evidence for a selected record.
- Refresh a consistent database snapshot without downloading originals.

This version displays metadata records, not image thumbnails. The photo detail panel uses a generic icon. It has no PhotoKit write capability and does not change locations, albums, original files, or database records.

## Run the command-line probe

For the initial metadata proof of concept, no graphical interface or unlocked desktop is needed:

```sh
swift run photos-probe "$HOME/Pictures/Photos Library.photoslibrary"
```

Pass an explicit library path. The command prints the diagnostic report to standard output and returns a nonzero exit status on failure. Use `--help` for usage. It uses the same read-only source connection and consistent snapshot as the graphical probe. Existing macOS privacy restrictions still apply; it does not grant itself additional access.

This establishes whether metadata can be read under the command's existing permissions. It does not establish App Sandbox compatibility. Test the graphical app separately when validating App Store distribution.

## Run the Mac app

Requires Xcode with the macOS 14 or newer SDK. Open `PhotosStatistics.xcodeproj`, choose **PhotosAccessProbe** (the development scheme), then Run. The product is now **Photos Statistics.app**. Its original development bundle identifier is retained so existing read-only bookmarks continue to work. Local builds use ad-hoc signing; distribution signing will need your Apple developer team.

1. Click **Choose Photos Library…**.
2. Select your `.photoslibrary` package. A folder containing `Photos.sqlite` is also accepted for development fixtures.
3. Explore **Overview**, **All photos**, and **Availability review**. Select a table row for its explanation and evidence.
4. The **Diagnostics** view retains the aggregate report; its toolbar copies that report only when clicked.

The app requests App Sandbox plus user-selected **read-only** file access. It has no network entitlement, requests no image data, and does not use PhotoKit to download originals. A read-only security-scoped bookmark remembers your selection. On launch, the app restores that access without displaying a chooser and refreshes the report. If access is stale, choose the library again.

The latest aggregate diagnostic report is written locally to `PhotosStatistics/last-probe-report.txt` under the app's Application Support folder. `last-overview-summary.json` contains aggregate counts and reason totals. No database snapshot, per-photo identifiers, or per-photo metadata values are saved there. Browsable photo records stay in memory for the session. The bookmark is stored separately in the app's preferences. These local files are not uploaded. Relaunch the app after rebuilding to use new logic.

It opens the source using SQLite's read-only mode, creates a consistent temporary snapshot with the SQLite backup API, checks it, and inspects only that snapshot. The temporary copy is deleted at the end of the check. SQLite may need existing WAL/shared-memory sidecars to read a live database with read-only filesystem access; failures are reported without escalating permissions or using `immutable` to ignore journal changes.

The diagnostic report includes the OS version, schema fingerprint, SQLite `user_version`, inventory counts, per-photo metadata coverage and review reason totals. The table-inventory section counts records; the explicitly labelled per-photo section counts active still-photo assets. Successful aggregate reports omit individual photo filenames, coordinates and camera values. SQLite/OS failure messages should still be reviewed before sharing.

## Validation

```sh
swift test --scratch-path .build
xcodebuild -project PhotosStatistics.xcodeproj -scheme PhotosAccessProbe -configuration Debug -derivedDataPath build build
codesign -d --entitlements - "build/Build/Products/Debug/Photos Statistics.app"
```

Tests use synthetic databases and exercise committed WAL data, rejection of source writes, schema changes, invalid files, and missing libraries. These tests do not grant access to or validate your personal library. The manual file-chooser check must run in the signed sandboxed app; passing command-line tests alone does not establish sandbox compatibility.

Initial real-library CLI attempt (27 October 2026): SQLite returned error 23, `authorization denied`, both within and outside Codex's restricted execution environment. No privacy settings were changed. This is a historical result from the CLI's permissions, not the status of the graphical app.

Subsequent graphical checks (27 October 2026): selecting the library through the signed sandboxed app succeeded, as did the per-photo coverage scan and bookmark restoration for the overview. The snapshot passed `quick_check`, and metadata was accessible for photo assets whose managed originals were absent locally. Personal-library counts are kept in local reports rather than committed here.

`project.yml` is the XcodeGen source for the checked-in Xcode project. Regenerate with `xcodegen generate` after changing project configuration.

## Compatibility approach

The probe inventories unknown schemas without interpreting them. One observed schema fingerprint now enables an experimental per-photo adapter with structural and relationship checks; no production adapter is approved yet. See [mapping and coverage definitions](docs/metadata-coverage.md). A schema fingerprint is a structural signal, not a substitute for interpreting Apple's model versions or validating each supported Photos release.

Successful access demonstrates technical feasibility on the tested system; App Store review remains separate. No original image downloads or cloud integration are required for this milestone.

## Next milestones

- Investigate alternative original-resource relationships to reduce uncertain classifications.
- Add trip proposals with adjustable date boundaries, GPS anchors and camera clock-offset handling.
- Compare confirmed trip membership against regular albums and propose additions.
- Add location suggestions with evidence and confidence.
- Add explicit change review, PhotoKit permission and System Photo Library matching before any edits.
- Add detailed photographic statistics and optional ChatGPT integration later.

See [the OpenAI request draft](docs/openai-access-request.md). No request has been submitted. A public repository alone does not grant an open-source licence; the project licence is still to be selected.
