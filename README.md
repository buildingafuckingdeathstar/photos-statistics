# Photos Statistics

A macOS app in development for exploring photographic metadata in Apple Photos, including library records whose original images are stored only in iCloud.

The intended product combines local statistical analysis, interactive charts, saved queries and optional natural-language questions. The first milestone is a small **Photos Access Probe**, not the finished statistics app.

## Run the access prototype

Requires Xcode with the macOS 14 or newer SDK. Open `PhotosStatistics.xcodeproj`, choose **PhotosAccessProbe**, then Run. Local builds use ad-hoc signing; distribution signing will need your Apple developer team.

1. Click **Choose Photos Library…**.
2. Select your `.photoslibrary` package. A folder containing `Photos.sqlite` is also accepted for development fixtures.
3. Review the access, snapshot and metadata-column report. **Copy Report** copies the diagnostic summary only when clicked.

The app requests App Sandbox plus user-selected **read-only** file access. It has no network entitlement, requests no image data, and does not use PhotoKit to download originals. Library access is granted afresh each run; persistent bookmarks come later.

It opens the source using SQLite's read-only mode, creates a consistent temporary snapshot with the SQLite backup API, checks it, and inspects only that snapshot. The temporary copy is deleted at the end of the check. SQLite may need existing WAL/shared-memory sidecars to read a live database with read-only filesystem access; failures are reported without escalating permissions or using `immutable` to ignore journal changes.

The diagnostic report includes the OS version, schema fingerprint, SQLite `user_version`, and non-NULL counts for candidate metadata columns. It does not include filenames of photos, coordinates, camera values or image content. Counts describe database records, **not photo counts or metadata coverage**. Original paths are not included in successful reports; SQLite/OS failure messages should still be reviewed before sharing.

## Validation

```sh
swift test --scratch-path .build
xcodebuild -project PhotosStatistics.xcodeproj -scheme PhotosAccessProbe -configuration Debug -derivedDataPath build build
codesign -d --entitlements :- build/Build/Products/Debug/PhotosAccessProbe.app
```

Tests use synthetic databases and exercise committed WAL data, rejection of source writes, schema changes, invalid files, and missing libraries. These tests do not grant access to or validate your personal library. The manual file-chooser check must run in the signed sandboxed app; passing command-line tests alone does not establish sandbox compatibility.

`project.yml` is the XcodeGen source for the checked-in Xcode project. Regenerate with `xcodegen generate` after changing project configuration.

## Compatibility approach

The probe inventories unknown schemas without interpreting them. No production schema adapter is approved yet. The importer will eventually use an explicit compatibility registry, original/current metadata distinctions, and per-field missing-data coverage. A schema fingerprint is a structural signal, not a substitute for interpreting Apple's model versions or validating each supported Photos release.

Successful access demonstrates technical feasibility on the tested system; App Store review remains separate. No original image downloads or cloud integration are required for this milestone.

## Next milestones

- Validate read-only package access against a real optimized Photos library.
- Add a verified schema adapter and measure per-photo metadata coverage.
- Build the local index, analysis engine, charts and drill-down.
- Add optional conversational queries using validated structured analysis requests.
- Confirm OpenAI eligibility for ChatGPT plan usage in a paid distribution before shipping that integration.

See [the OpenAI request draft](docs/openai-access-request.md). No request has been submitted. A public repository alone does not grant an open-source licence; the project licence is still to be selected.
