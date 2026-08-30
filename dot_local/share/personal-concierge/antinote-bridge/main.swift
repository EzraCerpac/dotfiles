import AppKit
import CryptoKit
import Foundation
import SQLite3

// The bridge deliberately treats AntiNote's Core Data store as a read-only
// projection.  Core Data owns writes, sync metadata, and persistent history;
// this process only reads a WAL-consistent snapshot and emits official URLs.

private let defaultDatabasePath = NSHomeDirectory() + "/Library/Containers/com.chabomakers.Antinote/Data/Library/Application Support/cd-v1-notes.sqlite"
private let helperVersion = "0.1.0"
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum BridgeError: Error, CustomStringConvertible {
    case usage(String)
    case database(String)
    case notFound(String)
    case invalidIdentifier(String)
    case invalidValue(String)

    var description: String {
        switch self {
        case .usage(let value), .database(let value), .notFound(let value), .invalidIdentifier(let value), .invalidValue(let value):
            return value
        }
    }
}

final class SQLiteStore {
    let path: String
    private var db: OpaquePointer?

    init(path: String) throws {
        self.path = path
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            if handle != nil { sqlite3_close(handle) }
            throw BridgeError.database("Cannot open AntiNote database at \(path): \(message)")
        }
        db = handle
        sqlite3_busy_timeout(handle, 3_000)
        try execute("PRAGMA query_only = ON")
        // A read transaction pins the WAL snapshot for every relation read by
        // one command. It also prevents a concurrent sync from mixing states.
        try execute("BEGIN")
    }

    deinit {
        if let db {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            sqlite3_close(db)
        }
    }

    func execute(_ sql: String) throws {
        guard let db else { throw BridgeError.database("Database is closed") }
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        guard result == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(error)
            throw BridgeError.database(message)
        }
    }

    func query(_ sql: String, bindings: [Binding] = [], row: ([String: Any?]) throws -> Void) throws {
        guard let db else { throw BridgeError.database("Database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw BridgeError.database(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                var values: [String: Any?] = [:]
                let count = sqlite3_column_count(statement)
                for index in 0..<count {
                    guard let name = sqlite3_column_name(statement, index) else { continue }
                    values[String(cString: name)] = columnValue(statement, index: index)
                }
                try row(values)
            } else if result == SQLITE_DONE {
                break
            } else {
                throw BridgeError.database(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    func scalarString(_ sql: String, bindings: [Binding] = []) throws -> String? {
        var value: String?
        try query(sql, bindings: bindings) { row in
            if let candidate = row.values.first ?? nil { value = stringValue(candidate) }
        }
        return value
    }

    func scalarInt(_ sql: String, bindings: [Binding] = []) throws -> Int? {
        var value: Int?
        try query(sql, bindings: bindings) { row in
            if let candidate = row.values.first ?? nil { value = intValue(candidate) }
        }
        return value
    }

    func rawHandle() throws -> OpaquePointer {
        guard let db else { throw BridgeError.database("Database is closed") }
        return db
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
            case .blob(let value):
                result = value.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), sqliteTransient)
                }
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else {
                throw BridgeError.database("SQLite bind failed: \(result)")
            }
        }
    }

    private func columnValue(_ statement: OpaquePointer, index: Int32) -> Any? {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return Int(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return sqlite3_column_double(statement, index)
        case SQLITE_TEXT:
            guard let pointer = sqlite3_column_text(statement, index) else { return nil }
            return String(cString: pointer)
        case SQLITE_BLOB:
            let length = Int(sqlite3_column_bytes(statement, index))
            guard length > 0, let pointer = sqlite3_column_blob(statement, index) else { return Data() }
            return Data(bytes: pointer, count: length)
        default:
            return nil
        }
    }
}

enum Binding {
    case text(String)
    case blob(Data)
    case double(Double)
    case integer(Int)
    case null
}

private func stringValue(_ value: Any?) -> String? {
    switch value {
    case let value as String: return value
    case let value as NSNumber: return value.stringValue
    default: return nil
    }
}

private func intValue(_ value: Any?) -> Int? {
    switch value {
    case let value as Int: return value
    case let value as NSNumber: return value.intValue
    case let value as String: return Int(value)
    default: return nil
    }
}

private func doubleValue(_ value: Any?) -> Double? {
    switch value {
    case let value as Double: return value
    case let value as Int: return Double(value)
    case let value as NSNumber: return value.doubleValue
    case let value as String: return Double(value)
    default: return nil
    }
}

