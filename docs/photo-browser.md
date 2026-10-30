# Photos and List views

Shared Album copies are excluded from the main-library dataset, including totals, dates, location counts, browsing and previews. Diagnostics retain separate aggregate counts for troubleshooting. Copies saved into the main library remain included.

The first tab is **Photos**, a lazy adaptive grid of all filtered photo records in newest-first order. Its size slider changes tile size without requesting full-resolution images. The second tab is **List**, the existing table with incremental row display. Search, category filters and the selected photo are shared between tabs. The detail panel shows the same local preview and metadata evidence.

## Permission and source

The metadata database remains read-only. Optional previews use the public PhotoKit framework and the System Photo Library. The app has the Photos Library entitlement and a usage description. It requests authorization only in response to **Enable local previews**; startup and database scans do not open a permission dialog.

Apple's PhotoKit authorization level for this access is named `readWrite`. The preview browser uses it to fetch asset metadata and request image previews. The separate Missing locations screen can request a single location edit through `performChanges` and `PHAssetChangeRequest`, only after explicit review and confirmation. There are no album changes or direct original-file writes. Denied access leaves the list and analysis usable.

## Matching

The reader retains the database asset UUID, current dimensions and library capture date in memory. The preview service enumerates actual PhotoKit identifiers, including Shared Albums and burst members. It recognizes only the observed UUID component of those returned identifiers, never constructs an identifier by appending a guessed suffix, and requires date and dimensions to agree. Duplicate mappings and unsupported identifier formats are rejected.

PhotoKit identifiers are documented as opaque, so recognizing the UUID representation is an experimental compatibility bridge, not an Apple-guaranteed conversion. A selected non-System library may have no matches. Unmatched records stay placeholders; filename similarity is never used to guess. This preview matching is not sufficient authority for future editing features, which need their own library and identity checks.

## Local-only images

Requests use `PHImageManager.requestImage`, `isNetworkAccessAllowed=false`, an image target of 480×480 pixels, opportunistic delivery and fast resizing. An already available lower-quality preview is retained if a later full-quality response is unavailable. Requests are cancelled when cells disappear. A bounded memory cache holds up to 160 images with a 64 MiB cost budget; no preview image files are persisted by our code. PhotoKit may generate a thumbnail from an already-local original. No request enables downloading an original.

Permission revocation is checked before new requests. Cache and mappings are invalidated if authorization is lost. The grid explains when access is disabled, matching is in progress, an asset is unmatched or no preview is available locally. The app does not reinterpret those preview failures as missing originals.

Primary references: [Apple's image request documentation](https://developer.apple.com/documentation/photos/phimagemanager/requestimage(for:targetsize:contentmode:options:resulthandler:)), [network access control](https://developer.apple.com/documentation/photos/phimagerequestoptions/isnetworkaccessallowed), and [opaque local identifiers](https://developer.apple.com/documentation/photos/phobject/localidentifier).
