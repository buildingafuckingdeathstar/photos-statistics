# Photos Statistics

A macOS app in development for exploring photographic metadata in Apple Photos, including library records whose original images are stored only in iCloud.

The app provides a read-only library overview, availability review and guided missing-location review with confirmed individual or batch PhotoKit location edits. Trip detection, album suggestions, detailed statistics and ChatGPT integration come later.

## First version

- Load a library and remember its read-only permission.
- See active photo/video totals, photo date range and missing-location count.
- Open the local-original, remote-reported and uncertain-availability groups.
- Break uncertain availability into specific, mutually exclusive reasons.
- Search photos by original filename or camera, and inspect the evidence for a selected record.
- Switch between **Photos** (a lazy, scrollable thumbnail grid) and **List**, with shared filters and selection.
- Exclude Shared Album copies from main-library statistics, browsing, previews and review. The overview reports excluded photo and video counts; copies saved into the main library remain included.
- Refresh a consistent database snapshot without downloading originals.

Local thumbnails are optional and require a separate Photos permission. The first tab is **Photos**; **List** retains the detailed table. The grid scrolls through all filtered records, requests previews only for visible cells, and has a photo-size slider. It does not download images to fill gaps; unavailable or unmatched previews show placeholders. Browsing and scanning make no changes. The Missing locations review can apply explicitly confirmed location updates through PhotoKit; albums and database files are not written directly.

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
5. In a photo browser's **Photos** tab, click **Enable local previews** if you want thumbnails. macOS asks for Photos access. The app never opens that permission prompt automatically on startup.

The app uses App Sandbox plus user-selected **read-only** file access for the metadata scan. It has no network entitlement. The scan requests no image data. A read-only security-scoped bookmark remembers your selection; on launch, the app restores it without displaying a chooser and refreshes the report. If access is stale, choose the library again.

Previews use the public PhotoKit image manager with `isNetworkAccessAllowed=false` and a small target size. macOS requires the Photos Library entitlement and Photos authorization; the supported access level is named `readWrite`, although this build implements no writes. See [the photo browser design](docs/photo-browser.md) for matching, privacy and preview limitations.

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

### Missing-location review

Open **Missing locations** to split main-library photos without valid coordinates into **No nearby references** and **With nearby references**. Choose a 15-minute, one-hour (default), or three-hour window. The nearest located photo before and after each target provides evidence; no location is inferred automatically. References more than 1 km apart are flagged. Missing dates remain in the first category. Camera clock errors, travel and unrelated simultaneous photos can produce misleading references.

Review the target and nearby located photos side by side, with their time differences and an Apple Maps preview of the highlighted reference location. The nearest reference is highlighted initially; select another reference to change the proposal. OK / NOK controls stay visible beneath the review. The map expands with the available window space, offers native + / − controls, and uses wheel scrolling to zoom while dragging pans. **NOK — leave unchanged** leaves Photos unchanged, with skips kept only for the current review session. **OK — use this location…** opens a second confirmation showing both photos. **Apply location to this photo** requests one location edit through public PhotoKit, which may sync to iCloud. SQLite and library files remain read-only. Previews have downloads disabled; map tiles may use Apple's map service.

Applying requires full Photos permission, locally available previews, unique validated main-library PhotoKit matches, fresh asset checks, no existing target location, an unchanged reference location and metadata-edit capability. It uses actual PhotoKit identifiers, never constructed identifiers. The UUID/date/dimensions bridge remains experimental and deliberately rejects unsupported or ambiguous matches. The user confirms the displayed photos before each edit. Batch edits require a separate confirmation for up to 30 selected photos; no automatic changes are performed. Refresh after applying to update overview counts. Real-library edits require manual verification; automated tests do not modify a user's library.

### Grouped location review

**Missing locations → Review groups** is the default. **Group photos within** sets the maximum group duration (15 minutes, 30 minutes, one hour or three hours), measured from the first photo; groups contain at most 30 photos. **Find references within** independently controls how far before/after each photo to search for located evidence. Widening reference search can leave groups unchanged when the nearest references were already available. Both settings are remembered. **Clear manual splits** allows previously split photos to regroup. A changed reference pair splits the group, so a located photo between missing-location photos creates a boundary. Undated photos remain singletons. Queues distinguish matching references (within 1 km), one-sided references, conflicting references and no references. Matching means reviewable evidence, not a guaranteed common location.

Use the thumbnail checkboxes to deselect exceptions, click a target preview to enlarge it, and select the located reference whose coordinates should be copied. Right-click a reference to enlarge it. The map fills the reference panel and retains wheel zoom, drag panning and + / − controls. **Split into individual photos** breaks a group into separate reviews. **Apply to selected photos…** opens a confirmation grid and count. Every target and the source must pass fresh PhotoKit identity, permission, preview and metadata checks before one `performChanges` transaction is submitted. Any preflight failure stops the entire batch. No automatic edits are made. Deselected photos remain available for later review.

Sessions stop after ten group reviews; **Stop for now / Resume review** allows an earlier pause. **Skip group** leaves Photos unchanged and removes those photos from the regular queue. Use **Skipped → Return group to review** to revisit them. Skips, deselections, splits, the last group/queue, paused state and session counters are saved in this app's local preferences, scoped by a hash of the selected database path. This progress includes photo identity/capture keys but no image files or GPS values; it is separate from aggregate diagnostics and is not uploaded. The reference-window preference is also remembered. Moving a library to a different path starts separate progress. Successful updates are hidden across both review modes until the next metadata scan; subsequent scans use actual library locations. Refresh to update overview counts.
