import Foundation
import SQLite3

final class WorkspaceLibraryDatabase {
    private let fileManager: FileManager
    private var database: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(paths: AppStoragePaths? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let dbPath: String
        if let paths = paths {
            try paths.ensureDirectories(fileManager: fileManager)
            dbPath = paths.databaseURL.path
        } else {
            dbPath = ":memory:"
        }

        guard sqlite3_open(dbPath, &database) == SQLITE_OK else {
            throw DatabaseError.openFailed(message: String(cString: sqlite3_errmsg(database)))
        }

        try execute(
            """
            CREATE TABLE IF NOT EXISTS workspaces (
                root_path TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                source_kind TEXT NOT NULL,
                clone_url TEXT,
                origin_path TEXT,
                added_at REAL NOT NULL,
                last_opened_at REAL NOT NULL,
                missing_path INTEGER NOT NULL DEFAULT 0
            );
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS exercise_progress (
                workspace_root_path TEXT NOT NULL,
                exercise_path TEXT NOT NULL,
                difficulty TEXT NOT NULL,
                passed_check_count INTEGER NOT NULL,
                total_check_count INTEGER NOT NULL,
                last_run_status TEXT NOT NULL,
                last_opened_at REAL NOT NULL,
                check_statuses_json TEXT NOT NULL,
                is_marked_done INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (workspace_root_path, exercise_path)
            );
            """
        )

        // Ensure new column exists for older DBs, ignoring error if it already exists
        _ = try? execute("ALTER TABLE exercise_progress ADD COLUMN is_marked_done INTEGER NOT NULL DEFAULT 0;")

        try execute(
            """
            CREATE TABLE IF NOT EXISTS workspace_state (
                workspace_root_path TEXT PRIMARY KEY,
                selected_exercise_path TEXT,
                active_tab_path TEXT,
                open_tabs_json TEXT NOT NULL,
                sidebar_mode TEXT NOT NULL,
                inspector_visible INTEGER NOT NULL DEFAULT 1,
                right_sidebar_tab TEXT NOT NULL DEFAULT 'inspector',
                right_sidebar_width REAL NOT NULL DEFAULT 360,
                terminal_display_mode TEXT NOT NULL DEFAULT 'split',
                search_query TEXT NOT NULL,
                difficulty_filter TEXT,
                tests_only INTEGER NOT NULL DEFAULT 0,
                selected_chat_session_id TEXT,
                last_saved_at REAL NOT NULL
            );
            """
        )

        try runMigrations()

        try execute(
            """
            CREATE TABLE IF NOT EXISTS chat_sessions (
                id TEXT PRIMARY KEY,
                workspace_root_path TEXT NOT NULL,
                exercise_path TEXT NOT NULL,
                title TEXT NOT NULL,
                provider_kind TEXT NOT NULL,
                model TEXT NOT NULL,
                backend_session_id TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS chat_messages (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at REAL NOT NULL,
                status TEXT NOT NULL,
                metadata_json TEXT
            );
            """
        )
    }

    deinit {
        sqlite3_close(database)
    }

    func fetchWorkspaces() throws -> [SavedWorkspaceRecord] {
        let statement = try prepare(
            """
            SELECT root_path, title, source_kind, clone_url, origin_path, added_at, last_opened_at, missing_path
            FROM workspaces
            ORDER BY last_opened_at DESC, title ASC;
            """
        )
        defer { sqlite3_finalize(statement) }

        var records: [SavedWorkspaceRecord] = []
        let row = Row(statement: statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(
                SavedWorkspaceRecord(
                    rootPath: row.string("root_path"),
                    title: row.string("title"),
                    sourceKind: WorkspaceSourceKind(rawValue: row.string("source_kind")) ?? .imported,
                    cloneURL: row.optionalString("clone_url"),
                    originPath: row.optionalString("origin_path"),
                    addedAt: Date(timeIntervalSince1970: row.double("added_at")),
                    lastOpenedAt: Date(timeIntervalSince1970: row.double("last_opened_at")),
                    isMissing: row.bool("missing_path")
                )
            )
        }

        return records
    }