private func dataValue(_ value: Any?) -> Data? { value as? Data }

private func iso8601(_ value: Any?) -> String? {
    guard let seconds = doubleValue(value) else { return nil }
    let date = Date(timeIntervalSinceReferenceDate: seconds)
    return ISO8601DateFormatter.withFractionalSeconds.string(from: date)
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

private func parseDate(_ value: String) -> Date? {
    if let number = Double(value) { return Date(timeIntervalSinceReferenceDate: number) }
    if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: value) { return date }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

private func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

private func uuidString(_ data: Data) -> String {
    guard data.count == 16 else { return hex(data) }
    let bytes = Array(data)
    return String(format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                  bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                  bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
}

private func parseIdentifier(_ value: String) throws -> Data {
    let normalized = value.replacingOccurrences(of: "-", with: "").lowercased()
    guard normalized.count == 32, let data = Data(hexString: normalized), data.count == 16 else {
        throw BridgeError.invalidIdentifier("AntiNote note IDs are 16-byte ZID UUIDs: \(value)")
    }
    return data
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

private func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func sha256(_ value: Data) -> String {
    SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
}

private func scalarString(on database: OpaquePointer, sql: String) throws -> String {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw BridgeError.database(String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw BridgeError.database(String(cString: sqlite3_errmsg(database)))
    }
    guard let value = sqlite3_column_text(statement, 0) else { return "" }
    return String(cString: value)
}

struct Checklist {
    let id: String
    let checked: Bool
    let index: Int
    let hidden: Bool
    let content: String

    func dictionary(includeContent: Bool) -> [String: Any] {
        var value: [String: Any] = ["id": id, "checked": checked, "index": index, "hidden": hidden]
        if includeContent { value["content"] = content }
        return value
    }
}

struct AntiLink {
    let id: String
    let fullURL: String
    let shortenedURL: String?

    var dictionary: [String: Any] {
        var value: [String: Any] = ["id": id, "url": fullURL]
        if let shortenedURL { value["shortenedURL"] = shortenedURL }
        return value
    }
}

struct Attachment {
    let id: String
    let filename: String?
    let fileType: String?
    let fileURL: String?
    let mimeType: String?
    let size: Int?

    var dictionary: [String: Any] {
        var value: [String: Any] = ["id": id]
        if let filename { value["filename"] = filename }
        if let fileType { value["fileType"] = fileType }
        if let fileURL { value["url"] = fileURL }
        if let mimeType { value["mimeType"] = mimeType }
        if let size { value["size"] = size }
        return value
    }
}

struct Note {
    let id: String
    let revision: Int?
    let stackIndex: Int?
    let createdAt: String?
    let deletedAt: String?
    let lastModifiedAt: String?
    let slotted: Bool
    let slotIndex: Int?
    let archived: Bool
    let softDeleted: Bool
    let isPrivate: Bool
    let locked: Bool
    let content: String
    let checklists: [Checklist]
    let links: [AntiLink]
    let attachments: [Attachment]

    var state: String {
        if softDeleted { return "void" }
        if archived { return "archived" }
        if slotted { return "slotted" }
        return "active"
    }

    var contentHash: String { sha256(content) }

    var metadataHash: String {
        // JSON with sorted keys and length-aware encoding avoids delimiter
        // collisions (for example, a URL containing our old separator).
        let metadata: [String: Any] = [
            "archived": archived,
            "attachments": attachments.map(\.dictionary),
            "checklists": checklists.map { $0.dictionary(includeContent: true) },
            "createdAt": createdAt ?? NSNull(),
            "deletedAt": deletedAt ?? NSNull(),
            "id": id,
            "lastModifiedAt": lastModifiedAt ?? NSNull(),
            "links": links.map(\.dictionary),
            "locked": locked,
            "private": isPrivate,
            "revision": revision ?? NSNull(),
            "slotted": slotted,
            "slotIndex": slotIndex ?? NSNull(),
            "softDeleted": softDeleted,
            "stackIndex": stackIndex ?? NSNull(),
            "state": state
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]) else {
            return sha256(id)
        }
        return sha256(data)
    }

    func dictionary(includeContent: Bool = false) -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "revision": revision ?? NSNull(),
            "stackIndex": stackIndex ?? NSNull(),
            "state": state,
            "slotted": slotted,
            "archived": archived,
            "softDeleted": softDeleted,
            "private": isPrivate,
            "locked": locked,
            "hasContent": !content.isEmpty,
            "contentHash": contentHash,
            "metadataHash": metadataHash,
            "checklists": checklists.map { $0.dictionary(includeContent: includeContent) },
            "links": links.map(\.dictionary),
            "attachments": attachments.map(\.dictionary)
        ]
        if slotted, let slotIndex { result["slotIndex"] = slotIndex }
        if let createdAt { result["createdAt"] = createdAt }
        if let deletedAt { result["deletedAt"] = deletedAt }
        if let lastModifiedAt { result["lastModifiedAt"] = lastModifiedAt }
        if includeContent { result["content"] = content }
        return result
    }
}

