import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'database_repository.dart';

class SqliteDatabaseRepository implements DatabaseRepository {
  Database? _db;

  @override
  Future<void> initialize() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'vigyan_transcribe.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE speaker_tags (
            signature TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE transcripts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            signature TEXT NOT NULL,
            language TEXT NOT NULL,
            timestamp INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  @override
  Future<void> saveSpeakerTag(String signature, String name) async {
    await _db?.insert(
      'speaker_tags',
      {
        'signature': signature,
        'name': name,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<String?> getSpeakerName(String signature) async {
    final maps = await _db?.query(
      'speaker_tags',
      where: 'signature = ?',
      whereArgs: [signature],
    );
    if (maps != null && maps.isNotEmpty) {
      return maps.first['name'] as String;
    }
    return null;
  }

  @override
  Future<Map<String, String>> getAllSpeakerTags() async {
    final maps = await _db?.query('speaker_tags');
    if (maps == null) return {};
    return {
      for (final row in maps) row['signature'] as String: row['name'] as String,
    };
  }

  @override
  Future<void> saveTranscript(String text, String signature, String language, int timestamp) async {
    await _db?.insert('transcripts', {
      'text': text,
      'signature': signature,
      'language': language,
      'timestamp': timestamp,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getSessionTranscripts() async {
    // Join transcripts with speaker names
    return await _db?.rawQuery('''
      SELECT t.*, IFNULL(s.name, 'Speaker ' || SUBSTR(t.signature, 1, 4)) as speaker_name
      FROM transcripts t
      LEFT JOIN speaker_tags s ON t.signature = s.signature
      ORDER BY t.timestamp ASC
    ''') ?? [];
  }

  @override
  Future<void> close() async {
    await _db?.close();
  }
}
