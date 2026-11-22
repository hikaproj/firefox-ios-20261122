// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import SQLite3
import os.lock

public struct KnowledgeResult: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let url: String
    public let snippet: String
    public let timestamp: Date

    public init(id: UUID = UUID(), title: String, url: String, snippet: String, timestamp: Date) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
        self.timestamp = timestamp
    }
}

public final class OfflineKnowledgeDBEngine: @unchecked Sendable {
    public static let shared = OfflineKnowledgeDBEngine()

    private var lock = os_unfair_lock()
    private var db: OpaquePointer?
    private let dbPath: String
    private let maxEntries: Int = 1000

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = docs.appendingPathComponent("godmode_knowledge.sqlite")
        self.dbPath = fileURL.path
        openDatabase()
        createTable()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            db = nil
        }
    }

    private func createTable() {
        guard let db = db else { return }
        let sql = """
        CREATE VIRTUAL TABLE IF NOT EXISTS page_knowledge_fts USING fts5(
            title,
            url,
            content,
            timestamp
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    public func indexPage(title: String, url: String, content: String) {
        guard !url.isEmpty, !content.isEmpty else { return }
        let cleanContent = String(content.prefix(32000))
        let now = String(Date().timeIntervalSince1970)

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard let db = db else { return }

        let deleteSQL = "DELETE FROM page_knowledge_fts WHERE url = ?;"
        var deleteStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStmt, 1, (url as NSString).utf8String, -1, nil)
            sqlite3_step(deleteStmt)
        }
        sqlite3_finalize(deleteStmt)

        let insertSQL = "INSERT INTO page_knowledge_fts (title, url, content, timestamp) VALUES (?, ?, ?, ?);"
        var insertStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStmt, 1, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStmt, 2, (url as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStmt, 3, (cleanContent as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStmt, 4, (now as NSString).utf8String, -1, nil)
            sqlite3_step(insertStmt)
        }
        sqlite3_finalize(insertStmt)

        pruneOldRecordsIfNeeded()
    }

    public func search(query: String) -> [KnowledgeResult] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return [] }

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard let db = db else { return [] }

        let sql = "SELECT title, url, snippet(page_knowledge_fts, 2, '<b>', '</b>', '...', 20), timestamp FROM page_knowledge_fts WHERE page_knowledge_fts MATCH ? ORDER BY rank LIMIT 50;"
        var stmt: OpaquePointer?
        var results: [KnowledgeResult] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let ftsQuery = cleanQuery.replacingOccurrences(of: "\"", with: "")
            let matchText = "\"\(ftsQuery)\""
            sqlite3_bind_text(stmt, 1, (matchText as NSString).utf8String, -1, nil)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let title = String(cString: sqlite3_column_text(stmt, 0))
                let url = String(cString: sqlite3_column_text(stmt, 1))
                let snippet = String(cString: sqlite3_column_text(stmt, 2))
                let timeStr = String(cString: sqlite3_column_text(stmt, 3))
                let timestamp = Date(timeIntervalSince1970: Double(timeStr) ?? 0)

                results.append(KnowledgeResult(title: title, url: url, snippet: snippet, timestamp: timestamp))
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    public func clearDatabase() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard let db = db else { return }
        sqlite3_exec(db, "DELETE FROM page_knowledge_fts;", nil, nil, nil)
    }

    private func pruneOldRecordsIfNeeded() {
        guard let db = db else { return }
        let countSQL = "SELECT count(*) FROM page_knowledge_fts;"
        var stmt: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)

        if count > maxEntries {
            let pruneSQL = "DELETE FROM page_knowledge_fts WHERE rowid IN (SELECT rowid FROM page_knowledge_fts ORDER BY timestamp ASC LIMIT 100);"
            sqlite3_exec(db, pruneSQL, nil, nil, nil)
        }
    }
}