final class AntiNoteBridge {
    let databasePath: String
    let store: SQLiteStore

    init(databasePath: String) throws {
        self.databasePath = databasePath
        self.store = try SQLiteStore(path: databasePath)
    }

    func schemaFingerprint() throws -> String {
        var schema = ""
        try store.query("SELECT type, name, tbl_name, sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type, name") { row in
            schema += [stringValue(row["type"] ?? nil) ?? "", stringValue(row["name"] ?? nil) ?? "", stringValue(row["tbl_name"] ?? nil) ?? "", stringValue(row["sql"] ?? nil) ?? ""].joined(separator: "\u{1f}") + "\n"
        }
        return sha256(schema)
    }

    func schemaGuard() throws -> [String: Any] {
        let requiredColumns: [String: [String]] = [
            "ZNOTE": ["Z_PK", "Z_OPT", "ZDBINDEX", "ZISSLOTTED", "ZSLOTINDEX", "ZSOFTDELETED", "ZCREATED", "ZDELETEDAT", "ZLASTMODIFIED", "ZCONTENT", "ZID", "ZISARCHIVED", "ZISPRIVATE", "ZISLOCKED"],
            "ZCHECKLISTITEM": ["ZID", "ZCHECKED", "ZINDEX", "ZISHIDDEN", "ZNOTE", "ZCONTENT"],
            "ZANTILINK": ["ZID", "ZNOTE", "ZFULLURL", "ZSHORTENEDURL"],
            "ZATTACHMENT": ["ZID", "ZNOTE", "ZFILESIZE", "ZSORTORDER", "ZFILENAME", "ZFILETYPE", "ZFILEURL", "ZMIMETYPE"]
        ]
        let requiredTypes: [String: [String: String]] = [
            "ZNOTE": ["Z_PK": "INTEGER", "Z_OPT": "INTEGER", "ZDBINDEX": "INTEGER", "ZISSLOTTED": "INTEGER", "ZSLOTINDEX": "INTEGER", "ZSOFTDELETED": "INTEGER", "ZID": "BLOB", "ZISARCHIVED": "INTEGER", "ZISPRIVATE": "INTEGER", "ZISLOCKED": "INTEGER"],
            "ZCHECKLISTITEM": ["ZID": "BLOB", "ZCHECKED": "INTEGER", "ZINDEX": "INTEGER", "ZISHIDDEN": "INTEGER", "ZNOTE": "INTEGER"],
            "ZANTILINK": ["ZID": "BLOB", "ZNOTE": "INTEGER"],
            "ZATTACHMENT": ["ZID": "BLOB", "ZNOTE": "INTEGER", "ZSORTORDER": "INTEGER"]
        ]
        var presentTables = Set<String>()
        try store.query("SELECT name FROM sqlite_master WHERE type = 'table'") { row in
            if let name = stringValue(row["name"] ?? nil) { presentTables.insert(name.uppercased()) }
        }
        var missingTables: [String] = []
        var missingColumns: [[String: String]] = []
        var invalidTypes: [[String: String]] = []
        var invalidPrimaryKeys: [[String: Any]] = []
        var invalidIdentities: [[String: Any]] = []
        var invalidRelations: [[String: Any]] = []
        for (table, columns) in requiredColumns {
            guard presentTables.contains(table) else {
                missingTables.append(table)
                continue
            }
            var presentColumns = Set<String>()
            var declaredTypes: [String: String] = [:]
            var primaryKeys: [String: Int] = [:]
            try store.query("PRAGMA table_info(\"\(table)\")") { row in
                if let name = stringValue(row["name"] ?? nil) {
                    let normalized = name.uppercased()
                    presentColumns.insert(normalized)
                    declaredTypes[normalized] = stringValue(row["type"] ?? nil)?.uppercased() ?? ""
                    primaryKeys[normalized] = intValue(row["pk"] ?? nil) ?? 0
                }
            }
            for column in columns where !presentColumns.contains(column) {
                missingColumns.append(["table": table, "column": column])
            }
            for (column, expected) in requiredTypes[table] ?? [:] where presentColumns.contains(column) {
                let actual = declaredTypes[column] ?? ""
                let matches: Bool
                switch expected {
                case "BLOB": matches = actual.contains("BLOB")
                case "INTEGER": matches = actual == "INTEGER"
                default: matches = !actual.isEmpty
                }
                if !matches { invalidTypes.append(["table": table, "column": column, "expected": expected, "actual": actual]) }
            }
            if table == "ZNOTE", presentColumns.contains("Z_PK"), primaryKeys["Z_PK"] != 1 {
                invalidPrimaryKeys.append(["table": table, "column": "Z_PK", "declaredPrimaryKey": primaryKeys["Z_PK"] ?? 0])
            }
        }
        let identityChecks: [(String, String)] = [
            ("ZNOTE", "note IDs"),
            ("ZCHECKLISTITEM", "checklist IDs"),
            ("ZANTILINK", "link IDs"),
            ("ZATTACHMENT", "attachment IDs")
        ]
        for (table, label) in identityChecks where presentTables.contains(table) {
            let count = try store.scalarInt("SELECT COUNT(*) FROM \(table) WHERE ZID IS NULL OR typeof(ZID) != 'blob' OR length(ZID) != 16") ?? 0
            if count > 0 { invalidIdentities.append(["table": table, "label": label, "invalidRows": count, "requirement": "ZID is a non-null 16-byte BLOB"])
            }
        }
        let relationChecks: [(String, String)] = [("ZCHECKLISTITEM", "checklist items"), ("ZANTILINK", "links"), ("ZATTACHMENT", "attachments")]
        if presentTables.contains("ZNOTE") {
            for (table, label) in relationChecks where presentTables.contains(table) {
                let count = try store.scalarInt("SELECT COUNT(*) FROM \(table) c LEFT JOIN ZNOTE n ON c.ZNOTE = n.Z_PK WHERE c.ZNOTE IS NULL OR n.Z_PK IS NULL") ?? 0
                if count > 0 { invalidRelations.append(["table": table, "label": label, "orphanRows": count, "requirement": "ZNOTE references ZNOTE.Z_PK"]) }
            }
        }
        return [
            "ok": missingTables.isEmpty && missingColumns.isEmpty && invalidTypes.isEmpty && invalidPrimaryKeys.isEmpty && invalidIdentities.isEmpty && invalidRelations.isEmpty,
            "requiredTables": Array(requiredColumns.keys).sorted(),
            "missingTables": missingTables.sorted(),
            "missingColumns": missingColumns,
            "invalidTypes": invalidTypes,
            "invalidPrimaryKeys": invalidPrimaryKeys,
            "invalidIdentities": invalidIdentities,
            "invalidRelations": invalidRelations
        ]
    }

