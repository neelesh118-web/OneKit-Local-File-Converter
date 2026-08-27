import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../engine/job.dart';

/// One completed (or failed) conversion, as recorded locally.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.name,
    required this.fromExt,
    required this.toExt,
    required this.status,
    required this.createdAt,
    this.outputPath,
    this.outputBytes = 0,
    this.sourceBytes = 0,
    this.elapsedMs = 0,
    this.error,
    this.extraCount = 0,
  });

  final int id;
  final String name;
  final String fromExt;
  final String toExt;
  final String status;
  final DateTime createdAt;
  final String? outputPath;
  final int outputBytes;
  final int sourceBytes;
  final int elapsedMs;
  final String? error;

  /// How many additional files the conversion produced (multi-page renders).
  final int extraCount;

  bool get succeeded => status == 'done';
  String get pairLabel => '${fromExt.toUpperCase()} → ${toExt.toUpperCase()}';
  Duration get elapsed => Duration(milliseconds: elapsedMs);

  Map<String, Object?> toMap() => {
        'name': name,
        'from_ext': fromExt,
        'to_ext': toExt,
        'status': status,
        'created_at': createdAt.millisecondsSinceEpoch,
        'output_path': outputPath,
        'output_bytes': outputBytes,
        'source_bytes': sourceBytes,
        'elapsed_ms': elapsedMs,
        'error': error,
        'extra_count': extraCount,
      };

  static HistoryEntry fromMap(Map<String, Object?> m) => HistoryEntry(
        id: m['id'] as int,
        name: m['name'] as String,
        fromExt: m['from_ext'] as String,
        toExt: m['to_ext'] as String,
        status: m['status'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        outputPath: m['output_path'] as String?,
        outputBytes: (m['output_bytes'] as int?) ?? 0,
        sourceBytes: (m['source_bytes'] as int?) ?? 0,
        elapsedMs: (m['elapsed_ms'] as int?) ?? 0,
        error: m['error'] as String?,
        extraCount: (m['extra_count'] as int?) ?? 0,
      );
}

/// Local conversion history and pair usage counts. Everything stays in an
/// app-private SQLite file; nothing is uploaded.
class HistoryStore extends ChangeNotifier {
  HistoryStore._();
  static final HistoryStore instance = HistoryStore._();

  Database? _db;

  Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'onekit_history.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            from_ext TEXT NOT NULL,
            to_ext TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            output_path TEXT,
            output_bytes INTEGER DEFAULT 0,
            source_bytes INTEGER DEFAULT 0,
            elapsed_ms INTEGER DEFAULT 0,
            error TEXT,
            extra_count INTEGER DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_history_created ON history(created_at DESC)');
        await db.execute('''
          CREATE TABLE pair_usage (
            pair_id TEXT PRIMARY KEY,
            uses INTEGER NOT NULL DEFAULT 0,
            last_used INTEGER NOT NULL
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  Future<void> record(ConversionJob job) async {
    final db = await _database;
    final entry = HistoryEntry(
      id: 0,
      name: job.name,
      fromExt: job.source?.ext ?? p.extension(job.sourcePath).replaceFirst('.', ''),
      toExt: job.target.ext,
      status: job.status.name,
      createdAt: DateTime.now(),
      outputPath: job.outputPath,
      outputBytes: job.outputBytes,
      sourceBytes: job.sourceBytes,
      elapsedMs: job.elapsed.inMilliseconds,
      error: job.error,
      extraCount: job.extraOutputs.length,
    );
    await db.insert('history', entry.toMap());

    if (job.status == JobStatus.done && job.source != null) {
      final id = '${job.source!.ext}>${job.target.ext}';
      await db.rawInsert(
        '''INSERT INTO pair_usage (pair_id, uses, last_used) VALUES (?, 1, ?)
           ON CONFLICT(pair_id) DO UPDATE SET uses = uses + 1, last_used = ?''',
        [id, DateTime.now().millisecondsSinceEpoch, DateTime.now().millisecondsSinceEpoch],
      );
    }
    notifyListeners();
  }

  Future<List<HistoryEntry>> recent({int limit = 200, String? filter}) async {
    final db = await _database;
    final rows = await db.query(
      'history',
      where: filter == null || filter.isEmpty
          ? null
          : 'name LIKE ? OR from_ext LIKE ? OR to_ext LIKE ?',
      whereArgs: filter == null || filter.isEmpty
          ? null
          : ['%$filter%', '%$filter%', '%$filter%'],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(HistoryEntry.fromMap).toList();
  }

  /// Pair ids ordered by how often this user has actually run them.
  Future<List<String>> favouritePairIds({int limit = 12}) async {
    final db = await _database;
    final rows = await db.query(
      'pair_usage',
      orderBy: 'uses DESC, last_used DESC',
      limit: limit,
    );
    return [for (final r in rows) r['pair_id'] as String];
  }

  Future<({int total, int succeeded, int bytesSaved})> stats() async {
    final db = await _database;
    final total = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM history')) ?? 0;
    final ok = Sqflite.firstIntValue(
          await db.rawQuery("SELECT COUNT(*) FROM history WHERE status = 'done'"),
        ) ??
        0;
    final saved = Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COALESCE(SUM(source_bytes - output_bytes), 0) FROM history WHERE status = 'done' AND output_bytes > 0 AND source_bytes > output_bytes",
          ),
        ) ??
        0;
    return (total: total, succeeded: ok, bytesSaved: saved);
  }

  Future<void> delete(int id, {bool alsoDeleteFile = false}) async {
    final db = await _database;
    if (alsoDeleteFile) {
      final rows = await db.query('history', columns: ['output_path'], where: 'id = ?', whereArgs: [id]);
      final path = rows.firstOrNull?['output_path'] as String?;
      if (path != null) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    }
    await db.delete('history', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> clear() async {
    final db = await _database;
    await db.delete('history');
    notifyListeners();
  }
}
