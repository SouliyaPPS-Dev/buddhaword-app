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

    final results = await db.query(
      'main',
      where: 'content LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'CAST(volume AS INTEGER), CAST(page AS INTEGER)',
      limit: _searchResultLimit,
    );

    return results.map((row) {
      return EtipitakaSearchResult(
        volume: int.tryParse(row['volume']?.toString() ?? '') ?? 0,
        page: int.tryParse(row['page']?.toString() ?? '') ?? 0,
        items: row['items']?.toString() ?? '',
        content: row['content']?.toString() ?? '',
      );
    }).toList();
  }

  Future<String?> getContent(String code, int volume, int page) async {
    final db = await _openDb(code);

    final volumeStr = volume.toString().padLeft(2, '0');
    final pageStr = page.toString().padLeft(4, '0');

    final results = await db.query(
      'main',
      columns: ['content'],
      where: 'volume = ? AND page = ?',
      whereArgs: [volumeStr, pageStr],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return results.first['content']?.toString();
  }

  Future<EtipitakaSearchResult?> getByVolumePage(
      String code, int volume, int page) async {
    final db = await _openDb(code);

    final volumeStr = volume.toString().padLeft(2, '0');
    final pageStr = page.toString().padLeft(4, '0');

    final results = await db.query(
      'main',
      where: 'volume = ? AND page = ?',
      whereArgs: [volumeStr, pageStr],
      limit: 1,
    );

    if (results.isEmpty) return null;
    final row = results.first;
    return EtipitakaSearchResult(
      volume: int.tryParse(row['volume']?.toString() ?? '') ?? 0,
      page: int.tryParse(row['page']?.toString() ?? '') ?? 0,
      items: row['items']?.toString() ?? '',
      content: row['content']?.toString() ?? '',
    );
  }

  Future<int> getTotalPages(String code, int volume) async {
    final db = await _openDb(code);

    final volumeStr = volume.toString().padLeft(2, '0');
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM main WHERE volume = ?',
      [volumeStr],
    );
    return result.first['cnt'] as int? ?? 0;
  }
}