    private func requireSchema() throws {
        let result = try schemaGuard()
        guard (result["ok"] as? Bool) == true else {
            let missingTables = (result["missingTables"] as? [String] ?? []).joined(separator: ", ")
            let missingColumns = (result["missingColumns"] as? [[String: String]] ?? []).map { "\($0["table"] ?? "?").\($0["column"] ?? "?")" }.joined(separator: ", ")
            var details = [String]()
            if !missingTables.isEmpty { details.append("tables: \(missingTables)") }
            if !missingColumns.isEmpty { details.append("columns: \(missingColumns)") }
            if let invalidTypes = result["invalidTypes"] as? [[String: String]], !invalidTypes.isEmpty { details.append("types: \(invalidTypes.map { "\($0["table"] ?? "?").\($0["column"] ?? "?")" })") }
            if let invalidPrimaryKeys = result["invalidPrimaryKeys"] as? [[String: Any]], !invalidPrimaryKeys.isEmpty { details.append("primary keys: \(invalidPrimaryKeys.map { "\($0["table"] ?? "?").\($0["column"] ?? "?")" })") }
            if let invalidIdentities = result["invalidIdentities"] as? [[String: Any]], !invalidIdentities.isEmpty { details.append("identities: \(invalidIdentities.map { $0["table"] as? String ?? "?" })") }
            if let invalidRelations = result["invalidRelations"] as? [[String: Any]], !invalidRelations.isEmpty { details.append("relations: \(invalidRelations.map { $0["table"] as? String ?? "?" })") }
            throw BridgeError.database("AntiNote schema guard failed (\(details.joined(separator: "; ")))" )
        }
    }

