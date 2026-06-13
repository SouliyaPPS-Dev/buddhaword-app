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

import '../../themes/ThemeProvider.dart';
import 'AnakameSutraPage.dart';

class AnakameSutraContentPage extends StatefulWidget {
  final String title;
  final String contentUrl;
  final List<AnakameSutraItem>? items;
  final int? itemIndex;
  final String searchQuery;

  const AnakameSutraContentPage({
    super.key,
    required this.title,
    required this.contentUrl,
    this.items,
    this.itemIndex,
    this.searchQuery = '',
  });

  @override
  _AnakameSutraContentPageState createState() =>
      _AnakameSutraContentPageState();
}

class _AnakameSutraContentPageState extends State<AnakameSutraContentPage> {
  String? _htmlContent;
  bool _isLoading = true;
  String? _error;
  late String _currentUrl;
  late String _currentTitle;
  late int _currentIndex;

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

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.contentUrl;
    _currentTitle = widget.title;
    _currentIndex = widget.itemIndex ?? 0;
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
      final response = await http.get(Uri.parse(_currentUrl));
      if (response.statusCode == 200) {
        String decoded = utf8.decode(response.bodyBytes);
        if (decoded.startsWith('\uFEFF')) {
          decoded = decoded.substring(1);
        }
        if (mounted) {
          setState(() {
            _htmlContent = decoded;
            _isLoading = false;
          });
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
          _error = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _goToPrevItem() {
    if (widget.items == null || _currentIndex <= 0) return;
    _stopTts();
    final prevItem = widget.items![_currentIndex - 1];
    setState(() {
      _currentIndex--;
      _currentTitle = prevItem.title;
      _currentUrl = _resolveUrl(prevItem.url);
    });
    _fetchContent();
    _loadFavoriteState();
  }

  void _goToNextItem() {
    if (widget.items == null || _currentIndex >= widget.items!.length - 1) {
      return;
    }
    _stopTts();
    final nextItem = widget.items![_currentIndex + 1];
    setState(() {
      _currentIndex++;
      _currentTitle = nextItem.title;
      _currentUrl = _resolveUrl(nextItem.url);
    });
    _fetchContent();
    _loadFavoriteState();
  }

  String _resolveUrl(String href) {
    if (href.startsWith('http')) return href;
    const baseUrl = 'http://anakame.com/page/1_Sutas/main/1_Sutta_number.htm';
    final uri = Uri.parse(baseUrl);
    return uri.resolve(href).toString();
  }

  List<String> _extractParagraphs(String html) {
    String text = html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
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
    final text = _extractPlainText(_htmlContent!);
    Share.share(text, subject: _currentTitle);
  }

  Future<void> _loadFavoriteState() async {
    final prefs = await SharedPreferences.getInstance();
    final identifier = _currentUrl;
    if (!mounted) return;
    setState(() {
      _isFavorited = prefs.getBool('fav_anakame_$identifier') ?? false;
    });
  }

  Future<void> _toggleFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    final identifier = _currentUrl;
    setState(() => _isFavorited = !_isFavorited);
    await prefs.setBool('fav_anakame_$identifier', _isFavorited);
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
    if (_ttsActive) {
      await _player.stop();
      if (mounted) {
        setState(() {
          _ttsActive = false;
          _isPlaying = false;
          _position = Duration.zero;
          _duration = Duration.zero;
          _ttsChunkIndex = 0;
          _ttsChunks = [];
          _nextPrefetchedFile = null;
        });
      }
      return;
    }

    if (_htmlContent == null) return;
    _ttsRunId++;
    final runId = _ttsRunId;
    _ttsChunkBytes.clear();
    _nextPrefetchedFile = null;

    final text = _extractPlainText(_htmlContent!);
    final content = text.length > _maxTtsChars
        ? text.substring(0, _maxTtsChars)
        : text;
    _ttsChunks = _chunkText(content);
    _ttsChunkIndex = 0;

    if (_ttsChunks.isEmpty) return;

    if (mounted) {
      setState(() {
        _ttsActive = true;
        _isTtsLoading = true;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }

    _setupTtsListeners();

    final file = await _fetchTtsChunk(0, _ttsChunks[0]);
    if (file == null || runId != _ttsRunId || !mounted || !_ttsActive) {
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
    _ttsChunkBytes.add(await file.readAsBytes());
    await _player.setFilePath(file.path);
    await _player.setSpeed(0.85);
    await _player.play();
    try {
      await file.delete();
    } catch (_) {}

    _prefetchChunk(1);
  }

  Future<void> _stopTts() async {
    _ttsRunId++;
    await _player.stop();
    if (mounted) {
      setState(() {
        _ttsActive = false;
        _isPlaying = false;
        _position = Duration.zero;
        _duration = Duration.zero;
        _ttsChunkIndex = 0;
        _ttsChunks = [];
        _nextPrefetchedFile = null;
      });
    }
  }

  Future<void> _downloadAudio() async {
    try {
      Uint8List audioData;
      String fileName;

      if (_ttsChunkBytes.isNotEmpty) {
        final int totalLength = _ttsChunkBytes.fold(
          0,
          (sum, b) => sum + b.length,
        );
        final Uint8List allBytes = Uint8List(totalLength);
        int offset = 0;
        for (final bytes in _ttsChunkBytes) {
          allBytes.setRange(offset, offset + bytes.length, bytes);
          offset += bytes.length;
        }
        audioData = allBytes;
        fileName = '$_currentTitle.mp3';
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No audio to download. Play TTS first.'),
            ),
          );
        }
        return;
      }

      fileName = fileName.replaceAll(RegExp(r'[^\w\s\-()]'), '_');
      if (!fileName.endsWith('.mp3')) fileName = '$fileName.mp3';

      final dir = await getApplicationDocumentsDirectory();
      final String downloadDir = '${dir.path}/Downloads';
      final Directory downloadFolder = Directory(downloadDir);
      if (!await downloadFolder.exists()) {
        await downloadFolder.create(recursive: true);
      }
      final File file = File('$downloadDir/$fileName');
      await file.writeAsBytes(audioData);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to Downloads/$fileName')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download error: $e')));
      }
    }
  }

  @override
  void dispose() {
    _ttsRunId++;
    _player.stop();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  bool get _hasPrev => widget.items != null && _currentIndex > 0;
  bool get _hasNext =>
      widget.items != null && _currentIndex < widget.items!.length - 1;

  bool _isFullScreen = false;
  bool _isFavorited = false;

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
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () {
                  _ttsRunId++;
                  _player.stop();
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
          : Row(
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
    );
  }

  Widget _buildBody() {
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
    if (paragraphs.isEmpty) {
      return const Center(child: Text('No text content'));
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! > 0) {
          if (_hasPrev) _goToPrevItem();
        } else if (details.primaryVelocity! < 0) {
          if (_hasNext) _goToNextItem();
        }
      },
      child: Column(
        children: [
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
