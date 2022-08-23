// MARK: - Upsert

extension PersistableRecord {
#if GRDBCUSTOMSQLITE || GRDBCIPHER
    /// Executes an `INSERT ... ON CONFLICT DO UPDATE` statement.
    ///
    /// The upsert behavior is triggered by a violation of any uniqueness
    /// constraint on the table (primary key or unique index). In case of
    /// violation, all columns but the primary key are overwritten with the
    /// inserted values:
    ///
    ///     struct Player: Encodable, PersistableRecord {
    ///         var id: Int64
    ///         var name: String
    ///         var score: Int
    ///     }
    ///
    ///     // INSERT INTO player (id, name, score)
    ///     // VALUES (1, 'Arthur', 1000)
    ///     // ON CONFLICT DO UPDATE SET
    ///     //   name = excluded.name,
    ///     //   score = excluded.score
    ///     let player = Player(id: 1, name: "Arthur", score: 1000)
    ///     try player.upsert(db)
    @inlinable // allow specialization so that empty callbacks are removed
    public func upsert(_ db: Database) throws {
        try willSave(db)
        
        var saved: PersistenceSuccess!
        try aroundSave(db) {
            let inserted = try upsertWithCallbacks(db)
            saved = PersistenceSuccess(inserted)
            return saved
        }
        
        didSave(saved)
    }
    
    /// Executes an `INSERT ... ON CONFLICT DO UPDATE ... RETURNING ...`
    /// statement, and returns the upserted record.
    ///
    /// With default parameters (`upsertAndFetch(db)`), the upsert behavior is
    /// triggered by a violation of any uniqueness constraint on the table
    /// (primary key or unique index). In case of violation, all columns but the
    /// primary key are overwritten with the inserted values:
    ///
    ///     struct Player: Encodable, PersistableRecord {
    ///         var id: Int64
    ///         var name: String
    ///         var score: Int
    ///     }
    ///
    ///     // INSERT INTO player (id, name, score)
    ///     // VALUES (1, 'Arthur', 1000)
    ///     // ON CONFLICT DO UPDATE SET
    ///     //   name = excluded.name,
    ///     //   score = excluded.score
    ///     // RETURNING *
    ///     let player = Player(id: 1, name: "Arthur", score: 1000)
    ///     let upsertedPlayer = try player.upsertAndFetch(db)
    ///
    /// With `conflictTarget` and `assignments` arguments, you can further
    /// control the upsert behavior. Make sure you check
    /// <https://www.sqlite.org/lang_UPSERT.html> for detailed information.
    ///
    /// The conflict target are the columns of the uniqueness constraint
    /// (primary key or unique index) that triggers the upsert. If empty, all
    /// uniqueness constraint are considered.
    ///
    /// The assignments describe how to update columns in case of violation of
    /// a uniqueness constraint. In the next example, we insert the new
    /// vocabulary word "jovial" if that word is not already in the dictionary.
    /// If the word is already in the dictionary, it increments the counter,
    /// does not overwrite the tainted flag, and overwrites the
    /// remaining columns:
    ///
    ///     // CREATE TABLE vocabulary(
    ///     //   word TEXT PRIMARY KEY,
    ///     //   kind TEXT NOT NULL,
    ///     //   isTainted BOOLEAN DEFAULT 0,
    ///     //   count INT DEFAULT 1))
    ///     struct Vocabulary: Encodable, PersistableRecord {
    ///         var word: String
    ///         var kind: String
    ///         var isTainted: Bool
    ///     }
    ///
    ///     // INSERT INTO vocabulary(word, kind, isTainted)
    ///     // VALUES('jovial', 'adjective', 0)
    ///     // ON CONFLICT(word) DO UPDATE SET \
    ///     //   count = count + 1,
    ///     //   kind = excluded.kind
    ///     // RETURNING *
    ///     let vocabulary = Vocabulary(word: "jovial", kind: "adjective", isTainted: false)
    ///     let upserted = try vocabulary.upsertAndFetch(
    ///         db,
    ///         onConflict: ["word"],
    ///         doUpdate: { _ in
    ///             [Column("count") += 1,
    ///              Column("isTainted").noOverwrite]
    ///         })
    ///
    /// - parameter db: A database connection.
    /// - parameter conflictTarget: The conflict target.
    /// - parameter assignments: An optional function that returns an array of
    ///   ``ColumnAssignment``. In case of violation of a uniqueness
    ///   constraints, these assignments are performed, and remaining columns
    ///   are overwritten by inserted values.
    /// - returns: The upserted record.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    @inlinable // allow specialization so that empty callbacks are removed
    public func upsertAndFetch(
        _ db: Database,
        onConflict conflictTarget: [String] = [],
        doUpdate assignments: ((_ excluded: TableAlias) -> [ColumnAssignment])? = nil)
    throws -> Self
    where Self: FetchableRecord
    {
        try upsertAndFetch(db, as: Self.self, onConflict: conflictTarget, doUpdate: assignments)
    }
    