    func notes(includeVoid: Bool, includeArchived: Bool, includeContent: Bool, query: String? = nil, since: Date? = nil) throws -> [Note] {
        try requireSchema()
        var whereParts = ["1 = 1"]
        var bindings: [Binding] = []
        if !includeVoid { whereParts.append("n.ZSOFTDELETED = 0") }
        if !includeArchived { whereParts.append("n.ZISARCHIVED = 0") }
        if let query {
            whereParts.append("lower(COALESCE(n.ZCONTENT, '')) LIKE lower(?)")
            bindings.append(.text("%\(query)%"))
        }
        if let since {
            whereParts.append("n.ZLASTMODIFIED >= ?")
            bindings.append(.double(since.timeIntervalSinceReferenceDate))
        }
        let sql = "SELECT n.Z_PK, n.Z_OPT, n.ZDBINDEX, n.ZCREATED, n.ZDELETEDAT, n.ZLASTMODIFIED, n.ZISSLOTTED, n.ZSLOTINDEX, n.ZSOFTDELETED, n.ZISARCHIVED, n.ZISPRIVATE, n.ZISLOCKED, n.ZCONTENT, n.ZID FROM ZNOTE n WHERE \(whereParts.joined(separator: " AND ")) ORDER BY n.ZLASTMODIFIED DESC, n.Z_PK DESC"
        var notes: [Note] = []
        try store.query(sql, bindings: bindings) { row in
            guard let idData = dataValue(row["ZID"] ?? nil) else { return }
            let primaryKey = intValue(row["Z_PK"] ?? nil) ?? 0
            let note = try self.makeNote(row: row, primaryKey: primaryKey, idData: idData)
            notes.append(note)
        }
        return notes
    }

    func note(idData: Data) throws -> Note {
        try requireSchema()
        var result: Note?
        try store.query("SELECT n.Z_PK, n.Z_OPT, n.ZDBINDEX, n.ZCREATED, n.ZDELETEDAT, n.ZLASTMODIFIED, n.ZISSLOTTED, n.ZSLOTINDEX, n.ZSOFTDELETED, n.ZISARCHIVED, n.ZISPRIVATE, n.ZISLOCKED, n.ZCONTENT, n.ZID FROM ZNOTE n WHERE n.ZID = ? LIMIT 1", bindings: [.blob(idData)]) { row in
            guard let actualID = dataValue(row["ZID"] ?? nil) else { return }
            result = try self.makeNote(row: row, primaryKey: intValue(row["Z_PK"] ?? nil) ?? 0, idData: actualID)
        }
        guard let result else { throw BridgeError.notFound("AntiNote note not found: \(uuidString(idData))") }
        return result
    }

