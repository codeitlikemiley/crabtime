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
                PRIMARY KEY (workspace_root_path, exercise_path)
            );
            """
        )

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

        try? execute(
            """
            ALTER TABLE workspaces
            ADD COLUMN origin_path TEXT;
            """
        )
        try? execute(
            """
            ALTER TABLE workspace_state
            ADD COLUMN shows_completed_exercises INTEGER NOT NULL DEFAULT 0;
            """
        )
        try? execute(
            """
            ALTER TABLE workspace_state
            ADD COLUMN right_sidebar_tab TEXT NOT NULL DEFAULT 'inspector';
            """
        )
        try? execute(
            """
            ALTER TABLE workspace_state
            ADD COLUMN selected_chat_session_id TEXT;
            """
        )
        try? execute(
            """
            ALTER TABLE workspace_state
            ADD COLUMN right_sidebar_width REAL NOT NULL DEFAULT 360;
            """
        )
        try? execute(
            """
            ALTER TABLE workspace_state
            ADD COLUMN inspector_visible INTEGER NOT NULL DEFAULT 1;
            """
        )
        try? execute(
            """
            ALTER TABLE workspace_state
            ADD COLUMN terminal_display_mode TEXT NOT NULL DEFAULT 'split';
            """
        )
        try? execute(
            """
            ALTER TABLE workspace_state
            ADD COLUMN tests_only INTEGER NOT NULL DEFAULT 0;
            """
        )

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
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(
                SavedWorkspaceRecord(
                    rootPath: string(at: 0, in: statement),
                    title: string(at: 1, in: statement),
                    sourceKind: WorkspaceSourceKind(rawValue: string(at: 2, in: statement)) ?? .imported,
                    cloneURL: optionalString(at: 3, in: statement),
                    originPath: optionalString(at: 4, in: statement),
                    addedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                    lastOpenedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                    isMissing: sqlite3_column_int(statement, 7) != 0
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

        return SavedWorkspaceRecord(
            rootPath: string(at: 0, in: statement),
            title: string(at: 1, in: statement),
            sourceKind: WorkspaceSourceKind(rawValue: string(at: 2, in: statement)) ?? .imported,
            cloneURL: optionalString(at: 3, in: statement),
            originPath: optionalString(at: 4, in: statement),
            addedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
            lastOpenedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
            isMissing: sqlite3_column_int(statement, 7) != 0
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
            SELECT exercise_path, difficulty, passed_check_count, total_check_count, last_run_status, last_opened_at, check_statuses_json
            FROM exercise_progress
            WHERE workspace_root_path = ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(workspaceRootPath, at: 1, in: statement)

        var progressLookup: [String: StoredExerciseProgress] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let exercisePath = string(at: 0, in: statement)
            let difficulty = ExerciseDifficulty(rawValue: string(at: 1, in: statement)) ?? .unknown
            let checkStatuses = decodeCheckStatuses(from: string(at: 6, in: statement))

            progressLookup[exercisePath] = StoredExerciseProgress(
                workspaceRootPath: workspaceRootPath,
                exercisePath: exercisePath,
                difficulty: difficulty,
                passedCheckCount: Int(sqlite3_column_int(statement, 2)),
                totalCheckCount: Int(sqlite3_column_int(statement, 3)),
                lastRunStatus: RunState(rawValue: string(at: 4, in: statement)) ?? .idle,
                lastOpenedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                checkStatuses: checkStatuses
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
                last_run_status, last_opened_at, check_statuses_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(workspace_root_path, exercise_path) DO UPDATE SET
                difficulty = excluded.difficulty,
                passed_check_count = excluded.passed_check_count,
                total_check_count = excluded.total_check_count,
                last_run_status = excluded.last_run_status,
                last_opened_at = excluded.last_opened_at,
                check_statuses_json = excluded.check_statuses_json;
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

        let openTabs = decodeOpenTabs(from: string(at: 2, in: statement))
        let sidebarMode = SidebarMode(rawValue: string(at: 3, in: statement)) ?? .exercises
        let inspectorVisible = sqlite3_column_int(statement, 4) != 0
        let rightSidebarTab = RightSidebarTab(rawValue: string(at: 5, in: statement)) ?? .inspector
        let terminalDisplayMode = TerminalDisplayMode(rawValue: string(at: 7, in: statement)) ?? .split
        let difficultyFilter = optionalString(at: 9, in: statement).flatMap(ExerciseDifficulty.init(rawValue:))

        return WorkspaceSessionState(
            workspaceRootPath: workspaceRootPath,
            selectedExercisePath: optionalString(at: 0, in: statement),
            activeTabPath: optionalString(at: 1, in: statement),
            openTabs: openTabs,
            sidebarMode: sidebarMode,
            isInspectorVisible: inspectorVisible,
            rightSidebarTab: rightSidebarTab,
            rightSidebarWidth: sqlite3_column_double(statement, 6),
            terminalDisplayMode: terminalDisplayMode,
            searchQuery: string(at: 8, in: statement),
            difficultyFilter: difficultyFilter,
            showsOnlyTestExercises: sqlite3_column_int(statement, 10) != 0,
            completionFilter: sqlite3_column_int(statement, 11) != 0 ? .done : .open,
            selectedChatSessionID: optionalString(at: 12, in: statement).flatMap(UUID.init(uuidString:))
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
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(at: 0, in: statement)) else {
                continue
            }

            result.append(
                ExerciseChatSession(
                    id: id,
                    workspaceRootPath: string(at: 1, in: statement),
                    exercisePath: string(at: 2, in: statement),
                    title: string(at: 3, in: statement),
                    providerKind: AIProviderKind(rawValue: string(at: 4, in: statement)) ?? .codexCLI,
                    model: string(at: 5, in: statement),
                    backendSessionID: optionalString(at: 6, in: statement),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
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
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(at: 0, in: statement)),
                  let resolvedSessionID = UUID(uuidString: string(at: 1, in: statement))
            else {
                continue
            }

            result.append(
                ExerciseChatMessage(
                    id: id,
                    sessionID: resolvedSessionID,
                    role: ExerciseChatRole(rawValue: string(at: 2, in: statement)) ?? .assistant,
                    content: string(at: 3, in: statement),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    status: ExerciseChatMessageStatus(rawValue: string(at: 5, in: statement)) ?? .complete,
                    metadataJSON: optionalString(at: 6, in: statement)
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

    private func string(at index: Int32, in statement: OpaquePointer?) -> String {
        String(cString: sqlite3_column_text(statement, index))
    }

    private func optionalString(at index: Int32, in statement: OpaquePointer?) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
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