    /// Executes an `INSERT ... ON CONFLICT DO UPDATE ... RETURNING ...`
    /// statement, and returns the upserted record.
    ///
    /// See `upsertAndFetch(_:onConflict:doUpdate:)` for more information about
    /// the `conflictTarget` and `assignments` parameters.
    ///
    /// - parameter db: A database connection.
    /// - parameter returnedType: The type of the returned record.
    /// - parameter conflictTarget: The conflict target.
    /// - parameter assignments: An optional function that returns an array of
    ///   ``ColumnAssignment``. In case of violation of a uniqueness
    ///   constraints, these assignments are performed, and remaining columns
    ///   are overwritten by inserted values.
    /// - returns: A record of type `returnedType`.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    @inlinable // allow specialization so that empty callbacks are removed
    public func upsertAndFetch<T: FetchableRecord & TableRecord>(
        _ db: Database,
        as returnedType: T.Type,
        onConflict conflictTarget: [String] = [],
        doUpdate assignments: ((_ excluded: TableAlias) -> [ColumnAssignment])? = nil)
    throws -> T
    {
        try willSave(db)
        
        var inserted: InsertionSuccess!
        var returned: T!
        try aroundSave(db) {
            (inserted, returned) = try upsertAndFetchWithCallbacks(
                db, onConflict: conflictTarget,
                doUpdate: assignments,
                selection: T.databaseSelection,
                decode: { try T(row: $0) })
            return PersistenceSuccess(inserted)
        }
        
        didSave(PersistenceSuccess(inserted))
        return returned
    }
#else
    /// Executes an `INSERT ... ON CONFLICT DO UPDATE` statement.
    ///
    /// The upsert behavior is triggered by a violation of any uniqueness
    /// constraint on the table (primary key or unique index). In case of
    /// violation, all columns but the primary key are overwritten with the
    /// inserted values:
    ///
    ///     struct Player: Encodable, PersistableRecord {
    ///         var id: Int64
    ///         var name: String
    ///         var score: Int
    ///     }
    ///
    ///     // INSERT INTO player (id, name, score)
    ///     // VALUES (1, 'Arthur', 1000)
    ///     // ON CONFLICT DO UPDATE SET
    ///     //   name = excluded.name,
    ///     //   score = excluded.score
    ///     let player = Player(id: 1, name: "Arthur", score: 1000)
    ///     try player.upsert(db)
    @inlinable // allow specialization so that empty callbacks are removed
    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) // SQLite 3.35.0+
    public func upsert(_ db: Database) throws {
        try willSave(db)
        
        var saved: PersistenceSuccess!
        try aroundSave(db) {
            let inserted = try upsertWithCallbacks(db)
            saved = PersistenceSuccess(inserted)
            return saved
        }
        
        didSave(saved)
    }
    
    /// Executes an `INSERT ... ON CONFLICT DO UPDATE ... RETURNING ...`
    /// statement, and returns the upserted record.
    ///
    /// With default parameters (`upsertAndFetch(db)`), the upsert behavior is
    /// triggered by a violation of any uniqueness constraint on the table
    /// (primary key or unique index). In case of violation, all columns but the
    /// primary key are overwritten with the inserted values:
    ///
    ///     struct Player: Encodable, PersistableRecord {
    ///         var id: Int64
    ///         var name: String
    ///         var score: Int
    ///     }
    ///
    ///     // INSERT INTO player (id, name, score)
    ///     // VALUES (1, 'Arthur', 1000)
    ///     // ON CONFLICT DO UPDATE SET
    ///     //   name = excluded.name,
    ///     //   score = excluded.score
    ///     // RETURNING *
    ///     let player = Player(id: 1, name: "Arthur", score: 1000)
    ///     let upsertedPlayer = try player.upsertAndFetch(db)
    ///
    /// With `conflictTarget` and `assignments` arguments, you can further
    /// control the upsert behavior. Make sure you check
    /// <https://www.sqlite.org/lang_UPSERT.html> for detailed information.
    ///
    /// The conflict target are the columns of the uniqueness constraint
    /// (primary key or unique index) that triggers the upsert. If empty, all
    /// uniqueness constraint are considered.
    ///
    /// The assignments describe how to update columns in case of violation of
    /// a uniqueness constraint. In the next example, we insert the new
    /// vocabulary word "jovial" if that word is not already in the dictionary.
    /// If the word is already in the dictionary, it increments the counter,
    /// does not overwrite the tainted flag, and overwrites the
    /// remaining columns:
    ///
    ///     // CREATE TABLE vocabulary(
    ///     //   word TEXT PRIMARY KEY,
    ///     //   kind TEXT NOT NULL,
    ///     //   isTainted BOOLEAN DEFAULT 0,
    ///     //   count INT DEFAULT 1))
    ///     struct Vocabulary: Encodable, PersistableRecord {
    ///         var word: String
    ///         var kind: String
    ///         var isTainted: Bool
    ///     }
    ///
    ///     // INSERT INTO vocabulary(word, kind, isTainted)
    ///     // VALUES('jovial', 'adjective', 0)
    ///     // ON CONFLICT(word) DO UPDATE SET \
    ///     //   count = count + 1,
    ///     //   kind = excluded.kind
    ///     // RETURNING *
    ///     let vocabulary = Vocabulary(word: "jovial", kind: "adjective", isTainted: false)
    ///     let upserted = try vocabulary.upsertAndFetch(
    ///         db,
    ///         onConflict: ["word"],
    ///         doUpdate: { _ in
    ///             [Column("count") += 1,
    ///              Column("isTainted").noOverwrite]
    ///         })
    ///
    /// - parameter db: A database connection.
    /// - parameter conflictTarget: The conflict target.
    /// - parameter assignments: An optional function that returns an array of
    ///   ``ColumnAssignment``. In case of violation of a uniqueness
    ///   constraints, these assignments are performed, and remaining columns
    ///   are overwritten by inserted values.
    /// - returns: The upserted record.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    @inlinable // allow specialization so that empty callbacks are removed
    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) // SQLite 3.35.0+
    public func upsertAndFetch(
        _ db: Database,
        onConflict conflictTarget: [String] = [],
        doUpdate assignments: ((_ excluded: TableAlias) -> [ColumnAssignment])? = nil)
    throws -> Self
    where Self: FetchableRecord
    {
        try upsertAndFetch(db, as: Self.self, onConflict: conflictTarget, doUpdate: assignments)
    }
    
    /// Executes an `INSERT ... ON CONFLICT DO UPDATE ... RETURNING ...`
    /// statement, and returns the upserted record.
    ///
    /// See `upsertAndFetch(_:onConflict:doUpdate:)` for more information about
    /// the `conflictTarget` and `assignments` parameters.
    ///
    /// - parameter db: A database connection.
    /// - parameter returnedType: The type of the returned record.
    /// - parameter conflictTarget: The conflict target.
    /// - parameter assignments: An optional function that returns an array of
    ///   ``ColumnAssignment``. In case of violation of a uniqueness
    ///   constraints, these assignments are performed, and remaining columns
    ///   are overwritten by inserted values.
    /// - returns: A record of type `returnedType`.
    /// - throws: A DatabaseError whenever an SQLite error occurs.
    @inlinable // allow specialization so that empty callbacks are removed
    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) // SQLite 3.35.0+
    public func upsertAndFetch<T: FetchableRecord & TableRecord>(
        _ db: Database,
        as returnedType: T.Type,
        onConflict conflictTarget: [String] = [],
        doUpdate assignments: ((_ excluded: TableAlias) -> [ColumnAssignment])? = nil)
    throws -> T
    {
        try willSave(db)
        
        var inserted: InsertionSuccess!
        var returned: T!
        try aroundSave(db) {
            (inserted, returned) = try upsertAndFetchWithCallbacks(
                db, onConflict: conflictTarget,
                doUpdate: assignments,
                selection: T.databaseSelection,
                decode: { try T(row: $0) })
            return PersistenceSuccess(inserted)
        }
        
        didSave(PersistenceSuccess(inserted))
        return returned
    }
#endif
}

// MARK: - Internal

extension PersistableRecord {
    @inlinable // allow specialization so that empty callbacks are removed
    func upsertWithCallbacks(_ db: Database)
    throws -> InsertionSuccess
    {
        let (inserted, _) = try upsertAndFetchWithCallbacks(
            db, onConflict: [],
            doUpdate: nil,
            selection: [],
            decode: { _ in /* Nothing to decode */ })
        return inserted
    }

    @inlinable // allow specialization so that empty callbacks are removed
    func upsertAndFetchWithCallbacks<T>(
        _ db: Database,
        onConflict conflictTarget: [String],
        doUpdate assignments: ((_ excluded: TableAlias) -> [ColumnAssignment])?,
        selection: [any SQLSelectable],
        decode: (Row) throws -> T)
    throws -> (InsertionSuccess, T)
    {
        try willInsert(db)
        
        var inserted: InsertionSuccess!
        var returned: T!
        try aroundInsert(db) {
            (inserted, returned) = try upsertAndFetchWithoutCallbacks(
                db, onConflict: conflictTarget,
                doUpdate: assignments,
                selection: selection,
                decode: decode)
            return inserted
        }
        
        didInsert(inserted)
        return (inserted, returned)
    }
}