    private func makeNote(row: [String: Any?], primaryKey: Int, idData: Data) throws -> Note {
        let checklistSQL = "SELECT ZID, ZCHECKED, ZINDEX, ZISHIDDEN, ZCONTENT FROM ZCHECKLISTITEM WHERE ZNOTE = ? ORDER BY ZINDEX, Z_PK"
        var checklists: [Checklist] = []
        try store.query(checklistSQL, bindings: [.integer(primaryKey)]) { child in
            guard let data = dataValue(child["ZID"] ?? nil) else { return }
            checklists.append(Checklist(id: uuidString(data), checked: (intValue(child["ZCHECKED"] ?? nil) ?? 0) != 0, index: intValue(child["ZINDEX"] ?? nil) ?? 0, hidden: (intValue(child["ZISHIDDEN"] ?? nil) ?? 0) != 0, content: stringValue(child["ZCONTENT"] ?? nil) ?? ""))
        }
        let linkSQL = "SELECT ZID, ZFULLURL, ZSHORTENEDURL FROM ZANTILINK WHERE ZNOTE = ? ORDER BY Z_PK"
        var links: [AntiLink] = []
        try store.query(linkSQL, bindings: [.integer(primaryKey)]) { child in
            guard let data = dataValue(child["ZID"] ?? nil), let url = stringValue(child["ZFULLURL"] ?? nil) else { return }
            links.append(AntiLink(id: uuidString(data), fullURL: url, shortenedURL: stringValue(child["ZSHORTENEDURL"] ?? nil)))
        }
        let attachmentSQL = "SELECT ZID, ZFILESIZE, ZFILENAME, ZFILETYPE, ZFILEURL, ZMIMETYPE FROM ZATTACHMENT WHERE ZNOTE = ? ORDER BY ZSORTORDER, Z_PK"
        var attachments: [Attachment] = []
        try store.query(attachmentSQL, bindings: [.integer(primaryKey)]) { child in
            guard let data = dataValue(child["ZID"] ?? nil) else { return }
            attachments.append(Attachment(id: uuidString(data), filename: stringValue(child["ZFILENAME"] ?? nil), fileType: stringValue(child["ZFILETYPE"] ?? nil), fileURL: stringValue(child["ZFILEURL"] ?? nil), mimeType: stringValue(child["ZMIMETYPE"] ?? nil), size: intValue(child["ZFILESIZE"] ?? nil)))
        }
        return Note(id: uuidString(idData), revision: intValue(row["Z_OPT"] ?? nil), stackIndex: intValue(row["ZDBINDEX"] ?? nil), createdAt: iso8601(row["ZCREATED"] ?? nil), deletedAt: iso8601(row["ZDELETEDAT"] ?? nil), lastModifiedAt: iso8601(row["ZLASTMODIFIED"] ?? nil), slotted: (intValue(row["ZISSLOTTED"] ?? nil) ?? 0) != 0, slotIndex: intValue(row["ZSLOTINDEX"] ?? nil), archived: (intValue(row["ZISARCHIVED"] ?? nil) ?? 0) != 0, softDeleted: (intValue(row["ZSOFTDELETED"] ?? nil) ?? 0) != 0, isPrivate: (intValue(row["ZISPRIVATE"] ?? nil) ?? 0) != 0, locked: (intValue(row["ZISLOCKED"] ?? nil) ?? 0) != 0, content: stringValue(row["ZCONTENT"] ?? nil) ?? "", checklists: checklists, links: links, attachments: attachments)
    }

    func doctor() throws -> [String: Any] {
        let fingerprint = try schemaFingerprint()
        let schema = try schemaGuard()
        var quickCheck = ""
        try store.query("PRAGMA quick_check") { row in quickCheck = stringValue(row.values.first ?? nil) ?? "" }
        guard (schema["ok"] as? Bool) == true else {
            return ["ok": false, "helperVersion": helperVersion, "databasePath": databasePath, "journalMode": try store.scalarString("PRAGMA journal_mode") ?? "unknown", "quickCheck": quickCheck, "schemaFingerprint": fingerprint, "schemaGuard": schema]
        }
        let count = try store.scalarInt("SELECT COUNT(*) FROM ZNOTE") ?? 0
        let active = try store.scalarInt("SELECT COUNT(*) FROM ZNOTE WHERE ZSOFTDELETED = 0 AND ZISARCHIVED = 0") ?? 0
        let slotted = try store.scalarInt("SELECT COUNT(*) FROM ZNOTE WHERE ZISSLOTTED = 1 AND ZSOFTDELETED = 0") ?? 0
        let void = try store.scalarInt("SELECT COUNT(*) FROM ZNOTE WHERE ZSOFTDELETED = 1") ?? 0
        return ["ok": quickCheck == "ok", "helperVersion": helperVersion, "databasePath": databasePath, "journalMode": try store.scalarString("PRAGMA journal_mode") ?? "unknown", "quickCheck": quickCheck, "schemaFingerprint": fingerprint, "schemaGuard": schema, "counts": ["total": count, "active": active, "slotted": slotted, "void": void]]
    }

    func changes(since: Date, includeSettling: Bool, includeArchived: Bool, includeVoid: Bool) throws -> [[String: Any]] {
        let notes = try self.notes(includeVoid: includeVoid, includeArchived: includeArchived, includeContent: false, since: since)
        let cutoff = Date().addingTimeInterval(-300)
        return notes.filter { includeSettling || parseDate($0.lastModifiedAt ?? "") ?? .distantPast <= cutoff }.map { $0.dictionary() }
    }

