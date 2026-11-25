import Foundation
import Security
import SQLite3

struct TransferReceipt: Codable {
    var size: Int64
    var sha256: String
    var partSize: Int64
    var confirmed: Int64 = 0
    var upload: String?
    var etag: String?
}

final class TransferLedger {
    private let db: OpaquePointer
    private let transient = unsafeBitCast(-1, to:sqlite3_destructor_type.self)

    init(_ directory: URL) throws {
        let url = directory.appendingPathComponent("transfer-v2.sqlite")
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path,&handle,SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            throw DiskFailure.rejected
        }
        guard sqlite3_exec(handle,"PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY, receipt BLOB NOT NULL)",nil,nil,nil) == SQLITE_OK else {
            sqlite3_close(handle)
            throw DiskFailure.rejected
        }
        db = handle
    }

    deinit { sqlite3_close(db) }

    private func statement<T>(_ sql: String, id: String, action: (OpaquePointer) throws -> T) throws -> T {
        var value: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&value,nil) == SQLITE_OK, let value else { throw DiskFailure.rejected }
        defer { sqlite3_finalize(value) }
        guard sqlite3_bind_text(value,1,id,-1,transient) == SQLITE_OK else { throw DiskFailure.rejected }
        return try action(value)
    }

    func read(_ id: String) throws -> TransferReceipt? {
        try statement("SELECT receipt FROM jobs WHERE id=?",id:id) { value in
            let result = sqlite3_step(value)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(value,0) else { throw DiskFailure.rejected }
            return try JSONDecoder().decode(TransferReceipt.self,from:Data(bytes:bytes,count:Int(sqlite3_column_bytes(value,0))))
        }
    }

    func write(_ id: String, _ receipt: TransferReceipt) throws {
        let data = try JSONEncoder().encode(receipt)
        try statement("INSERT INTO jobs VALUES (?,?) ON CONFLICT(id) DO UPDATE SET receipt=excluded.receipt",id:id) { value in
            let bound = data.withUnsafeBytes { sqlite3_bind_blob(value,2,$0.baseAddress,Int32($0.count),transient) }
            guard bound == SQLITE_OK, sqlite3_step(value) == SQLITE_DONE else { throw DiskFailure.rejected }
        }
    }
}

struct DiskDeviceKey: Codable {
    var token: String
    var expires: TimeInterval

    private static let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,
        kSecAttrService as String:"ru.atma.phonedisk.v2",kSecAttrAccount as String:"transfers"]

    static func load() -> Self? {
        var query = Self.query
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self,from:data)
    }

    func store() throws {
        let data = try JSONEncoder().encode(self)
        let values = [kSecValueData as String:data]
        let result = SecItemUpdate(Self.query as CFDictionary,values as CFDictionary)
        if result == errSecSuccess { return }
        guard result == errSecItemNotFound else { throw DiskFailure.signIn }
        var item = Self.query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { throw DiskFailure.signIn }
    }

    static func clear(_ token: String? = nil) {
        if let token, load()?.token != token { return }
        SecItemDelete(query as CFDictionary)
    }
}
