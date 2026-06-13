import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart' show AudioPlayer, ProcessingState;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/etipitaka_database_service.dart';
import '../../themes/ThemeProvider.dart';
import 'etipitaka_page.dart';

class EtipitakaContentPage extends StatefulWidget {
  final String title;
  final String code;
  final int volume;
  final int page;
  final List<EtipitakaItem>? results;
  final int? resultIndex;
  final String searchQuery;

  const EtipitakaContentPage({
    super.key,
    required this.title,
    required this.code,
    required this.volume,
    required this.page,
    this.results,
    this.resultIndex,
    this.searchQuery = '',
  });

  @override
  EtipitakaContentPageState createState() => EtipitakaContentPageState();
}

class EtipitakaContentPageState extends State<EtipitakaContentPage> {
  String? _plainText;
  bool _isLoading = true;
  String? _error;
  late int _currentVolume;
  late int _currentPage;
  late String _currentCode;
  String _currentTitle = '';

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isTtsLoading = false;
  bool _ttsActive = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;

  static const String _ttsBaseUrl = 'https://buddhaword-web.hf.space';
  static const int _ttsChunkSize = 1200;
  static const int _maxTtsChars = 50000;

  int _ttsChunkIndex = 0;
  List<String> _ttsChunks = [];
  final List<Uint8List> _ttsChunkBytes = [];
  File? _nextPrefetchedFile;
  int _ttsRunId = 0;
  double _fontSize = 18.0;