    func backup(to destination: String) throws -> [String: Any] {
        let destinationURL = URL(fileURLWithPath: destination).standardizedFileURL
        let fileManager = FileManager.default
        let parentURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        if (try? fileManager.destinationOfSymbolicLink(atPath: destinationURL.path)) != nil {
            throw BridgeError.database("Backup destination must not be a symlink: \(destinationURL.path)")
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw BridgeError.database("Backup destination already exists: \(destinationURL.path)")
        }
        let temporaryURL = parentURL.appendingPathComponent("\(destinationURL.lastPathComponent).antinote-\(UUID().uuidString).tmp")
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) { try? fileManager.removeItem(at: temporaryURL) }
        }

        var output: OpaquePointer?
        let openResult = sqlite3_open_v2(temporaryURL.path, &output, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let outputHandle = output else {
            let message = output.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to create backup"
            if output != nil { sqlite3_close(output) }
            throw BridgeError.database("Cannot create temporary backup at \(temporaryURL.path) (SQLite \(openResult)): \(message)")
        }
        var outputOpen = true
        do {
            let source = try store.rawHandle()
            guard let backup = sqlite3_backup_init(outputHandle, "main", source, "main") else {
                throw BridgeError.database("Backup initialization failed: \(String(cString: sqlite3_errmsg(outputHandle)))")
            }
            let result = sqlite3_backup_step(backup, -1)
            let finishResult = sqlite3_backup_finish(backup)
            guard result == SQLITE_DONE, finishResult == SQLITE_OK else {
                throw BridgeError.database("Backup copy failed (step=\(result), finish=\(finishResult)): \(String(cString: sqlite3_errmsg(outputHandle)))")
            }
            let quickCheck = try scalarString(on: outputHandle, sql: "PRAGMA quick_check")
            let integrityCheck = try scalarString(on: outputHandle, sql: "PRAGMA integrity_check")
            guard quickCheck == "ok", integrityCheck == "ok" else {
                throw BridgeError.database("Temporary AntiNote backup verification failed (quick_check=\(quickCheck), integrity_check=\(integrityCheck))")
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            _ = try fileManager.attributesOfItem(atPath: temporaryURL.path)
            let bytes = (try? fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? Int) ?? 0
            guard sqlite3_close(outputHandle) == SQLITE_OK else {
                output = nil
                throw BridgeError.database("Cannot close temporary AntiNote backup")
            }
            outputOpen = false
            output = nil
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            return ["ok": true, "path": destinationURL.path, "permissions": "0600", "quickCheck": quickCheck, "integrityCheck": integrityCheck, "bytes": bytes, "source": databasePath, "schemaFingerprint": try schemaFingerprint()]
        } catch {
            if outputOpen { sqlite3_close(outputHandle) }
            output = nil
            throw error
        }
    }
}

private struct Arguments {
    var values: [String]

    init(_ raw: [String]) {
        var result: [String] = []
        var index = 0
        while index < raw.count {
            if raw[index] == "--json" { index += 1; continue }
            result.append(raw[index])
            index += 1
        }
        values = result
    }

    func option(_ name: String) -> String? {
        guard let index = values.firstIndex(of: name), index + 1 < values.count else { return nil }
        return values[index + 1]
    }

    func has(_ name: String) -> Bool { values.contains(name) }

    func positional(after command: String, index: Int = 0) -> String? {
        let commandIndex = values.firstIndex(of: command) ?? -1
        guard commandIndex >= 0 else { return nil }
        let candidates = values[(commandIndex + 1)...].filter { !$0.hasPrefix("--") && $0 != option("--db") }
        return candidates.dropFirst(index).first
    }
}

