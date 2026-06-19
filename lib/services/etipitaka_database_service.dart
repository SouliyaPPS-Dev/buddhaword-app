import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class EtipitakaSearchResult {
  final int volume;
  final int page;
  final String items;
  final String content;

  EtipitakaSearchResult({
    required this.volume,
    required this.page,
    required this.items,
    required this.content,
  });
}

class EtipitakaDatabaseService {
  static final EtipitakaDatabaseService _instance =
      EtipitakaDatabaseService._internal();
  factory EtipitakaDatabaseService() => _instance;
  EtipitakaDatabaseService._internal();

  static const Map<String, String> _assetMap = {
    'thai': 'thai.sqlite.gz',
    'pali': 'pali.sqlite.gz',
    'thaimm': 'thaimm.sqlite.gz',
    'thaimc': 'thaimc.sqlite.gz',
    'thaipb': 'thaipb.sqlite.gz',
    'thaibt': 'thaibt.sqlite.gz',
    'thaiwn': 'thaiwn.sqlite.gz',
    'thaict': 'thaict.sqlite.gz',
    'romanct': 'romanct.sqlite.gz',
    'palimc': 'palimc.sqlite.gz',
    'thaims': 'thaims.sqlite.gz',
    'thaivn': 'thaivn.sqlite.gz',
    'palinew': 'palinew.sqlite.gz',
  };

  static const Map<String, String> _labelMap = {
    'thai': 'ไทย (ฉบับหลวง)',
    'pali': 'บาลี (สยามรัฐ)',
    'thaimm': 'ไทย (มหามกุฏฯ)',
    'thaimc': 'ไทย (มหาจุฬาฯ)',
    'thaipb': 'พุทธวจน-หมวดธรรม',
    'thaibt': 'ชุดจากพระโอษฐ์ ๕ เล่ม',
    'thaiwn': 'ไทย (wn)',
    'thaict': 'ไทย (ct)',
    'romanct': 'โรมัน (ct)',
    'palimc': 'บาลี (mc)',
    'thaims': 'ไทย (ms)',
    'thaivn': 'ไทย (vn)',
    'palinew': 'บาลี (new)',
  };

  final Map<String, Database> _databases = {};
  final Map<String, String> _tableNames = {};
  final Map<String, Map<String, String>> _colMap = {};
  String? _appDir;

  Future<String> get _appDocumentsDir async {
    if (_appDir != null) return _appDir!;
    final dir = await getApplicationDocumentsDirectory();
    _appDir = dir.path;
    return _appDir!;
  }

  bool isCodeAvailable(String code) => _assetMap.containsKey(code);

  String? labelForCode(String code) => _labelMap[code];

  List<String> getAvailableCodes() => _assetMap.keys.toList();