  final EtipitakaDatabaseService _dbService = EtipitakaDatabaseService();
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _currentVolume = widget.volume;
    _currentPage = widget.page;
    _currentCode = widget.code;
    _currentTitle = widget.title;
    _fetchContent();
    _loadFontSizeFromSharedPreferences();
  }

  Future<void> _fetchContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final content = await _dbService.getContent(
        _currentCode,
        _currentVolume,
        _currentPage,
      );

      if (mounted) {
        setState(() {
          _plainText = content;
          _isLoading = false;
          if (content == null) {
            _error = 'Content not found';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _goToPrevPage() {
    _stopTts();
    setState(() {
      if (_currentPage > 1) {
        _currentPage--;
      }
    });
    _fetchContent();
  }

  void _goToNextPage() {
    _stopTts();
    setState(() {
      _currentPage++;
    });
    _fetchContent();
  }

  List<String> _extractParagraphs(String text) {
    final lines = text
        .split('\n')
        .expand((line) => line.split('.'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line.length >= 4)
        .toList();

    if (lines.length < 3) {
      final words = text.split(' ').where((w) => w.trim().isNotEmpty).toList();
      final grouped = <String>[];
      for (int i = 0; i < words.length; i += 20) {
        final end = (i + 20 < words.length) ? i + 20 : words.length;
        grouped.add(words.sublist(i, end).join(' '));
      }
      return grouped.where((g) => g.length >= 4).toList();
    }

    return lines;
  }

  void _copyContent() {
    if (_plainText == null) return;
    Clipboard.setData(ClipboardData(text: _plainText!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Content copied to clipboard')),
    );
  }

  String _detectLanguage(String text) {
    int laoCount = 0, thaiCount = 0, engCount = 0;
    for (final rune in text.runes) {
      if (rune >= 0x0E80 && rune <= 0x0EFF) {
        laoCount++;
      } else if (rune >= 0x0E00 && rune <= 0x0E7F) {
        thaiCount++;
      } else if ((rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A)) {
        engCount++;
      }
    }
    if (laoCount > thaiCount && laoCount > engCount) return 'lo-LA';
    if (thaiCount > laoCount && thaiCount > engCount) return 'th-TH';
    return 'en-US';
  }

  List<String> _chunkText(String text) {
    if (text.length <= _ttsChunkSize) return [text];
    final chunks = <String>[];
    int start = 0;
    while (start < text.length) {
      int end = start + _ttsChunkSize;
      if (end >= text.length) {
        chunks.add(text.substring(start).trim());
        break;
      }
      int breakAt = end;
      for (int i = end; i > start + _ttsChunkSize - 200 && i > start; i--) {
        if ('\n'.contains(text[i]) && i + 1 < text.length) {
          breakAt = i + 1;
          break;
        }
      }
      if (breakAt == end) {
        for (int i = end; i > start + _ttsChunkSize - 200 && i > start; i--) {
          if ('.!?:\n'.contains(text[i])) {
            breakAt = i + 1;
            break;
          }
        }
      }
      chunks.add(text.substring(start, breakAt).trim());
      start = breakAt;
    }
    return chunks.where((c) => c.isNotEmpty).toList();
  }

  Future<File?> _fetchTtsChunk(int index, String text) async {
    try {
      final lang = _detectLanguage(text);
      final response = await http.post(
        Uri.parse('$_ttsBaseUrl/api/tts/synthesize'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'text': text, 'language': lang}),
      );
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body);
      if (data['error'] == true) return null;
      final audioBytes = base64.decode(data['audioContent']);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/tts_${index}_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await file.writeAsBytes(audioBytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  void _setupTtsListeners() {
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();

    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
      });
      if (state.processingState == ProcessingState.completed && _ttsActive) {
        _advanceToNextChunk();
      }
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration ?? Duration.zero;
        });
      }
    });
    _positionSubscription = _player.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });
  }

  Future<void> _advanceToNextChunk() async {
    _ttsChunkIndex++;
    if (_ttsChunkIndex >= _ttsChunks.length) {
      if (mounted) {
        setState(() {
          _ttsActive = false;
          _isPlaying = false;
        });
      }
      return;
    }

    final file = _nextPrefetchedFile;
    _nextPrefetchedFile = null;
    if (file == null || !_ttsActive) return;

    file.readAsBytes().then((bytes) {
      _ttsChunkBytes.add(bytes);
    });
    _player.setFilePath(file.path).then((_) {
      _player.setSpeed(0.85);
      _player.play();
    });
    try {
      await file.delete();
    } catch (_) {}
    _prefetchChunk(_ttsChunkIndex + 1);
  }

  void _prefetchChunk(int index) {
    if (index >= _ttsChunks.length) return;
    _fetchTtsChunk(index, _ttsChunks[index]).then((file) {
      if (file != null && _ttsActive && _ttsChunkIndex + 1 == index) {
        _nextPrefetchedFile = file;
      }
    });
  }

  Future<void> _speakContent() async {
    if (_plainText == null) return;
    if (_ttsActive) {
      _stopTts();
      return;
    }

    final text = _plainText!;
    if (text.length > _maxTtsChars) return;

    _ttsRunId++;
    final runId = _ttsRunId;
    _ttsChunkBytes.clear();
    _nextPrefetchedFile = null;
    _ttsChunks = _chunkText(text);

    if (_ttsChunks.isEmpty) return;
    _ttsChunkIndex = 0;

    if (mounted) {
      setState(() {
        _ttsActive = true;
        _isTtsLoading = true;
      });
    }

    _setupTtsListeners();

    final firstFile = await _fetchTtsChunk(0, _ttsChunks[0]);
    if (firstFile == null || runId != _ttsRunId || !mounted || !_ttsActive) {
      if (mounted) {
        setState(() {
          _ttsActive = false;
          _isTtsLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isTtsLoading = false;
      });
    }
    _ttsChunkBytes.add(await firstFile.readAsBytes());
    await _player.setFilePath(firstFile.path);
    await _player.setSpeed(0.85);
    await _player.play();
    try {
      await firstFile.delete();
    } catch (_) {}
    _prefetchChunk(1);
  }

  void _stopTts() {
    _ttsActive = false;
    _ttsRunId++;
    _ttsChunks = [];
    _ttsChunkBytes.clear();
    _nextPrefetchedFile = null;
    _player.stop();
    setState(() {
      _isPlaying = false;
      _isTtsLoading = false;
    });
  }

  Future<void> _downloadAudio() async {
    if (_ttsChunkBytes.isEmpty) return;
    final dir = await getTemporaryDirectory();
    final fileName = 'etipitaka_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final file = File('${dir.path}/$fileName');
    final allBytes = <int>[];
    for (final bytes in _ttsChunkBytes) {
      allBytes.addAll(bytes);
    }
    await file.writeAsBytes(allBytes);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved: $fileName')));
    }
  }

  @override
  void dispose() {
    _ttsRunId++;
    _ttsActive = false;
    _player.stop();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _player.dispose();
    _ttsChunks = [];
    _nextPrefetchedFile = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullScreen
          ? PreferredSize(
              preferredSize: Size.zero,
              child: const SizedBox.shrink(),
            )
          : AppBar(
              backgroundColor: Colors.brown,
              title: Text(
                _currentTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () {
                  _stopTts();
                  Navigator.of(context).pop();
                },
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.fullscreen, color: Colors.white),
                  onPressed: () => setState(() => _isFullScreen = true),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white),
                  tooltip: 'Copy content',
                  onPressed: _plainText != null ? () => _copyContent() : null,
                ),
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
                    return IconButton(
                      icon: Text(
                        themeProvider.isDarkMode ? "☀️" : "🌙",
                        style: const TextStyle(fontSize: 16),
                      ),
                      onPressed: () =>
                          themeProvider.toggleTheme(!themeProvider.isDarkMode),
                    );
                  },
                ),
              ],
            ),
      body: Stack(
        children: [
          _buildBody(),
          if (_isFullScreen)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: GestureDetector(
                onTap: () => setState(() => _isFullScreen = false),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.black26,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fullscreen_exit,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _isFullScreen
          ? null
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FloatingActionButton(
                    heroTag: 'fab_prev',
                    onPressed: _isLoading ? null : _goToPrevPage,
                    backgroundColor: const Color(0xFFF5F5F5),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Color.fromARGB(241, 179, 93, 78),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FloatingActionButton(
                    heroTag: 'fab_minus',
                    onPressed: _decreaseFontSize,
                    backgroundColor: const Color(0xFFF5F5F5),
                    child: const Icon(
                      Icons.remove,
                      color: Color.fromARGB(241, 179, 93, 78),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FloatingActionButton(
                    heroTag: 'fab_plus',
                    onPressed: _increaseFontSize,
                    backgroundColor: const Color(0xFFF5F5F5),
                    child: const Icon(
                      Icons.add,
                      color: Color.fromARGB(241, 179, 93, 78),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FloatingActionButton(
                    heroTag: 'fab_volume',
                    onPressed: _isTtsLoading ? null : _speakContent,
                    backgroundColor: _ttsActive
                        ? Colors.brown
                        : const Color(0xFFF5F5F5),
                    child: _isTtsLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.brown,
                            ),
                          )
                        : Icon(
                            _ttsActive ? Icons.stop : Icons.volume_up,
                            color: _ttsActive
                                ? Colors.white
                                : const Color.fromARGB(241, 179, 93, 78),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FloatingActionButton(
                    heroTag: 'fab_next',
                    onPressed: _isLoading ? null : _goToNextPage,
                    backgroundColor: const Color(0xFFF5F5F5),
                    child: const Icon(
                      Icons.arrow_forward,
                      color: Color.fromARGB(241, 179, 93, 78),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: Colors.red)),
            SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchContent, child: Text('Retry')),
          ],
        ),
      );
    }

    if (_plainText == null || _plainText!.isEmpty) {
      return const Center(child: Text('No content'));
    }

    final paragraphs = _extractParagraphs(_plainText!);
    if (paragraphs.isEmpty) {
      return const Center(child: Text('No text content'));
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! > 0) {
          _goToPrevPage();
        } else if (details.primaryVelocity! < 0) {
          _goToNextPage();
        }
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: Text(
              'เล่มที่ $_currentVolume หน้า $_currentPage',
              style: TextStyle(
                fontSize: 14,
                color: Colors.brown,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: paragraphs.map((text) {
                final isHeading = text.length < 60;
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: SelectableText.rich(
                    _buildHighlightedSpan(text),
                    showCursor: true,
                    style: TextStyle(
                      fontSize: _fontSize,
                      fontWeight: isHeading
                          ? FontWeight.bold
                          : FontWeight.normal,
                      height: 1.6,
                      letterSpacing: 0.3,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (_ttsActive || _isTtsLoading)
            Container(
              color: Colors.brown.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.brown,
                    ),
                    onPressed: () async {
                      if (_isPlaying) {
                        await _player.pause();
                      } else {
                        await _player.play();
                      }
                    },
                  ),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: _duration.inMilliseconds.toDouble().clamp(
                        1,
                        double.infinity,
                      ),
                      value: _position.inMilliseconds.toDouble().clamp(
                        0,
                        _duration.inMilliseconds.toDouble(),
                      ),
                      onChanged: (v) =>
                          _player.seek(Duration(milliseconds: v.toInt())),
                    ),
                  ),
                  Text(
                    '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                    style: TextStyle(fontSize: 11, color: Colors.brown),
                  ),
                  SizedBox(width: 4),
                  if (_ttsChunkBytes.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.download, color: Colors.brown, size: 20),
                      onPressed: _downloadAudio,
                      constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                    ),
                  IconButton(
                    icon: Icon(Icons.stop, color: Colors.red, size: 20),
                    onPressed: _stopTts,
                    constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _increaseFontSize() {
    setState(() => _fontSize += 2.0);
    _saveFontSizeToSharedPreferences(_fontSize);
  }

  void _decreaseFontSize() {
    setState(() => _fontSize = _fontSize > 2.0 ? _fontSize - 2.0 : _fontSize);
    _saveFontSizeToSharedPreferences(_fontSize);
  }

  Future<void> _loadFontSizeFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final double? saved = prefs.getDouble('fontSize');
    if (saved != null && mounted) {
      setState(() => _fontSize = saved);
    }
  }

  Future<void> _saveFontSizeToSharedPreferences(double fontSize) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', fontSize);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  TextSpan _buildHighlightedSpan(String text) {
    final query = widget.searchQuery;
    if (query.isEmpty) {
      return TextSpan(text: text);
    }
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final qLower = query.toLowerCase();
    int start = 0;
    int idx = lower.indexOf(qLower, start);
    while (idx != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + query.length),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.orange.shade800,
            backgroundColor: Colors.yellow.withValues(alpha: 0.3),
          ),
        ),
      );
      start = idx + query.length;
      idx = lower.indexOf(qLower, start);
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return TextSpan(children: spans);
  }
}
