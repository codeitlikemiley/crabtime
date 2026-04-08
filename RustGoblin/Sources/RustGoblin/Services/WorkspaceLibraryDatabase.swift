import Foundation
import SQLite3

final class WorkspaceLibraryDatabase {
    private let fileManager: FileManager
    private var database: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(paths: AppStoragePaths, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        try paths.ensureDirectories(fileManager: fileManager)

        guard sqlite3_open(paths.databaseURL.path, &database) == SQLITE_OK else {
            throw DatabaseError.openFailed(message: String(cString: sqlite3_errmsg(database)))
        }

        try execute(
            """
            CREATE TABLE IF NOT EXISTS workspaces (
                root_path TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                source_kind TEXT NOT NULL,
                clone_url TEXT,
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
                search_query TEXT NOT NULL,
                difficulty_filter TEXT,
                last_saved_at REAL NOT NULL
            );
            """
        )

        try? execute(
            """
            ALTER TABLE workspace_state
            ADD COLUMN shows_completed_exercises INTEGER NOT NULL DEFAULT 0;
            """
        )
    }

    deinit {
        sqlite3_close(database)
    }

    func fetchWorkspaces() throws -> [SavedWorkspaceRecord] {
        let statement = try prepare(
            """
            SELECT root_path, title, source_kind, clone_url, added_at, last_opened_at, missing_path
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
                    addedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    lastOpenedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                    isMissing: sqlite3_column_int(statement, 6) != 0
                )
            )
        }

        return records
    }

    func fetchWorkspace(rootPath: String) throws -> SavedWorkspaceRecord? {
        let statement = try prepare(
            """
            SELECT root_path, title, source_kind, clone_url, added_at, last_opened_at, missing_path
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
            addedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
            lastOpenedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
            isMissing: sqlite3_column_int(statement, 6) != 0
        )
    }

    func upsertWorkspace(_ record: SavedWorkspaceRecord) throws {
        let statement = try prepare(
            """
            INSERT INTO workspaces (
                root_path, title, source_kind, clone_url, added_at, last_opened_at, missing_path
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(root_path) DO UPDATE SET
                title = excluded.title,
                source_kind = excluded.source_kind,
                clone_url = excluded.clone_url,
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
        sqlite3_bind_double(statement, 5, record.addedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 6, record.lastOpenedAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 7, record.isMissing ? 1 : 0)

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
            SELECT selected_exercise_path, active_tab_path, open_tabs_json, sidebar_mode, search_query, difficulty_filter, shows_completed_exercises
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
        let difficultyFilter = optionalString(at: 5, in: statement).flatMap(ExerciseDifficulty.init(rawValue:))

        return WorkspaceSessionState(
            workspaceRootPath: workspaceRootPath,
            selectedExercisePath: optionalString(at: 0, in: statement),
            activeTabPath: optionalString(at: 1, in: statement),
            openTabs: openTabs,
            sidebarMode: sidebarMode,
            searchQuery: string(at: 4, in: statement),
            difficultyFilter: difficultyFilter,
            completionFilter: sqlite3_column_int(statement, 6) != 0 ? .done : .open
        )
    }

    func saveWorkspaceState(_ state: WorkspaceSessionState) throws {
        let statement = try prepare(
            """
            INSERT INTO workspace_state (
                workspace_root_path, selected_exercise_path, active_tab_path, open_tabs_json,
                sidebar_mode, search_query, difficulty_filter, shows_completed_exercises, last_saved_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(workspace_root_path) DO UPDATE SET
                selected_exercise_path = excluded.selected_exercise_path,
                active_tab_path = excluded.active_tab_path,
                open_tabs_json = excluded.open_tabs_json,
                sidebar_mode = excluded.sidebar_mode,
                search_query = excluded.search_query,
                difficulty_filter = excluded.difficulty_filter,
                shows_completed_exercises = excluded.shows_completed_exercises,
                last_saved_at = excluded.last_saved_at;
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(state.workspaceRootPath, at: 1, in: statement)
        bind(state.selectedExercisePath, at: 2, in: statement)
        bind(state.activeTabPath, at: 3, in: statement)
        bind(encodeOpenTabs(state.openTabs), at: 4, in: statement)
        bind(state.sidebarMode.rawValue, at: 5, in: statement)
        bind(state.searchQuery, at: 6, in: statement)
        bind(state.difficultyFilter?.rawValue, at: 7, in: statement)
        sqlite3_bind_int(statement, 8, state.completionFilter == .done ? 1 : 0)
        sqlite3_bind_double(statement, 9, Date().timeIntervalSince1970)

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
