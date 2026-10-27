import Foundation

enum ReferenceInvestigation {
    static func report(db: Database, schema: [String: [String]], hashColumn: String) throws -> [String] {
        let quote = LibraryProbe.quote
        let missing = "(d.\(quote(hashColumn)) IS NULL OR length(d.\(quote(hashColumn)))=0)"
        let joins = "FROM ZASSET a LEFT JOIN ZADDITIONALASSETATTRIBUTES d ON d.ZASSET=a.Z_PK"
        let scope = "a.ZKIND=0 AND a.ZTRASHEDSTATE=0 AND \(missing)"
        var lines = ["", "ALTERNATIVE ORIGINAL REFERENCES — aggregate investigation",
                     "Scope: active photo assets with an empty primary original reference."]
        for table in ["ZASSET", "ZADDITIONALASSETATTRIBUTES", "ZINTERNALRESOURCE", "ZCLOUDMASTER"] {
            let columns = (schema[table] ?? []).filter {
                $0.contains("FINGERPRINT") || $0.contains("HASH") || $0.contains("RESOURCE")
                || $0.contains("MASTER") || $0.contains("SHARE") || $0.contains("SCOPE")
            }
            lines.append("\(table) reference columns: \(columns.sorted().joined(separator: ", "))")
        }
        for (table, alias) in [("ZADDITIONALASSETATTRIBUTES", "d"), ("ZASSET", "a")] {
            let columns = (schema[table] ?? []).filter {
                ($0.contains("FINGERPRINT") || $0.contains("HASH")) && $0 != hashColumn
            }
            for column in columns {
                let count = try db.rows("SELECT COUNT(*) \(joins) WHERE \(scope) AND \(alias).\(quote(column)) IS NOT NULL AND length(\(alias).\(quote(column)))>0").first?.first ?? nil
                lines.append("Nonempty alternate \(table).\(column): \(count ?? "unknown") photos")
            }
        }
        for column in ["ZCOLLECTIONSHARE", "ZLIBRARYSCOPE", "ZCLOUDASSETGUID", "ZMASTER"] where schema["ZASSET"]?.contains(column) == true {
            let count = try db.rows("SELECT COUNT(*) \(joins) WHERE \(scope) AND a.\(quote(column)) IS NOT NULL AND a.\(quote(column)) != 0 AND length(a.\(quote(column)))>0").first?.first ?? nil
            lines.append("Photos with \(column): \(count ?? "unknown")")
        }
        let profileColumns = ["ZDATASTORESUBTYPE", "ZRESOURCETYPE", "ZLOCALAVAILABILITY", "ZREMOTEAVAILABILITY"]
            .filter { schema["ZINTERNALRESOURCE"]?.contains($0) == true }
        if !profileColumns.isEmpty {
            let fields = profileColumns.map { "r.\(quote($0))" }.joined(separator: ",")
            let rows = try db.rows("SELECT \(fields),COUNT(*),COUNT(DISTINCT a.Z_PK) \(joins) JOIN ZINTERNALRESOURCE r ON r.ZASSET=a.Z_PK WHERE \(scope) GROUP BY \(fields) ORDER BY COUNT(DISTINCT a.Z_PK) DESC LIMIT 100")
            lines += ["Resource profile: \(profileColumns.joined(separator: ", ")), resource rows, distinct photos",
                      "A photo may occur in several resource profiles; do not add these photo counts."]
            for row in rows { lines.append("  " + row.map { $0 ?? "NULL" }.joined(separator: ", ")) }
            let unmatched = try db.rows("SELECT COUNT(*) \(joins) WHERE \(scope) AND NOT EXISTS (SELECT 1 FROM ZINTERNALRESOURCE r WHERE r.ZASSET=a.Z_PK)").first?.first ?? nil
            lines.append("Photos with no directly linked internal resources: \(unmatched ?? "unknown")")
        }
        return lines
    }
}