    func fetchWorkspace(rootPath: String) throws -> SavedWorkspaceRecord? {
        let statement = try prepare(
            """
            SELECT root_path, title, source_kind, clone_url, origin_path, added_at, last_opened_at, missing_path
            FROM workspaces
            WHERE root_path = ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(rootPath, at: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let row = Row(statement: statement)
        return SavedWorkspaceRecord(
            rootPath: row.string("root_path"),
            title: row.string("title"),
            sourceKind: WorkspaceSourceKind(rawValue: row.string("source_kind")) ?? .imported,
            cloneURL: row.optionalString("clone_url"),
            originPath: row.optionalString("origin_path"),
            addedAt: Date(timeIntervalSince1970: row.double("added_at")),
            lastOpenedAt: Date(timeIntervalSince1970: row.double("last_opened_at")),
            isMissing: row.bool("missing_path")
        )
    }

    func upsertWorkspace(_ record: SavedWorkspaceRecord) throws {
        let statement = try prepare(
            """
            INSERT INTO workspaces (
                root_path, title, source_kind, clone_url, origin_path, added_at, last_opened_at, missing_path
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(root_path) DO UPDATE SET
                title = excluded.title,
                source_kind = excluded.source_kind,
                clone_url = excluded.clone_url,
                origin_path = COALESCE(excluded.origin_path, workspaces.origin_path),
                added_at = excluded.added_at,
                last_opened_at = excluded.last_opened_at,
                missing_path = excluded.missing_path;
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(record.rootPath, at: 1, in: statement)
        bind(record.title, at: 2, in: statement)
        bind(record.sourceKind.rawValue, at: 3, in: statement)
        bind(record.cloneURL, at: 4, in: statement)
        bind(record.originPath, at: 5, in: statement)
        sqlite3_bind_double(statement, 6, record.addedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 7, record.lastOpenedAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 8, record.isMissing ? 1 : 0)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database)))
        }
    }

    func fetchProgress(for workspaceRootPath: String) throws -> [String: StoredExerciseProgress] {
        let statement = try prepare(
            """
            SELECT exercise_path, difficulty, passed_check_count, total_check_count, last_run_status, last_opened_at, check_statuses_json, is_marked_done
            FROM exercise_progress
            WHERE workspace_root_path = ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(workspaceRootPath, at: 1, in: statement)

        let row = Row(statement: statement)
        var progressLookup: [String: StoredExerciseProgress] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let exercisePath = row.string("exercise_path")
            let difficulty = ExerciseDifficulty(rawValue: row.string("difficulty")) ?? .unknown
            let checkStatuses = decodeCheckStatuses(from: row.string("check_statuses_json"))

            progressLookup[exercisePath] = StoredExerciseProgress(
                workspaceRootPath: workspaceRootPath,
                exercisePath: exercisePath,
                difficulty: difficulty,
                passedCheckCount: row.int("passed_check_count"),
                totalCheckCount: row.int("total_check_count"),
                lastRunStatus: RunState(rawValue: row.string("last_run_status")) ?? .idle,
                lastOpenedAt: Date(timeIntervalSince1970: row.double("last_opened_at")),
                checkStatuses: checkStatuses,
                isMarkedDone: row.int("is_marked_done") == 1
            )
        }

        return progressLookup
    }

    func deleteWorkspace(rootPath: String) throws {
        try executeDelete(
            """
            DELETE FROM chat_messages
            WHERE session_id IN (
                SELECT id FROM chat_sessions WHERE workspace_root_path = ?
            );
            """,
            value: rootPath
        )
        try executeDelete(
            """
            DELETE FROM chat_sessions
            WHERE workspace_root_path = ?;
            """,
            value: rootPath
        )
        try executeDelete(
            """
            DELETE FROM exercise_progress
            WHERE workspace_root_path = ?;
            """,
            value: rootPath
        )
        try executeDelete(
            """
            DELETE FROM workspace_state
            WHERE workspace_root_path = ?;
            """,
            value: rootPath
        )
        try executeDelete(
            """
            DELETE FROM workspaces
            WHERE root_path = ?;
            """,
            value: rootPath
        )
    }

    func saveProgress(_ progressEntries: [StoredExerciseProgress], for workspaceRootPath: String) throws {
        let statement = try prepare(
            """
            INSERT INTO exercise_progress (
                workspace_root_path, exercise_path, difficulty, passed_check_count, total_check_count,
                last_run_status, last_opened_at, check_statuses_json, is_marked_done
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(workspace_root_path, exercise_path) DO UPDATE SET
                difficulty = excluded.difficulty,
                passed_check_count = excluded.passed_check_count,
                total_check_count = excluded.total_check_count,
                last_run_status = excluded.last_run_status,
                last_opened_at = excluded.last_opened_at,
                check_statuses_json = excluded.check_statuses_json,
                is_marked_done = excluded.is_marked_done;
            """
        )
        defer { sqlite3_finalize(statement) }

        for entry in progressEntries {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            bind(workspaceRootPath, at: 1, in: statement)
            bind(entry.exercisePath, at: 2, in: statement)
            bind(entry.difficulty.rawValue, at: 3, in: statement)
            sqlite3_bind_int(statement, 4, Int32(entry.passedCheckCount))
            sqlite3_bind_int(statement, 5, Int32(entry.totalCheckCount))
            bind(entry.lastRunStatus.rawValue, at: 6, in: statement)
            sqlite3_bind_double(statement, 7, entry.lastOpenedAt.timeIntervalSince1970)
            bind(encodeCheckStatuses(entry.checkStatuses), at: 8, in: statement)
            sqlite3_bind_int(statement, 9, Int32(entry.isMarkedDone ? 1 : 0))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    func fetchWorkspaceState(for workspaceRootPath: String) throws -> WorkspaceSessionState? {
        let statement = try prepare(
            """
            SELECT selected_exercise_path, active_tab_path, open_tabs_json, sidebar_mode, inspector_visible, right_sidebar_tab, right_sidebar_width, terminal_display_mode, search_query, difficulty_filter, tests_only, shows_completed_exercises, selected_chat_session_id
            FROM workspace_state
            WHERE workspace_root_path = ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(workspaceRootPath, at: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let row = Row(statement: statement)
        let openTabs = decodeOpenTabs(from: row.string("open_tabs_json"))
        let sidebarMode = SidebarMode(rawValue: row.string("sidebar_mode")) ?? .exercises
        let inspectorVisible = row.bool("inspector_visible")
        let rightSidebarTab = RightSidebarTab(rawValue: row.string("right_sidebar_tab")) ?? .inspector
        let terminalDisplayMode = TerminalDisplayMode(rawValue: row.string("terminal_display_mode")) ?? .split
        let difficultyFilter = row.optionalString("difficulty_filter").flatMap(ExerciseDifficulty.init(rawValue:))

        return WorkspaceSessionState(
            workspaceRootPath: workspaceRootPath,
            selectedExercisePath: row.optionalString("selected_exercise_path"),
            activeTabPath: row.optionalString("active_tab_path"),
            openTabs: openTabs,
            sidebarMode: sidebarMode,
            isInspectorVisible: inspectorVisible,
            rightSidebarTab: rightSidebarTab,
            rightSidebarWidth: row.double("right_sidebar_width"),
            terminalDisplayMode: terminalDisplayMode,
            searchQuery: row.string("search_query"),
            difficultyFilter: difficultyFilter,
            showsOnlyTestExercises: row.bool("tests_only"),
            completionFilter: row.bool("shows_completed_exercises") ? .done : .open,
            selectedChatSessionID: row.optionalString("selected_chat_session_id").flatMap(UUID.init(uuidString:))
        )
    }

    func saveWorkspaceState(_ state: WorkspaceSessionState) throws {
        let statement = try prepare(
            """
            INSERT INTO workspace_state (
                workspace_root_path, selected_exercise_path, active_tab_path, open_tabs_json,
                sidebar_mode, inspector_visible, right_sidebar_tab, right_sidebar_width, terminal_display_mode, search_query, difficulty_filter, tests_only, shows_completed_exercises, selected_chat_session_id, last_saved_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(workspace_root_path) DO UPDATE SET
                selected_exercise_path = excluded.selected_exercise_path,
                active_tab_path = excluded.active_tab_path,
                open_tabs_json = excluded.open_tabs_json,
                sidebar_mode = excluded.sidebar_mode,
                inspector_visible = excluded.inspector_visible,
                right_sidebar_tab = excluded.right_sidebar_tab,
                right_sidebar_width = excluded.right_sidebar_width,
                terminal_display_mode = excluded.terminal_display_mode,
                search_query = excluded.search_query,
                difficulty_filter = excluded.difficulty_filter,
                tests_only = excluded.tests_only,
                shows_completed_exercises = excluded.shows_completed_exercises,
                selected_chat_session_id = excluded.selected_chat_session_id,
                last_saved_at = excluded.last_saved_at;
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(state.workspaceRootPath, at: 1, in: statement)
        bind(state.selectedExercisePath, at: 2, in: statement)
        bind(state.activeTabPath, at: 3, in: statement)
        bind(encodeOpenTabs(state.openTabs), at: 4, in: statement)
        bind(state.sidebarMode.rawValue, at: 5, in: statement)
        sqlite3_bind_int(statement, 6, state.isInspectorVisible ? 1 : 0)
        bind(state.rightSidebarTab.rawValue, at: 7, in: statement)
        sqlite3_bind_double(statement, 8, state.rightSidebarWidth)
        bind(state.terminalDisplayMode.rawValue, at: 9, in: statement)
        bind(state.searchQuery, at: 10, in: statement)
        bind(state.difficultyFilter?.rawValue, at: 11, in: statement)
        sqlite3_bind_int(statement, 12, state.showsOnlyTestExercises ? 1 : 0)
        sqlite3_bind_int(statement, 13, state.completionFilter == .done ? 1 : 0)
        bind(state.selectedChatSessionID?.uuidString, at: 14, in: statement)
        sqlite3_bind_double(statement, 15, Date().timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database)))
        }
    }

    func fetchChatSessions(workspaceRootPath: String, exercisePath: String) throws -> [ExerciseChatSession] {
        let statement = try prepare(
            """
            SELECT id, workspace_root_path, exercise_path, title, provider_kind, model, backend_session_id, created_at, updated_at
            FROM chat_sessions
            WHERE workspace_root_path = ? AND exercise_path = ?
            ORDER BY updated_at DESC, created_at DESC;
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(workspaceRootPath, at: 1, in: statement)
        bind(exercisePath, at: 2, in: statement)

        var result: [ExerciseChatSession] = []
        let row = Row(statement: statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: row.string("id")) else {
                continue
            }

            result.append(
                ExerciseChatSession(
                    id: id,
                    workspaceRootPath: row.string("workspace_root_path"),
                    exercisePath: row.string("exercise_path"),
                    title: row.string("title"),
                    providerKind: AIProviderKind(rawValue: row.string("provider_kind")) ?? .codexCLI,
                    model: row.string("model"),
                    backendSessionID: row.optionalString("backend_session_id"),
                    createdAt: Date(timeIntervalSince1970: row.double("created_at")),
                    updatedAt: Date(timeIntervalSince1970: row.double("updated_at"))
                )
            )
        }

        return result
    }

    func upsertChatSession(_ session: ExerciseChatSession) throws {
        let statement = try prepare(
            """
            INSERT INTO chat_sessions (
                id, workspace_root_path, exercise_path, title, provider_kind, model, backend_session_id, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                workspace_root_path = excluded.workspace_root_path,
                exercise_path = excluded.exercise_path,
                title = excluded.title,
                provider_kind = excluded.provider_kind,
                model = excluded.model,
                backend_session_id = excluded.backend_session_id,
                updated_at = excluded.updated_at;
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(session.id.uuidString, at: 1, in: statement)
        bind(session.workspaceRootPath, at: 2, in: statement)
        bind(session.exercisePath, at: 3, in: statement)
        bind(session.title, at: 4, in: statement)
        bind(session.providerKind.rawValue, at: 5, in: statement)
        bind(session.model, at: 6, in: statement)
        bind(session.backendSessionID, at: 7, in: statement)
        sqlite3_bind_double(statement, 8, session.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 9, session.updatedAt.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database)))
        }
    }

    func fetchMessages(for sessionID: UUID) throws -> [ExerciseChatMessage] {
        let statement = try prepare(
            """
            SELECT id, session_id, role, content, created_at, status, metadata_json
            FROM chat_messages
            WHERE session_id = ?
            ORDER BY created_at ASC;
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(sessionID.uuidString, at: 1, in: statement)

        var result: [ExerciseChatMessage] = []
        let row = Row(statement: statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: row.string("id")),
                  let resolvedSessionID = UUID(uuidString: row.string("session_id"))
            else {
                continue
            }

            result.append(
                ExerciseChatMessage(
                    id: id,
                    sessionID: resolvedSessionID,
                    role: ExerciseChatRole(rawValue: row.string("role")) ?? .assistant,
                    content: row.string("content"),
                    createdAt: Date(timeIntervalSince1970: row.double("created_at")),
                    status: ExerciseChatMessageStatus(rawValue: row.string("status")) ?? .complete,
                    metadataJSON: row.optionalString("metadata_json")
                )
            )
        }

        return result
    }

    func insertChatMessage(_ message: ExerciseChatMessage) throws {
        let statement = try prepare(
            """
            INSERT INTO chat_messages (id, session_id, role, content, created_at, status, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(message.id.uuidString, at: 1, in: statement)
        bind(message.sessionID.uuidString, at: 2, in: statement)
        bind(message.role.rawValue, at: 3, in: statement)
        bind(message.content, at: 4, in: statement)
        sqlite3_bind_double(statement, 5, message.createdAt.timeIntervalSince1970)
        bind(message.status.rawValue, at: 6, in: statement)
        bind(message.metadataJSON, at: 7, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database)))
        }
    }

    func deleteMessages(for sessionID: UUID) throws {
        let statement = try prepare(
            """
            DELETE FROM chat_messages
            WHERE session_id = ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(sessionID.uuidString, at: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database)))
        }
    }

    func deleteMessage(id: UUID) throws {
        let statement = try prepare(
            """
            DELETE FROM chat_messages
            WHERE id = ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(id.uuidString, at: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database)))
        }
    }

    // MARK: - Schema Migrations

    private func getUserVersion() throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    /// Applies incremental schema migrations guarded by PRAGMA user_version.
    /// Each version block runs exactly once; errors are propagated rather than silenced.
    private func runMigrations() throws {
        let currentVersion = try getUserVersion()

        // v1: Add origin_path to workspaces table
        if currentVersion < 1 {
            try? execute("ALTER TABLE workspaces ADD COLUMN origin_path TEXT;")
        }

        // v2: Add shows_completed_exercises and right_sidebar_tab to workspace_state
        if currentVersion < 2 {
            try? execute("ALTER TABLE workspace_state ADD COLUMN shows_completed_exercises INTEGER NOT NULL DEFAULT 0;")
            try? execute("ALTER TABLE workspace_state ADD COLUMN right_sidebar_tab TEXT NOT NULL DEFAULT 'inspector';")
        }

        // v3: Add selected_chat_session_id
        if currentVersion < 3 {
            try? execute("ALTER TABLE workspace_state ADD COLUMN selected_chat_session_id TEXT;")
        }

        // v4: Add right_sidebar_width
        if currentVersion < 4 {
            try? execute("ALTER TABLE workspace_state ADD COLUMN right_sidebar_width REAL NOT NULL DEFAULT 360;")
        }

        // v5: Add inspector_visible
        if currentVersion < 5 {
            try? execute("ALTER TABLE workspace_state ADD COLUMN inspector_visible INTEGER NOT NULL DEFAULT 1;")
        }

        // v6: Add terminal_display_mode
        if currentVersion < 6 {
            try? execute("ALTER TABLE workspace_state ADD COLUMN terminal_display_mode TEXT NOT NULL DEFAULT 'split';")
        }

        // v7: Add tests_only filter
        if currentVersion < 7 {
            try? execute("ALTER TABLE workspace_state ADD COLUMN tests_only INTEGER NOT NULL DEFAULT 0;")
        }

        // Bump schema version to latest
        guard sqlite3_exec(database, "PRAGMA user_version = 7;", nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.executionFailed(message: "Failed to update schema version: \(String(cString: sqlite3_errmsg(database)))")
        }
    }

    // MARK: - Private helpers

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database)))
        }
    }


    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(message: String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func executeDelete(_ sql: String, value: String) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        bind(value, at: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database)))
        }
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }

        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private struct Row {
        let statement: OpaquePointer?
        private let columnIndices: [String: Int32]

        init(statement: OpaquePointer?) {
            self.statement = statement
            let count = sqlite3_column_count(statement)
            var indices: [String: Int32] = [:]
            for i in 0..<count {
                if let name = sqlite3_column_name(statement, i) {
                    indices[String(cString: name).lowercased()] = i
                }
            }
            self.columnIndices = indices
        }

        func string(_ name: String) -> String {
            guard let index = columnIndices[name.lowercased()],
                  let ptr = sqlite3_column_text(statement, index) else {
                return ""
            }
            return String(cString: ptr)
        }

        func optionalString(_ name: String) -> String? {
            guard let index = columnIndices[name.lowercased()],
                  let ptr = sqlite3_column_text(statement, index) else {
                return nil
            }
            return String(cString: ptr)
        }

        func double(_ name: String) -> Double {
            guard let index = columnIndices[name.lowercased()] else { return 0 }
            return sqlite3_column_double(statement, index)
        }

        func int(_ name: String) -> Int {
            guard let index = columnIndices[name.lowercased()] else { return 0 }
            return Int(sqlite3_column_int(statement, index))
        }

        func bool(_ name: String) -> Bool {
            int(name) != 0
        }
    }

    private func encodeOpenTabs(_ tabs: [ActiveDocumentTab]) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(tabs) else {
            return "[]"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeOpenTabs(from string: String) -> [ActiveDocumentTab] {
        let decoder = JSONDecoder()
        guard let data = string.data(using: .utf8) else {
            return []
        }
        return (try? decoder.decode([ActiveDocumentTab].self, from: data)) ?? []
    }

    private func encodeCheckStatuses(_ statuses: [String: CheckStatus]) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(statuses) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeCheckStatuses(from string: String) -> [String: CheckStatus] {
        let decoder = JSONDecoder()
        guard let data = string.data(using: .utf8) else {
            return [:]
        }
        return (try? decoder.decode([String: CheckStatus].self, from: data)) ?? [:]
    }
}

extension WorkspaceLibraryDatabase {
    enum DatabaseError: LocalizedError {
        case openFailed(message: String)
        case prepareFailed(message: String)
        case executionFailed(message: String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let message):
                "Failed to open workspace library database: \(message)"
            case .prepareFailed(let message):
                "Failed to prepare workspace library database query: \(message)"
            case .executionFailed(let message):
                "Failed to execute workspace library database query: \(message)"
            }
        }
    }
}