  Future<Database> _openDb(String code) async {
    if (_databases.containsKey(code)) return _databases[code]!;

    final dir = await _appDocumentsDir;
    final dbPath = '$dir/$code.sqlite';

    final file = File(dbPath);
    if (!file.existsSync()) {
      final assetPath = _assetMap[code];
      if (assetPath == null) {
        throw Exception('Unknown edition code: $code');
      }
      final compressedData =
          await rootBundle.load('assets/databases/$assetPath');
      final bytes = await Isolate.run(
        () => GZipCodec().decode(compressedData.buffer.asUint8List()),
      );
      await file.writeAsBytes(bytes);
    }

    try {
      final db = await openDatabase(dbPath, readOnly: true);
      _databases[code] = db;
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT IN ('android_metadata', 'sqlite_sequence') AND name NOT LIKE 'sqlite_%'",
      );

      String tableName = 'main';
      Map<String, String> mapping = {};
      for (final row in tables) {
        final name = row['name'] as String;
        final cols = await db.rawQuery("PRAGMA table_info($name)");
        final colNames = cols.map((c) => c['name'] as String).toList();

        mapping['content'] = colNames.contains('content') ? 'content' : '';
        mapping['page'] = colNames.contains('page') ? 'page' : '';
        if (colNames.contains('volume')) {
          mapping['volume'] = 'volume';
        } else if (colNames.contains('book')) {
          mapping['volume'] = 'book';
        } else {
          mapping['volume'] = '';
        }
        if (colNames.contains('items')) {
          mapping['items'] = 'items';
        } else if (colNames.contains('title')) {
          mapping['items'] = 'title';
        } else {
          mapping['items'] = '';
        }

        if (mapping['content']!.isNotEmpty) {
          tableName = name;
          break;
        }
      }
      _tableNames[code] = tableName;
      _colMap[code] = mapping;
      return db;
    } catch (e) {
      if (file.existsSync()) {
        await file.delete();
      }
      _databases.remove(code);
      rethrow;
    }
  }

  static const int _searchResultLimit = 200;

  Future<List<EtipitakaSearchResult>> search(
      String code, String query) async {
    final db = await _openDb(code);
    final table = _tableNames[code] ?? 'main';
    final map = _colMap[code] ?? <String, String>{};

    final volumeCol = map['volume'] ?? '';
    final pageCol = map['page'] ?? '';
    final itemsCol = map['items'] ?? '';
    final contentCol = map['content'] ?? 'content';
    final hasVolumeAndPage = volumeCol.isNotEmpty && pageCol.isNotEmpty;

    final results = await db.query(
      table,
      where: '$contentCol LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: hasVolumeAndPage
          ? 'CAST($volumeCol AS INTEGER), CAST($pageCol AS INTEGER)'
          : null,
      limit: _searchResultLimit,
    );

    return results.map((row) {
      return EtipitakaSearchResult(
        volume: volumeCol.isNotEmpty
            ? int.tryParse(row[volumeCol]?.toString() ?? '') ?? 0
            : 0,
        page: pageCol.isNotEmpty
            ? int.tryParse(row[pageCol]?.toString() ?? '') ?? 0
            : 0,
        items: itemsCol.isNotEmpty ? row[itemsCol]?.toString() ?? '' : '',
        content: row[contentCol]?.toString() ?? '',
      );
    }).toList();
  }

  Future<String?> getContent(String code, int volume, int page) async {
    final db = await _openDb(code);
    final table = _tableNames[code] ?? 'main';
    final map = _colMap[code] ?? <String, String>{};

    final volumeCol = map['volume'] ?? '';
    final pageCol = map['page'] ?? '';
    final contentCol = map['content'] ?? 'content';
    if (volumeCol.isEmpty || pageCol.isEmpty) return null;

    final results = await db.rawQuery(
      'SELECT $contentCol FROM $table WHERE CAST($volumeCol AS INTEGER) = ? AND CAST($pageCol AS INTEGER) = ? LIMIT 1',
      [volume, page],
    );

    if (results.isEmpty) return null;
    return results.first[contentCol]?.toString();
  }

  Future<EtipitakaSearchResult?> getByVolumePage(
      String code, int volume, int page) async {
    final db = await _openDb(code);
    final table = _tableNames[code] ?? 'main';
    final map = _colMap[code] ?? <String, String>{};

    final volumeCol = map['volume'] ?? '';
    final pageCol = map['page'] ?? '';
    final itemsCol = map['items'] ?? '';
    final contentCol = map['content'] ?? 'content';
    if (volumeCol.isEmpty || pageCol.isEmpty) return null;

    final results = await db.rawQuery(
      'SELECT * FROM $table WHERE CAST($volumeCol AS INTEGER) = ? AND CAST($pageCol AS INTEGER) = ? LIMIT 1',
      [volume, page],
    );

    if (results.isEmpty) return null;
    final row = results.first;
    return EtipitakaSearchResult(
      volume: int.tryParse(row[volumeCol]?.toString() ?? '') ?? 0,
      page: int.tryParse(row[pageCol]?.toString() ?? '') ?? 0,
      items: itemsCol.isNotEmpty ? row[itemsCol]?.toString() ?? '' : '',
      content: row[contentCol]?.toString() ?? '',
    );
  }

  Future<int> getTotalPages(String code, int volume) async {
    final db = await _openDb(code);
    final table = _tableNames[code] ?? 'main';
    final map = _colMap[code] ?? <String, String>{};

    final volumeCol = map['volume'] ?? '';
    if (volumeCol.isEmpty) return 0;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM $table WHERE CAST($volumeCol AS INTEGER) = ?',
      [volume],
    );
    return result.first['cnt'] as int? ?? 0;
  }
}
