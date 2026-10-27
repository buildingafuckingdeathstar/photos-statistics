import Foundation

enum PhotoCoverage {
    // Observed on the user's macOS 27.0.1 library. Still an experimental adapter.
    static let observedFingerprint = "5dc18957fa228399796128db14dcf81ec182518618678ddeab2c7db3f4fc9cd1"

    enum Presence { case present, absent, unknown, unsupportedPath, inaccessible }

    static func presence(library: URL, directory: String?, filename: String?) -> Presence {
        guard let directory, let filename, !filename.isEmpty,
              !directory.hasPrefix("/"), !filename.contains("/"),
              !directory.split(separator: "/").contains(".."), filename != ".." else { return .unsupportedPath }
        let root = library.appendingPathComponent("originals").standardizedFileURL
        let candidate = root.appendingPathComponent(directory).appendingPathComponent(filename).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"),
              candidate.resolvingSymlinksInPath().path == candidate.path else { return .unsupportedPath }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: candidate.path)
            return attributes[.type] as? FileAttributeType == .typeRegular ? .present : .inaccessible
        } catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return .absent }
            return .inaccessible
        }
    }

    static func analyze(db: Database, schema: [String: [String]], library: URL,
                        checkPresence: ((String?, String?) -> Presence)? = nil) throws -> [String] {
        try inspect(db: db, schema: schema, library: library, checkPresence: checkPresence).lines
    }

    struct Result {
        let lines: [String]
        let overview: LibraryOverview?
    }

    static func classify(presence: Presence, fingerprint: String?, resourceCount: String?,
                         localCount: String?, localMin: String?, localMax: String?,
                         remoteCount: String?, remoteMin: String?, remoteMax: String?) -> (OriginalAvailability, ReviewReason?) {
        if presence == .unsupportedPath { return (.review, .unsupportedPath) }
        if presence == .unknown || presence == .inaccessible { return (.review, .inaccessibleFile) }
        guard let fingerprint, !fingerprint.isEmpty else { return (.review, .missingFingerprint) }
        guard let resourceCount, Int(resourceCount).map({ $0 > 0 }) == true else { return (.review, .noMatchingResource) }
        guard resourceCount == localCount, localMin != nil, localMax != nil else { return (.review, .incompleteAvailability) }
        guard localMin == localMax else { return (.review, .conflictingResources) }
        if localMin == "1" { return presence == .present ? (.local, nil) : (.review, .fileAbsentButReportedLocal) }
        guard localMin == "-1" else { return (.review, .unrecognizedState) }
        if presence == .present { return (.review, .filePresentButReportedAbsent) }
        guard resourceCount == remoteCount, remoteMin != nil, remoteMax != nil else { return (.review, .incompleteAvailability) }
        guard remoteMin == remoteMax else { return (.review, .conflictingResources) }
        guard remoteMin == "1" else { return (.review, .remoteNotConfirmed) }
        return (.remote, nil)
    }

    static func inspect(db: Database, schema: [String: [String]], library: URL,
                        checkPresence: ((String?, String?) -> Presence)? = nil,
                        progress: @Sendable (String) -> Void = { _ in }) throws -> Result {
        let required: [String: [String]] = [
            "ZASSET": ["Z_PK", "ZKIND", "ZTRASHEDSTATE", "ZDIRECTORY", "ZFILENAME"],
            "ZEXTENDEDATTRIBUTES": ["ZASSET"],
            "ZADDITIONALASSETATTRIBUTES": ["ZASSET"],
            "ZINTERNALRESOURCE": ["ZASSET", "ZFINGERPRINT", "ZLOCALAVAILABILITY", "ZREMOTEAVAILABILITY"]
        ]
        for (table, columns) in required {
            guard let available = schema[table], columns.allSatisfy(available.contains) else {
                return Result(lines: ["Per-photo analysis unavailable: required columns missing in \(table)."], overview: nil)
            }
        }
        let additional = schema["ZADDITIONALASSETATTRIBUTES"]!
        guard let hashColumn = ["ZORIGINALSTABLEHASH", "ZMASTERFINGERPRINT"].first(where: additional.contains) else {
            return Result(lines: ["Per-photo analysis unavailable: no recognized original fingerprint column."], overview: nil)
        }
        // Do not multiply assets when a database has ambiguous metadata relationships.
        for table in ["ZEXTENDEDATTRIBUTES", "ZADDITIONALASSETATTRIBUTES"] {
            let duplicates = try db.rows("""
                SELECT COUNT(*) FROM (
                  SELECT e.ZASSET FROM \(table) e JOIN ZASSET a ON a.Z_PK=e.ZASSET
                  WHERE a.ZKIND=0 AND a.ZTRASHEDSTATE=0
                  GROUP BY e.ZASSET HAVING COUNT(*)>1
                )
                """)
            guard duplicates.first?.first == "0" else {
                return Result(lines: ["Per-photo analysis stopped: duplicate active-photo relationships in \(table)."], overview: nil)
            }
        }
        struct Metric {
            let label: String
            let expression: String
        }
        func has(_ table: String, _ column: String) -> Bool { schema[table]?.contains(column) == true }
        func positive(_ alias: String, _ table: String, _ column: String) -> String {
            has(table, column) ? "\(alias).\(column)>0" : "0"
        }
        func text(_ column: String) -> String {
            has("ZEXTENDEDATTRIBUTES", column) ? "length(trim(e.\(column)))>0" : "0"
        }
        var metrics = [
            Metric(label: "Camera make", expression: text("ZCAMERAMAKE")),
            Metric(label: "Camera model", expression: text("ZCAMERAMODEL")),
            Metric(label: "Lens model", expression: text("ZLENSMODEL"))
        ]
        for (label, column) in [("Aperture", "ZAPERTURE"), ("Shutter speed", "ZSHUTTERSPEED"),
                                ("Focal length", "ZFOCALLENGTH"), ("ISO", "ZISO")] {
            metrics.append(Metric(label: label, expression: positive("e", "ZEXTENDEDATTRIBUTES", column)))
        }
        let dimensions = positive("a", "ZASSET", "ZWIDTH") + " AND " + positive("a", "ZASSET", "ZHEIGHT")
        let originals = positive("d", "ZADDITIONALASSETATTRIBUTES", "ZORIGINALWIDTH") + " AND " + positive("d", "ZADDITIONALASSETATTRIBUTES", "ZORIGINALHEIGHT")
        metrics += [Metric(label: "Current dimensions / derived megapixels", expression: dimensions),
                    Metric(label: "Original dimensions / derived megapixels", expression: originals)]
        if has("ZASSET", "ZLATITUDE"), has("ZASSET", "ZLONGITUDE") {
            metrics.append(Metric(label: "Valid location coordinates", expression: "a.ZLATITUDE BETWEEN -90 AND 90 AND a.ZLONGITUDE BETWEEN -180 AND 180"))
        }
        if has("ZASSET", "ZDATECREATED") {
            metrics.append(Metric(label: "Library capture date", expression: "a.ZDATECREATED IS NOT NULL"))
        }
        let metricSQL = metrics.map { "CASE WHEN \($0.expression) THEN 1 ELSE 0 END" }.joined(separator: ",")
        func optional(_ alias: String, _ table: String, _ column: String) -> String {
            has(table, column) ? "\(alias).\(column)" : "NULL"
        }
        let dateSQL = optional("a", "ZASSET", "ZDATECREATED")
        let cameraSQL = optional("e", "ZEXTENDEDATTRIBUTES", "ZCAMERAMODEL")
        let originalNameSQL = optional("d", "ZADDITIONALASSETATTRIBUTES", "ZORIGINALFILENAME")
        progress("Matching photos to their original resources…")
        // Aggregate all matches per original fingerprint so RAW/live-photo/derivative rows
        // cannot multiply photos or let a local preview stand in for an original.
        let rows = try db.rows("""
            WITH resources AS (
              SELECT ZASSET, ZFINGERPRINT, COUNT(*) n,
                     COUNT(ZLOCALAVAILABILITY) local_n, MIN(ZLOCALAVAILABILITY) local_min,
                     MAX(ZLOCALAVAILABILITY) local_max,
                     COUNT(ZREMOTEAVAILABILITY) remote_n, MIN(ZREMOTEAVAILABILITY) remote_min,
                     MAX(ZREMOTEAVAILABILITY) remote_max
              FROM ZINTERNALRESOURCE GROUP BY ZASSET, ZFINGERPRINT
            )
            SELECT a.ZDIRECTORY, a.ZFILENAME, r.n, r.local_n, r.local_min, r.local_max,
                   r.remote_n, r.remote_min, r.remote_max, e.ZASSET, \(metricSQL),
                   a.Z_PK, \(dateSQL), \(cameraSQL), hex(d.\(hashColumn)), \(originalNameSQL)
            FROM ZASSET a
            LEFT JOIN ZEXTENDEDATTRIBUTES e ON e.ZASSET=a.Z_PK
            LEFT JOIN ZADDITIONALASSETATTRIBUTES d ON d.ZASSET=a.Z_PK
            LEFT JOIN resources r ON r.ZASSET=a.Z_PK AND r.ZFINGERPRINT=d.\(hashColumn)
            WHERE a.ZKIND=0 AND a.ZTRASHEDSTATE=0
            """)
        var totals = [0, 0, 0]
        var counts = Array(repeating: Array(repeating: 0, count: metrics.count), count: 3)
        var withoutExif = 0
        var photos: [PhotoRecord] = []
        photos.reserveCapacity(rows.count)
        let locationIndex = metrics.firstIndex { $0.label == "Valid location coordinates" }
        for (rowIndex, row) in rows.enumerated() {
            if rowIndex % 2000 == 0 { progress("Checking originals: \(rowIndex.formatted()) of \(rows.count.formatted()) photos…") }
            let found = checkPresence?(row[0], row[1]) ?? presence(library: library, directory: row[0], filename: row[1])
            let offset = 10 + metrics.count
            let (status, reason) = classify(presence: found, fingerprint: row[offset + 3], resourceCount: row[2],
                                            localCount: row[3], localMin: row[4], localMax: row[5],
                                            remoteCount: row[6], remoteMin: row[7], remoteMax: row[8])
            let bucket = status == .local ? 0 : status == .remote ? 1 : 2
            let date = row[offset + 1].flatMap(Double.init).flatMap { $0.isFinite ? Date(timeIntervalSinceReferenceDate: $0) : nil }
            let camera = row[offset + 2]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fileStatus = switch found {
            case .present: "Present"
            case .absent: "Not found"
            case .unsupportedPath: "Alternative or unsupported path"
            case .unknown, .inaccessible: "Could not determine"
            }
            let evidence = "Managed file: \(fileStatus)\nMatching original resources: \(row[2] ?? "0")\nLocal availability range: \(row[4] ?? "unknown") to \(row[5] ?? "unknown")\nRemote availability range: \(row[7] ?? "unknown") to \(row[8] ?? "unknown")"
            let originalName = row[offset + 4]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = originalName?.isEmpty == false ? originalName! : (row[1] ?? "Unnamed photo")
            photos.append(PhotoRecord(id: row[offset] ?? "row-\(rowIndex)", filename: name,
                                      captureDate: date, camera: camera?.isEmpty == false ? camera : nil,
                                      hasLocation: locationIndex.map { row[10 + $0] == "1" } ?? false,
                                      availability: status, reason: reason, evidence: evidence))
            totals[bucket] += 1
            if row[9] == nil { withoutExif += 1 }
            for index in metrics.indices where row[10 + index] == "1" { counts[bucket][index] += 1 }
        }
        let labels = ["Original present (DB and file agree)",
                      "Original absent; DB reports remote available", "Unknown or conflicting availability"]
        var output = ["", "PER-PHOTO METADATA COVERAGE — experimental adapter",
                      "Scope: active still-photo asset rows (ZKIND=0, ZTRASHEDSTATE=0); hidden and burst members included.",
                      "Videos excluded; Live Photos and RAW+JPEG pairs count as their owning still-photo asset.",
                      "Managed primary original only; this does not audit every RAW/Live Photo companion.",
                      "Primary original resource matched by asset and \(hashColumn).",
                      "Photo assets: \(rows.count); without an extended-metadata record: \(withoutExif).",
                      "Availability is database-reported and cross-checked with file attributes; no image bytes read.",
                      "Only local=1 and remote=1/nonlocal=-1 are interpreted; other or conflicting states stay unknown.",
                      "Remote availability is a local database claim, not a live check against iCloud."]
        for bucket in 0..<3 {
            output += ["", "\(labels[bucket]): \(totals[bucket]) photos"]
            for index in metrics.indices {
                let expression = metrics[index].expression
                if expression == "0" || expression.hasPrefix("0 AND") || expression.hasSuffix("AND 0") {
                    output.append("  \(metrics[index].label): unavailable in this schema")
                    continue
                }
                let count = counts[bucket][index]
                let percentage = totals[bucket] == 0 ? "n/a" : String(format: "%.1f%%", 100 * Double(count) / Double(totals[bucket]))
                output.append("  \(metrics[index].label): \(count)/\(totals[bucket]) (\(percentage))")
            }
        }
        let videoCount = try db.rows("SELECT COUNT(*) FROM ZASSET WHERE ZKIND=1 AND ZTRASHEDSTATE=0").first?.first.flatMap { $0 }.flatMap(Int.init) ?? 0
        photos.sort { ($0.captureDate ?? .distantPast) > ($1.captureDate ?? .distantPast) }
        let overview = LibraryOverview(photos: photos, videoCount: videoCount, scanDate: Date(), fingerprint: observedFingerprint)
        output += ["", "REVIEW REASONS (mutually exclusive; not a damage diagnosis)"]
        for reason in ReviewReason.allCases { output.append("  \(reason.title): \(overview.count(reason))") }
        return Result(lines: output, overview: overview)
    }
}
