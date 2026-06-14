import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart'
    show AudioPlayer, PlayerState, ProcessingState;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../providers/search_books_provider.dart';

enum _AudioMode { none, tts }

class SearchBooksReaderPage extends StatefulWidget {
  final String slug;
  final String title;
  final int totalPages;

  const SearchBooksReaderPage({
    super.key,
    required this.slug,
    required this.title,
    required this.totalPages,
  });

  @override
  State<SearchBooksReaderPage> createState() => _SearchBooksReaderPageState();
}

class _SearchBooksReaderPageState extends State<SearchBooksReaderPage> {
  late PageController _pageController;
  int _currentPage = 1;
  final Map<int, PageNavResult?> _pageCache = {};
  static const String _ttsBaseUrl = 'https://buddhaword-web.hf.space';
  static const int _ttsMaxChars = 50000;
  static const int _ttsChunkSize = 1200;

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLoadingAudio = false;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  _AudioMode _audioMode = _AudioMode.none;
  final List<Uint8List> _ttsChunkBytes = [];
  int _ttsRunId = 0;
  double _fontSize = 18.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadPage(1);
  }

  Future<void> _loadPage(int pageNum) async {
    if (_pageCache.containsKey(pageNum)) return;
    final provider = context.read<SearchBooksProvider>();
    final result = await provider.fetchPage(widget.slug, pageNum);
    if (mounted) {
      setState(() {
        _pageCache[pageNum] = result;
        _currentPage = pageNum;
      });
    }
  }

  void _onPageChanged(int index) {
    _stopTts();
    final pageNum = index + 1;
    _currentPage = pageNum;
    _loadPage(pageNum);
  }

  @override
  void dispose() {
    _ttsRunId++;
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _player.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromRGBO(246, 238, 217, 1.0),
      appBar: AppBar(
        backgroundColor: Colors.brown,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16, letterSpacing: 0.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => _showSearchInBookDialog(context),
          ),
          const SizedBox(width: 5),
          IconButton(
            icon: const Icon(Icons.text_increase, color: Colors.white),
            onPressed: _increaseFontSize,
          ),
          IconButton(
            icon: const Icon(Icons.text_decrease, color: Colors.white),
            onPressed: _decreaseFontSize,
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.totalPages,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final pageNum = index + 1;
                    final cached = _pageCache[pageNum];

                    if (cached == null) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return GestureDetector(
                      onHorizontalDragEnd: (details) {
                        if (details.primaryVelocity == null) return;
                        if (details.primaryVelocity! < -50) {
                          if (_currentPage < widget.totalPages) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        } else if (details.primaryVelocity! > 50) {
                          if (_currentPage > 1) {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        }
                      },
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.all(16.0),
                        child: SelectableText(
                          cached.page.text,
                          style: TextStyle(
                            fontSize: _fontSize,
                            height: 1.6,
                            fontFamily: 'NotoSerifLao',
                            color: const Color.fromRGBO(88, 74, 54, 1.0),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _buildTtsBar(),
            ],
          ),
          if (_currentPage > 1)
            Positioned(
              left: 0,
              top: 0,
              bottom: 80,
              child: Center(
                child: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new,
                      color: Colors.brown.withValues(alpha: 0.5), size: 30),
                  onPressed: () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ),
            ),
          if (_currentPage < widget.totalPages)
            Positioned(
              right: 0,
              top: 0,
              bottom: 80,
              child: Center(
                child: IconButton(
                  icon: Icon(Icons.arrow_forward_ios,
                      color: Colors.brown.withValues(alpha: 0.5), size: 30),
                  onPressed: () {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ),
            ),
          Positioned(
            bottom: 100,
            right: 16,
            child: _buildVolumeFab(),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: Colors.brown,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              onPressed: _currentPage > 1
                  ? () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  : null,
              iconSize: 32,
            ),
            Text(
              '$_currentPage / ${widget.totalPages}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: Colors.white),
              onPressed: _currentPage < widget.totalPages
                  ? () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  : null,
              iconSize: 32,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeFab() {
    return SizedBox(
      width: 48,
      height: 48,
      child: FloatingActionButton(
        heroTag: 'fab_volume',
        onPressed: _isLoadingAudio ? null : _speakContent,
        backgroundColor: _audioMode == _AudioMode.tts
            ? Colors.brown
            : const Color(0xFFF5F5F5),
        child: _isLoadingAudio
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.brown,
                ),
              )
            : Icon(
                _audioMode == _AudioMode.tts ? Icons.stop : Icons.volume_up,
                color: _audioMode == _AudioMode.tts
                    ? Colors.white
                    : const Color.fromARGB(241, 179, 93, 78),
              ),
      ),
    );
  }

  Widget _buildTtsBar() {
    if (_audioMode != _AudioMode.tts && _ttsChunkBytes.isEmpty) {
      return const SizedBox.shrink();
    }
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
          const SizedBox(width: 4),
          if (_ttsChunkBytes.isNotEmpty)
            IconButton(
              icon: Icon(Icons.download, color: Colors.brown, size: 20),
              onPressed: () => _downloadTtsAudio(),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
          IconButton(
            icon: Icon(Icons.stop, color: Colors.red, size: 20),
            onPressed: _stopTts,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  void _stopTts() {
    _ttsRunId++;
    _player.stop();
    _ttsChunkBytes.clear();
    setState(() {
      _audioMode = _AudioMode.none;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _isLoadingAudio = false;
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  String _detectLanguage(String text) {
    int laoCount = 0, thaiCount = 0, engCount = 0;
    for (final rune in text.runes) {
      if (rune >= 0x0E80 && rune <= 0x0EFF) {
        laoCount++;
      } else if (rune >= 0x0E00 && rune <= 0x0E7F) {
        thaiCount++;
      } else if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) {
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
        if ('.!?:\n'.contains(text[i])) {
          breakAt = i + 1;
          break;
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

  Future<void> _speakContent() async {
    if (_audioMode == _AudioMode.tts) {
      await _player.stop();
      _ttsChunkBytes.clear();
      if (mounted) {
        setState(() {
          _audioMode = _AudioMode.none;
          _isPlaying = false;
          _position = Duration.zero;
          _duration = Duration.zero;
          _isLoadingAudio = false;
        });
      }
      return;
    }

    final cached = _pageCache[_currentPage];
    if (cached == null) return;
    String content = cached.page.text;
    content = content.replaceAll(RegExp(r'<\/?b>'), '');
    if (content.length > _ttsMaxChars) {
      content = content.substring(0, _ttsMaxChars);
    }
    final chunks = _chunkText(content);
    if (chunks.isEmpty) return;

    _ttsRunId++;
    final runId = _ttsRunId;
    _ttsChunkBytes.clear();

    if (mounted) {
      setState(() {
        _audioMode = _AudioMode.tts;
        _isLoadingAudio = true;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }

    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();

    _playerStateSubscription = _player.playerStateStream.listen((playerState) {
      if (mounted) setState(() => _isPlaying = playerState.playing);
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      if (mounted) setState(() => _duration = duration ?? Duration.zero);
    });
    _positionSubscription = _player.positionStream.listen((position) {
      if (mounted) setState(() => _position = position);
    });

    File? file = await _fetchTtsChunk(0, chunks[0]);
    if (file == null || runId != _ttsRunId || !mounted || _audioMode != _AudioMode.tts) {
      if (mounted && _audioMode == _AudioMode.tts) {
        setState(() { _audioMode = _AudioMode.none; _isLoadingAudio = false; });
      }
      return;
    }

    if (mounted) setState(() => _isLoadingAudio = false);
    await _player.setFilePath(file.path);
    await _player.setSpeed(0.85);
    await _player.play();
    _ttsChunkBytes.add(await file.readAsBytes());
    try { await file.delete(); } catch (_) {}

    for (int i = 1; i < chunks.length; i++) {
      if (runId != _ttsRunId || !mounted || _audioMode != _AudioMode.tts) break;

      Future<File?> prefetch = _fetchTtsChunk(i, chunks[i]);

      try {
        final state = _player.processingState;
        if (state != ProcessingState.completed && state != ProcessingState.idle) {
          await _player.processingStateStream.firstWhere(
            (s) => s == ProcessingState.completed || s == ProcessingState.idle,
          );
        }
      } catch (_) {
        break;
      }
      if (runId != _ttsRunId || !mounted || _audioMode != _AudioMode.tts) break;

      File? file = await prefetch;
      if (file == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('TTS error')),
          );
        }
        break;
      }

      await _player.setFilePath(file.path);
      await _player.setSpeed(0.85);
      await _player.play();
      _ttsChunkBytes.add(await file.readAsBytes());
      try { await file.delete(); } catch (_) {}
    }

    if (mounted && runId == _ttsRunId && _audioMode == _AudioMode.tts) {
      try {
        final state = _player.processingState;
        if (state != ProcessingState.completed && state != ProcessingState.idle) {
          await _player.processingStateStream.firstWhere(
            (s) => s == ProcessingState.completed || s == ProcessingState.idle,
          );
        }
      } catch (_) {}
      if (mounted && runId == _ttsRunId && _audioMode == _AudioMode.tts) {
        setState(() {
          _audioMode = _AudioMode.none;
          _isPlaying = false;
          _position = Duration.zero;
          _duration = Duration.zero;
        });
      }
    }
  }

  Future<void> _downloadTtsAudio() async {
    if (_ttsChunkBytes.isEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/${widget.slug}_page$_currentPage.mp3',
      );
      final allBytes = Uint8List(_ttsChunkBytes.fold(0, (sum, b) => sum + b.length));
      int offset = 0;
      for (final chunk in _ttsChunkBytes) {
        allBytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      await file.writeAsBytes(allBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  void _increaseFontSize() {
    setState(() => _fontSize = (_fontSize + 2).clamp(12.0, 36.0));
  }

  void _decreaseFontSize() {
    setState(() => _fontSize = (_fontSize - 2).clamp(12.0, 36.0));
  }

  void _showSearchInBookDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ຄົ້ນຫາໃນປຶ້ມ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'ພິມຄຳທີ່ຕ້ອງການຄົ້ນຫາ...',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ຍົກເລີກ'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (controller.text.trim().isNotEmpty) {
                _showSearchResults(controller.text.trim());
              }
            },
            child: const Text('ຄົ້ນຫາ'),
          ),
        ],
      ),
    );
  }

  void _showSearchResults(String query) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final provider = context.read<SearchBooksProvider>();
    final results = await provider.searchInBook(widget.slug, query);

    if (!mounted) return;
    Navigator.pop(context);

    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ບໍ່ພົບຜົນການຄົ້ນຫາ')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'ພົບ ${results.length} ໜ້າ',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = results[i];
                  return ListTile(
                    leading: CircleAvatar(child: Text('${r.page}')),
                    title: Text(
                      'ໜ້າທີ ${r.page} (${r.matches} ຄຳ)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      r.snippet,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _pageController.jumpToPage(r.page - 1);
                      _loadPage(r.page);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
