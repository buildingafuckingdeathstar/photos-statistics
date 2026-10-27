# Experimental per-photo coverage

This adapter is gated to the structural fingerprint observed during the successful macOS 27.0.1 UI check. Other schemas still receive the basic inventory, without guessed per-photo results. Synthetic tests exercise the adapter directly with an explicit fixture schema.

## Counting scope

- One `ZASSET` row where `ZKIND=0` and `ZTRASHEDSTATE=0` is one photo asset.
- Hidden photos and burst members are included. Videos and deleted items are excluded.
- Camera metadata comes from `ZEXTENDEDATTRIBUTES.ZASSET = ZASSET.Z_PK`, not matching primary-key numbers across unrelated tables.
- `ZADDITIONALASSETATTRIBUTES.ZASSET` supplies original dimensions and the original fingerprint.
- Duplicate extended/additional relationships for active photos stop analysis instead of multiplying counts.
- Photos without extended metadata remain in denominators.

## Original availability

Original resource rows are matched by both asset ID and `ZORIGINALSTABLEHASH` (or the older `ZMASTERFINGERPRINT`) against `ZINTERNALRESOURCE.ZFINGERPRINT`. Multiple original-resource matches are aggregated and must agree; previews with other fingerprints cannot make an original appear local.

The adapter cross-checks reported availability with attributes at the managed path `originals/<ZDIRECTORY>/<ZFILENAME>`. It reads attributes only, never image data. Absolute/referenced paths, traversal, symlinks, access errors and ambiguous resource states remain unknown.

- **Present:** all matched original resources report local availability `1` and the managed file exists.
- **Absent, remote reported available:** all matched original resources report local availability `-1`, remote availability `1`, and the managed file is absent.
- **Unknown/conflicting:** every other combination, including nulls, unrecognized state codes, file/database disagreements, and unrecognized original paths.

The remote state is a local database assertion, not verification against iCloud. File existence alone does not prove file data is resident, so the local group also requires the database's local-availability flag. These classifications audit the managed primary original only, not every RAW or Live Photo companion resource.

## Field coverage

Text fields must be nonblank. Aperture, exposure time, focal length, ISO and dimensions must be positive. Location requires latitude in [-90,90] and longitude in [-180,180], rejecting the out-of-range latitude sentinel while retaining a legitimate (0,0). Library date requires a non-NULL value. Megapixels are derivable only when both dimensions are available; original and current dimensions are separate.

Each bucket reports its own numerator, denominator and percentage. Empty buckets use `n/a`. Schema-unavailable fields are distinguished from absent values. This measures availability of usable database fields, not equality with original EXIF tags.

## Sources and limitations

The relationship and fingerprint approach is informed by the primary [OSXPhotos EXIF reader](https://github.com/RhetTbull/osxphotos/blob/main/osxphotos/photosdb/_photosdb_process_exif.py), [resource-availability reader](https://github.com/RhetTbull/osxphotos/blob/main/osxphotos/photosdb/photosdb.py), and [version-specific field mappings](https://github.com/RhetTbull/osxphotos/blob/main/osxphotos/_constants.py). The [original path implementation](https://github.com/RhetTbull/osxphotos/blob/main/osxphotos/photoinfo.py) also documents alternative storage layouts that this initial managed-path check leaves unknown.

Apple's database is undocumented. Runtime relationship checks and conservative unknowns limit misclassification but do not establish production compatibility. Real-library scans have now validated per-photo metadata coverage and restored read-only bookmark access on the tested Mac. Aggregate results remain local rather than being committed to this repository.

## Availability review

The overview and review browser use the same structured photo records as the coverage report. Each uncertain photo gets one primary reason. Path/access problems take precedence, followed by an absent original reference, unmatched resources, incomplete or conflicting availability, unrecognized states, file/database disagreement, and unconfirmed remote availability. This precedence makes totals mutually exclusive; it does not mean a photo has only one possible underlying issue.

The reference test is based on the selected original fingerprint column. A missing reference does not imply the original was deleted. Alternate paths, legacy fingerprints and resource relationships are future investigation areas, not grounds for changing Photos' database.

The browser keeps names, dates, camera models and evidence in process memory. It does not persist a per-photo index yet. Only counts and reason totals are saved for diagnostics. Image thumbnails, trip grouping and any PhotoKit edits are separate later milestones.
