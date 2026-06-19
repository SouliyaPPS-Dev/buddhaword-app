import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart' show AudioPlayer, ProcessingState;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
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
  List<int> _ttsChunkEnds = [];
  final List<Uint8List> _ttsChunkBytes = [];
  File? _nextPrefetchedFile;
  int _ttsRunId = 0;
  double _fontSize = 18.0;
  List<_WordRange> _ttsWords = [];
  int _ttsCurrentWordIndex = -1;
  List<int> _ttsParagraphOffsets = [];

  final EtipitakaDatabaseService _dbService = EtipitakaDatabaseService();
  bool _isFullScreen = false;
  bool _isFavorited = false;

  @override
  void initState() {
    super.initState();
    _currentVolume = widget.volume;
    _currentPage = widget.page;
    _currentCode = widget.code;
    _currentTitle = widget.title;
    _fetchContent();
    _loadFontSizeFromSharedPreferences();
    _loadFavoriteState();
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
          _plainText = content != null ? _cleanText(content) : null;
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
      _currentTitle = 'เล่มที่ $_currentVolume หน้า $_currentPage';
    });
    _fetchContent();
    _loadFavoriteState();
  }

  void _goToNextPage() {
    _stopTts();
    setState(() {
      _currentPage++;
      _currentTitle = 'เล่มที่ $_currentVolume หน้า $_currentPage';
    });
    _fetchContent();
    _loadFavoriteState();
  }

  String _cleanText(String text) {
    final buf = StringBuffer();
    for (final r in text.runes) {
      if (r == 0x09 || r == 0x0A || r == 0x0D) {
        buf.writeCharCode(r);
        continue;
      }
      if (r <= 0x1F || (r >= 0x7F && r <= 0x9F)) continue;
      if (r == 0x00AD || r == 0x200B || r == 0x200C || r == 0x200D || r == 0xFEFF) continue;
      if (r == 0x0E3F || (r >= 0x0E01 && r <= 0x0E3A) || (r >= 0x0E40 && r <= 0x0E5B) || (r >= 0x0E50 && r <= 0x0E59)) {
        buf.writeCharCode(r);
        continue;
      }
      if (r >= 0x20 && r <= 0x7E) {
        buf.writeCharCode(r);
        continue;
      }
      if (r >= 0x0E00 && r <= 0x0E7F) {
        buf.writeCharCode(r);
        continue;
      }
    }
    return buf.toString();
  }

  List<String> _extractParagraphs(String text) {
    final lines = text
        .split('\n')
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

  void _shareContent() {
    if (_plainText == null) return;
    final href = 'https://buddhaword-web.hf.space/etipitaka/$_currentCode/$_currentVolume/$_currentPage';
    final shareText = '$_currentTitle\n$href';
    SharePlus.instance.share(
      ShareParams(text: shareText, subject: _currentTitle),
    );
  }

  Future<void> _loadFavoriteState() async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList('favorites') ?? [];
    final identifier = '${_currentCode}_v${_currentVolume}_p$_currentPage';
    if (!mounted) return;
    setState(() {
      _isFavorited = favorites.any((fav) {
        try {
          final data = json.decode(fav) as Map<String, dynamic>;
          return data['id'] == identifier;
        } catch (_) {
          return false;
        }
      });
    });
  }

  Future<void> _toggleFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    final identifier = '${_currentCode}_v${_currentVolume}_p$_currentPage';
    final favorites = List<String>.from(prefs.getStringList('favorites') ?? []);

    if (_isFavorited) {
      favorites.removeWhere((fav) {
        try {
          final data = json.decode(fav) as Map<String, dynamic>;
          return data['id'] == identifier;
        } catch (_) {
          return false;
        }
      });
    } else {
      final item = json.encode({
        'id': identifier,
        'title': _currentTitle,
        'audio': '/',
        'details': _plainText ?? '',
        'category': 'etipitaka',
        'image': '',
      });
      favorites.add(item);
    }

    await prefs.setStringList('favorites', favorites);
    setState(() => _isFavorited = !_isFavorited);
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
          _updateTtsWordIndex();
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
    if (_isTtsLoading) return;
    if (_plainText == null) return;
    if (_ttsActive) {
      _stopTts();
      return;
    }

    final text = _plainText!;
    if (text.length > _maxTtsChars) return;
    final paragraphs = _extractParagraphs(text);
    if (paragraphs.isEmpty) return;
    final ttsText = paragraphs.join('\n');

    _ttsWords = _buildWordRanges(ttsText);
    _ttsCurrentWordIndex = -1;
    _ttsParagraphOffsets = [];
    int offset = 0;
    for (final p in paragraphs) {
      _ttsParagraphOffsets.add(offset);
      offset += p.length + 1;
    }

    _ttsRunId++;
    final runId = _ttsRunId;
    _ttsChunkBytes.clear();
    _nextPrefetchedFile = null;
    _ttsChunks = _chunkText(ttsText);

    // Reconstruct original end positions (reverse .trim() from _chunkText)
    _ttsChunkEnds = [];
    int pos = 0;
    for (final chunk in _ttsChunks) {
      final found = ttsText.indexOf(chunk, pos);
      if (found == -1) {
        pos += chunk.length;
      } else {
        pos = found + chunk.length;
      }
      _ttsChunkEnds.add(pos);
    }

    if (_ttsChunks.isEmpty) return;
    _ttsChunkIndex = 0;

    if (mounted) {
      setState(() {
        _ttsActive = true;
        _isTtsLoading = true;
      });
    }

    await Future.delayed(Duration.zero);

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
    _ttsChunkEnds = [];
    _ttsChunkBytes.clear();
    _nextPrefetchedFile = null;
    _player.stop();
    setState(() {
      _isPlaying = false;
      _isTtsLoading = false;
      _ttsWords = [];
      _ttsCurrentWordIndex = -1;
      _ttsParagraphOffsets = [];
    });
  }

  List<_WordRange> _buildWordRanges(String text) {
    final ranges = <_WordRange>[];
    int start = -1;
    for (int i = 0; i < text.length; i++) {
      if (text[i] == ' ' || text[i] == '\n' || text[i] == '\t' || text[i] == '\r') {
        if (start >= 0) {
          ranges.add(_WordRange(start, i));
          start = -1;
        }
      } else {
        if (start < 0) start = i;
      }
    }
    if (start >= 0) {
      ranges.add(_WordRange(start, text.length));
    }
    return ranges;
  }

  void _updateTtsWordIndex() {
    if (_ttsWords.isEmpty) return;
    if (_ttsChunkEnds.isEmpty || _duration.inMilliseconds <= 0) return;

    final chunkEnd = _ttsChunkIndex < _ttsChunkEnds.length
        ? _ttsChunkEnds[_ttsChunkIndex]
        : _ttsWords.last.end;
    final chunkStart = _ttsChunkIndex > 0 && _ttsChunkIndex <= _ttsChunkEnds.length
        ? _ttsChunkEnds[_ttsChunkIndex - 1]
        : 0;
    final chunkLength = chunkEnd - chunkStart;

    final progress = _position.inMilliseconds / _duration.inMilliseconds;
    final charOffset = chunkStart + (progress * chunkLength).round();

    int newIndex = -1;
    for (int i = 0; i < _ttsWords.length; i++) {
      if (charOffset >= _ttsWords[i].start && charOffset < _ttsWords[i].end) {
        newIndex = i;
        break;
      }
    }
    if (newIndex > _ttsCurrentWordIndex) {
      _ttsCurrentWordIndex = newIndex;
    }
  }

  Widget _buildTtsHighlightedParagraph(String text, int paragraphIndex) {
    if (paragraphIndex >= _ttsParagraphOffsets.length) {
      return SelectableText.rich(TextSpan(text: text));
    }
    final offset = _ttsParagraphOffsets[paragraphIndex];
    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (int i = 0; i < _ttsWords.length; i++) {
      final r = _ttsWords[i];
      if (r.end <= offset) continue;
      if (r.start >= offset + text.length) break;
      final localStart = r.start - offset;
      final localEnd = r.end - offset;
      if (localStart > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, localStart)));
      }
      final wordText = text.substring(localStart, localEnd);
      final isCurrent = i == _ttsCurrentWordIndex;
      spans.add(TextSpan(
        text: wordText,
        style: TextStyle(
          backgroundColor: isCurrent ? Colors.yellow : null,
          color: isCurrent && context.read<ThemeProvider>().isDarkMode ? Colors.black : null,
          fontWeight: isCurrent ? FontWeight.bold : null,
        ),
      ));
      lastEnd = localEnd;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return SelectableText.rich(
      TextSpan(children: spans),
      showCursor: true,
    );
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
    _ttsChunkEnds = [];
    _nextPrefetchedFile = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.watch<ThemeProvider>().isDarkMode ? Colors.black : Color.fromRGBO(246, 238, 217, 1.0),
      drawer: const custom_nav.NavigationDrawer(),
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
                  icon: Icon(
                    _isFavorited ? Icons.favorite : Icons.favorite_border,
                    color: Colors.white,
                  ),
                  onPressed: _toggleFavorite,
                ),
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu_open, color: Colors.white),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
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
          Column(
            children: [
              Expanded(child: _buildBody()),
              _buildTtsBar(),
            ],
          ),
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _isFullScreen
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: (_ttsActive || _isTtsLoading) ? 60 : 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFAB(Icons.add, _increaseFontSize, 'fab1'),
                  const SizedBox(width: 12),
                  _buildFAB(Icons.remove, _decreaseFontSize, 'fab2'),
                  const SizedBox(width: 12),
                  _buildFAB(Icons.content_copy, _copyContent, 'fab3'),
                  const SizedBox(width: 12),
                  _buildFAB(Icons.share, _shareContent, 'fab4'),
                  const SizedBox(width: 12),
                  _buildVolumeFab(),
                ],
              ),
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
              children: paragraphs.asMap().entries.map((entry) {
                final i = entry.key;
                final text = entry.value;
                final isHeading = text.length < 60;
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: _ttsActive && _ttsWords.isNotEmpty
                      ? _buildTtsHighlightedParagraph(text, i)
                      : SelectableText.rich(
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
        ],
      ),
    );
  }

  Widget _buildTtsBar() {
    if (!_ttsActive && !_isTtsLoading) return const SizedBox.shrink();
    return Container(
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
              onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
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
    );
  }

  Widget _buildFAB(IconData icon, VoidCallback onPressed, String heroTag) {
    return SizedBox(
      width: 48,
      height: 48,
      child: FloatingActionButton(
        heroTag: heroTag,
        onPressed: onPressed,
        backgroundColor: const Color(0xFFF5F5F5),
        child: Icon(icon, color: Color.fromARGB(241, 179, 93, 78)),
      ),
    );
  }

  Widget _buildVolumeFab() {
    return SizedBox(
      width: 48,
      height: 48,
      child: FloatingActionButton(
        heroTag: 'fab_volume',
        onPressed: _speakContent,
        backgroundColor: _ttsActive ? Colors.brown : const Color(0xFFF5F5F5),
        child: _isTtsLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                _ttsActive ? Icons.stop : Icons.volume_up,
                color: _ttsActive
                    ? Colors.white
                    : const Color.fromARGB(241, 179, 93, 78),
              ),
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

class _WordRange {
  final int start;
  final int end;
  _WordRange(this.start, this.end);
}
