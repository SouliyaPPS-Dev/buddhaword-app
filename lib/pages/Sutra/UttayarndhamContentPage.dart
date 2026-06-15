// ignore_for_file: file_names, library_private_types_in_public_api, prefer_const_constructors, deprecated_member_use
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
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'UttayarndhamPage.dart';

class UttayarndhamContentPage extends StatefulWidget {
  final String title;
  final String contentUrl;
  final List<UttayarndhamItem>? items;
  final int? itemIndex;
  final String searchQuery;

  const UttayarndhamContentPage({
    super.key,
    required this.title,
    required this.contentUrl,
    this.items,
    this.itemIndex,
    this.searchQuery = '',
  });

  @override
  _UttayarndhamContentPageState createState() =>
      _UttayarndhamContentPageState();
}

class _UttayarndhamContentPageState
    extends State<UttayarndhamContentPage> {
  String? _htmlContent;
  bool _isLoading = true;
  String? _error;
  late String _currentUrl;
  late String _currentTitle;
  late int _currentIndex;
  String _currentRelUrl = '';

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
  final Map<int, String> _contentCache = {};
  late PageController _pageController;

  bool _isOffline = false;
  StreamSubscription? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.contentUrl;
    _currentTitle = widget.title;
    _currentIndex = widget.itemIndex ?? 0;
    if (widget.items != null && _currentIndex < widget.items!.length) {
      _currentRelUrl = widget.items![_currentIndex].url;
    }
    _pageController = PageController(initialPage: _currentIndex);
    _fetchContent();
    _loadFontSizeFromSharedPreferences();
    _loadFavoriteState();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) setState(() => _isOffline = results.contains(ConnectivityResult.none));
    });
  }

  Future<void> _fetchContent() async {
    if (_contentCache.containsKey(_currentIndex)) {
      setState(() {
        _htmlContent = _contentCache[_currentIndex]!;
        _isLoading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http.get(Uri.parse(_currentUrl));
      if (response.statusCode == 200) {
        final extracted = _extractContent(response.body);
        if (mounted) {
          setState(() {
            _htmlContent = extracted;
            _isLoading = false;
          });
          _contentCache[_currentIndex] = extracted;
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed (${response.statusCode})';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!_isOffline) _error = 'ການໂຫຼດຂໍ້ມູນລົ້ມເຫຼວ (ກະລຸນາກວດສອບການເຊື່ອມຕໍ່)';
          _isLoading = false;
        });
      }
    }
  }

  void _goToPrevItem() {
    if (!_hasPrev || !_pageController.hasClients) return;
    _pageController.previousPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goToNextItem() {
    if (!_hasNext || !_pageController.hasClients) return;
    _pageController.nextPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    if (index == _currentIndex) return;
    if (_htmlContent != null && !_contentCache.containsKey(_currentIndex)) {
      _contentCache[_currentIndex] = _htmlContent!;
    }
    _stopTts();
    final item = widget.items![index];
    setState(() {
      _currentIndex = index;
      _currentTitle = item.title;
      _currentUrl = 'https://uttayarndham.org${item.url}';
      _currentRelUrl = item.url;
    });
    if (_contentCache.containsKey(index)) {
      setState(() {
        _htmlContent = _contentCache[index]!;
        _isLoading = false;
        _error = null;
      });
    } else {
      setState(() {
        _htmlContent = null;
        _isLoading = true;
        _error = null;
      });
      _fetchContent();
    }
    _loadFavoriteState();
  }

  String _extractContent(String html) {
    final nodeStart = html.indexOf('node__content');
    if (nodeStart < 0) return html;
    final divStart = html.lastIndexOf('<div', nodeStart);
    if (divStart < 0) return html;
    int depth = 0;
    int endPos = divStart;
    for (int i = divStart; i < html.length; i++) {
      if (html.substring(i).startsWith('<div')) { depth++; i += 3; }
      else if (html.substring(i).startsWith('</div>')) {
        depth--;
        if (depth <= 0) { endPos = i + 6; break; }
        i += 5;
      }
    }
    return html.substring(divStart, endPos);
  }

  List<String> _extractParagraphs(String html) {
    String text = html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<p[^>]*>'), '\n')
        .replaceAll(RegExp(r'</p>'), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\u00A0'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final lines = text.split('\n')
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

  String _extractPlainText(String html) {
    final paragraphs = _extractParagraphs(html);
    return paragraphs.join('\n\n');
  }

  void _copyContent() {
    if (_htmlContent == null) return;
    final text = _extractPlainText(_htmlContent!);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Content copied to clipboard')),
    );
  }

  void _shareContent() {
    if (_htmlContent == null) return;
    final href = _currentRelUrl.isNotEmpty
        ? _currentRelUrl
        : _currentUrl;
    final shareUrl = 'https://buddhaword-web.hf.space/uttayarndham/read?url=${Uri.encodeQueryComponent(href)}';
    Share.share('$_currentTitle\n$shareUrl', subject: _currentTitle);
  }

  Future<void> _loadFavoriteState() async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList('favorites') ?? [];
    final identifier = _currentUrl;
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
    final identifier = _currentUrl;
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
        'details': _htmlContent != null ? _extractPlainText(_htmlContent!) : _currentUrl,
        'category': 'uttayarndham',
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
      setState(() { _isPlaying = state.playing; });
      if (state.processingState == ProcessingState.completed && _ttsActive) {
        _advanceToNextChunk();
      }
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      if (mounted) setState(() { _duration = duration ?? Duration.zero; });
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
        setState(() { _ttsActive = false; _isPlaying = false; });
      }
      return;
    }

    final file = _nextPrefetchedFile;
    _nextPrefetchedFile = null;
    if (file == null || !_ttsActive) return;

    file.readAsBytes().then((bytes) { _ttsChunkBytes.add(bytes); });
    _player.setFilePath(file.path).then((_) {
      _player.setSpeed(0.85);
      _player.play();
    });
    try { await file.delete(); } catch (_) {}
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
    if (_htmlContent == null) return;
    if (_ttsActive) {
      _stopTts();
      return;
    }

    final paragraphs = _extractParagraphs(_htmlContent!);
    if (paragraphs.isEmpty) return;
    final ttsText = paragraphs.join('\n');
    if (ttsText.length > _maxTtsChars) return;

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
      if (mounted) setState(() { _ttsActive = false; _isTtsLoading = false; });
      return;
    }

    if (mounted) setState(() { _isTtsLoading = false; });
    _ttsChunkBytes.add(await firstFile.readAsBytes());
    await _player.setFilePath(firstFile.path);
    await _player.setSpeed(0.85);
    await _player.play();
    try { await firstFile.delete(); } catch (_) {}
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

  Future<void> _downloadAudio() async {
    if (_ttsChunkBytes.isEmpty) return;
    final dir = await getTemporaryDirectory();
    final fileName = 'uttayarndham_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final file = File('${dir.path}/$fileName');
    final allBytes = <int>[];
    for (final bytes in _ttsChunkBytes) {
      allBytes.addAll(bytes);
    }
    await file.writeAsBytes(allBytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: $fileName')),
      );
    }
  }

  @override
  void dispose() {
    _ttsRunId++;
    _connectivitySubscription?.cancel();
    _ttsActive = false;
    _player.stop();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _player.dispose();
    _ttsChunks = [];
    _ttsChunkEnds = [];
    _nextPrefetchedFile = null;
    _pageController.dispose();
    super.dispose();
  }

  bool get _hasPrev => widget.items != null && _currentIndex > 0;
  bool get _hasNext => widget.items != null && _currentIndex < widget.items!.length - 1;

  bool _isFullScreen = false;
  bool _isFavorited = false;

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
                icon: Icon(Icons.arrow_back_ios, color: Colors.white),
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
              _buildOfflineBanner(),
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
          if (!_isFullScreen && _hasPrev)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.brown.withOpacity(0.5),
                    size: 30,
                  ),
                  onPressed: _goToPrevItem,
                ),
              ),
            ),
          if (!_isFullScreen && _hasNext)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.brown.withOpacity(0.5),
                    size: 30,
                  ),
                  onPressed: _goToNextItem,
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

  Widget _buildOfflineBanner() {
    if (!_isOffline) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.shade800,
      child: const Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'No internet connection',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (widget.items != null && widget.items!.length > 1) {
      return PageView.builder(
        controller: _pageController,
        itemCount: widget.items!.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) => _buildItemContent(index),
      );
    }
    return _buildSingleContent();
  }

  Widget _buildSingleContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
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
    if (_htmlContent == null) return const Center(child: Text('No content'));
    final paragraphs = _extractParagraphs(_htmlContent!);
    if (paragraphs.isEmpty) return const Center(child: Text('No text content'));
    return _buildParagraphsView(paragraphs);
  }

  Widget _buildItemContent(int index) {
    final cached = _contentCache[index];
    if (cached != null) {
      final paragraphs = _extractParagraphs(cached);
      if (paragraphs.isEmpty) return const Center(child: Text('No text content'));
      return _buildParagraphsView(paragraphs);
    }
    if (index == _currentIndex) {
      if (_isLoading) return const Center(child: CircularProgressIndicator());
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
      if (_htmlContent != null) {
        final paragraphs = _extractParagraphs(_htmlContent!);
        if (paragraphs.isEmpty) return const Center(child: Text('No text content'));
        return _buildParagraphsView(paragraphs);
      }
    }
    return const Center(child: CircularProgressIndicator());
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

  Widget _buildParagraphsView(List<String> paragraphs) {
    return ListView(
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
                    fontWeight: isHeading ? FontWeight.bold : FontWeight.normal,
                    height: 1.6,
                    letterSpacing: 0.3,
                  ),
                ),
        );
      }).toList(),
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
              max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
              value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
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
        backgroundColor: _ttsActive
            ? Colors.brown
            : const Color(0xFFF5F5F5),
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
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.orange.shade800,
          backgroundColor: Colors.yellow.withValues(alpha: 0.3),
        ),
      ));
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