private func emit(_ value: Any) throws {
    guard JSONSerialization.isValidJSONObject(value) else { throw BridgeError.invalidValue("Internal result is not valid JSON") }
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

private func usage() -> String {
    """
    Usage: antinote <doctor|backup|list|search|show|changes|create-url|verify> [options] --json

      list [--all|--include-archived|--include-void] [--with-content]
      search <text> [--all|--include-archived|--include-void] [--with-content]
      show <uuid> [--with-content]
      changes --since <ISO-8601> [--include-settling] [--all|--include-archived|--include-void|--exclude-void]
      backup --output <path>
      create-url --content <text> [--operation createNote|appendToCurrent|overwriteCurrent] [--open]
      verify <uuid> [--content-hash <sha256>] [--metadata-hash <sha256>]
    """
}

func main() throws {
    let rawArguments = Array(CommandLine.arguments.dropFirst())
    if rawArguments.contains("--version") || rawArguments.first == "version" {
        try emit(["ok": true, "name": "antinote", "version": helperVersion, "helperVersion": helperVersion])
        return
    }
    let arguments = Arguments(rawArguments)
    guard let command = arguments.values.first, !command.hasPrefix("--") else { throw BridgeError.usage(usage()) }
    let databasePath = arguments.option("--db") ?? ProcessInfo.processInfo.environment["ANTINOTE_DB_PATH"] ?? defaultDatabasePath

    if command == "create-url" {
        guard let content = arguments.option("--content") else { throw BridgeError.usage("create-url requires --content") }
        let operation = arguments.option("--operation") ?? "createNote"
        guard ["createNote", "appendToCurrent", "overwriteCurrent"].contains(operation) else { throw BridgeError.invalidValue("Unsupported AntiNote URL operation: \(operation)") }
        var components = URLComponents()
        components.scheme = "antinote"
        components.host = "x-callback-url"
        components.path = "/\(operation)"
        components.queryItems = [URLQueryItem(name: "content", value: content)]
        guard let url = components.url else { throw BridgeError.invalidValue("Could not construct AntiNote URL") }
        var opened = false
        if arguments.has("--open") { opened = NSWorkspace.shared.open(url) }
        try emit(["ok": !arguments.has("--open") || opened, "url": url.absoluteString, "operation": operation, "opened": opened])
        return
    }

    let bridge = try AntiNoteBridge(databasePath: databasePath)
    switch command {
    case "doctor":
        try emit(bridge.doctor())
    case "backup":
        guard let path = arguments.option("--output") else { throw BridgeError.usage("backup requires --output <path>") }
        try emit(bridge.backup(to: path))
    case "list":
        let includeAll = arguments.has("--all")
        let notes = try bridge.notes(includeVoid: includeAll || arguments.has("--include-void"), includeArchived: includeAll || arguments.has("--include-archived"), includeContent: arguments.has("--with-content"))
        try emit(["ok": true, "count": notes.count, "notes": notes.map { $0.dictionary(includeContent: arguments.has("--with-content")) }])
    case "search":
        guard let query = arguments.positional(after: "search") else { throw BridgeError.usage("search requires text") }
        let includeAll = arguments.has("--all")
        let notes = try bridge.notes(includeVoid: includeAll || arguments.has("--include-void"), includeArchived: includeAll || arguments.has("--include-archived"), includeContent: arguments.has("--with-content"), query: query)
        try emit(["ok": true, "query": query, "count": notes.count, "notes": notes.map { $0.dictionary(includeContent: arguments.has("--with-content")) }])
    case "show":
        guard let value = arguments.positional(after: "show") else { throw BridgeError.usage("show requires a UUID") }
        let note = try bridge.note(idData: parseIdentifier(value))
        try emit(["ok": true, "note": note.dictionary(includeContent: true)])
    case "changes":
        guard let rawSince = arguments.option("--since"), let since = parseDate(rawSince) else { throw BridgeError.usage("changes requires --since <ISO-8601>") }
        let includeAll = arguments.has("--all")
        let records = try bridge.changes(since: since, includeSettling: arguments.has("--include-settling"), includeArchived: includeAll || arguments.has("--include-archived"), includeVoid: !arguments.has("--exclude-void") || includeAll || arguments.has("--include-void"))
        try emit(["ok": true, "since": ISO8601DateFormatter.withFractionalSeconds.string(from: since), "settleSeconds": 300, "count": records.count, "notes": records])
    case "verify":
        guard let value = arguments.positional(after: "verify") else { throw BridgeError.usage("verify requires a UUID") }
        let note = try bridge.note(idData: parseIdentifier(value))
        let expectedContent = arguments.option("--content-hash")
        let expectedMetadata = arguments.option("--metadata-hash")
        let contentMatches = expectedContent.map { $0.lowercased() == note.contentHash } ?? true
        let metadataMatches = expectedMetadata.map { $0.lowercased() == note.metadataHash } ?? true
        try emit(["ok": contentMatches && metadataMatches, "id": note.id, "contentHash": note.contentHash, "metadataHash": note.metadataHash, "contentMatches": contentMatches, "metadataMatches": metadataMatches, "note": note.dictionary()])
    default:
        throw BridgeError.usage(usage())
    }
}

do {
    try main()
} catch {
    let message = (error as? BridgeError)?.description ?? String(describing: error)
    let result: [String: Any] = ["ok": false, "error": message]
    try? emit(result)
    exit(1)
}
