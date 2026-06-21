import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart'
    show AudioPlayer, PlayerState, ProcessingState;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/search_books_provider.dart';

class _SearchHighlightController extends TextEditingController {
  final String query;
  final bool isDark;

  _SearchHighlightController({
    required String text,
    required this.query,
    required this.isDark,
  }) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (query.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    final escaped = RegExp.escape(query);
    final regex = RegExp('($escaped)', caseSensitive: false);
    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.yellowAccent : Colors.brown.shade900,
            backgroundColor: isDark
                ? Colors.yellow.withValues(alpha: 0.3)
                : const Color(0xFFFFD700),
          ),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return TextSpan(style: style, children: spans);
  }
}

enum _AudioMode { none, tts }

enum BookTheme { light, sepia, dark }

class _WordRange {
  final int start;
  final int end;
  _WordRange(this.start, this.end);
}

class SearchBooksReaderPage extends StatefulWidget {
  final String slug;
  final String title;
  final int totalPages;
  final String? highlightQuery;
  final int? initialPage;

  const SearchBooksReaderPage({
    super.key,
    required this.slug,
    required this.title,
    this.totalPages = 0,
    this.highlightQuery,
    this.initialPage,
  });

  @override
  State<SearchBooksReaderPage> createState() => _SearchBooksReaderPageState();
}

class _SearchBooksReaderPageState extends State<SearchBooksReaderPage> {
  late PageController _pageController;
  int _currentPage = 1;
  late int _totalPages;
  final Map<int, PageNavResult?> _pageCache = {};
  final Map<int, bool> _pageErrors = {};
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
  BookTheme _bookTheme = BookTheme.sepia;
  bool _isFullScreen = false;
  bool _isFavorited = false;
  List<_WordRange> _ttsWords = [];
  int _ttsCurrentWordIndex = -1;
  int _ttsChunkIndex = 0;
  List<int> _ttsChunkEnds = [];

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage ?? 1;
    _totalPages = widget.totalPages;
    final startIndex = _currentPage - 1;
    _pageController = PageController(initialPage: startIndex);
    _loadPage(_currentPage);
    _loadTheme();
    _loadFontSize();
    _loadFavoriteState();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt('reader_theme') ?? 1;
    if (mounted) setState(() => _bookTheme = BookTheme.values[val.clamp(0, 2)]);
  }

  Future<void> _saveTheme(BookTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reader_theme', theme.index);
  }

  Future<void> _loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble('fontSize');
    if (saved != null && mounted) {
      setState(() => _fontSize = saved);
    }
  }

  Future<void> _saveFontSize(double size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', size);
  }

  Future<void> _loadFavoriteState() async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList('favorites') ?? [];
    if (!mounted) return;
    setState(() {
      _isFavorited = favorites.any((fav) {
        final data = json.decode(fav) as Map<String, dynamic>;
        return data['type'] == 'book' && data['slug'] == widget.slug;
      });
    });
  }

  Future<void> _toggleFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = List<String>.from(prefs.getStringList('favorites') ?? []);
    setState(() => _isFavorited = !_isFavorited);
    if (_isFavorited) {
      favorites.add(
        json.encode({
          'type': 'book',
          'slug': widget.slug,
          'title': widget.title,
          'totalPages': _totalPages,
        }),
      );
    } else {
      favorites.removeWhere((fav) {
        final data = json.decode(fav) as Map<String, dynamic>;
        return data['type'] == 'book' && data['slug'] == widget.slug;
      });
    }
    await prefs.setStringList('favorites', favorites);
  }

  void _cycleTheme() {
    final themes = BookTheme.values;
    final next = themes[(_bookTheme.index + 1) % themes.length];
    setState(() => _bookTheme = next);
    _saveTheme(next);
  }

  Color get _bgColor {
    switch (_bookTheme) {
      case BookTheme.light:
        return Colors.white;
      case BookTheme.sepia:
        return const Color.fromRGBO(246, 238, 217, 1.0);
      case BookTheme.dark:
        return const Color(0xFF0D0D0D);
    }
  }

  Color get _textColor {
    switch (_bookTheme) {
      case BookTheme.light:
        return const Color.fromRGBO(88, 74, 54, 1.0);
      case BookTheme.sepia:
        return const Color.fromRGBO(88, 74, 54, 1.0);
      case BookTheme.dark:
        return const Color(0xFFF0F0F0);
    }
  }

  Future<void> _loadPage(int pageNum) async {
    if (_pageCache.containsKey(pageNum)) return;
    final provider = context.read<SearchBooksProvider>();
    final result = await provider.fetchPage(
      widget.slug,
      pageNum,
    );
    if (mounted) {
      final wasUnknown = _totalPages == 0;
      setState(() {
        _pageCache[pageNum] = result;
        if (result == null) {
          _pageErrors[pageNum] = true;
        }
        if (result != null && _totalPages == 0) {
          _totalPages = result.totalPages;
        }
      });
      if (wasUnknown && result != null) {
        final targetPage = pageNum;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _pageController.hasClients &&
              _currentPage == targetPage &&
              targetPage > 0 &&
              targetPage - 1 < _totalPages) {
            _pageController.jumpToPage(targetPage - 1);
          }
        });
      }
    }
  }

  void _onPageChanged(int index) {
    _stopTts();
    final pageNum = index + 1;
    _currentPage = pageNum;
    _loadPage(pageNum);
  }

  void _goToPage(int pageNum) {
    _stopTts();
    _pageController.jumpToPage(pageNum - 1);
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
      backgroundColor: _bgColor,
      appBar: _isFullScreen
          ? PreferredSize(
              preferredSize: Size.zero,
              child: const SizedBox.shrink(),
            )
          : AppBar(
              backgroundColor: Colors.brown,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: _buildTitle(),
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
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: () => _showSearchInBookDialog(context),
                ),
                IconButton(
                  icon: const Icon(Icons.text_increase, color: Colors.white),
                  onPressed: _increaseFontSize,
                ),
                IconButton(
                  icon: const Icon(Icons.text_decrease, color: Colors.white),
                  onPressed: _decreaseFontSize,
                ),
                IconButton(
                  icon: Icon(
                    _bookTheme == BookTheme.dark
                        ? Icons.dark_mode
                        : Icons.light_mode,
                    color: Colors.white,
                  ),
                  onPressed: _cycleTheme,
                ),
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.white),
                  onPressed: _sharePage,
                ),
                const SizedBox(width: 4),
              ],
            ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _totalPages > 0 ? _totalPages : 1,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final pageNum = index + 1;
                    final cached = _pageCache[pageNum];

                    if (_pageErrors[pageNum] == true) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_off,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'ບໍ່ສາມາດໂຫຼດຂໍ້ມູນໜ້ານີ້ໄດ້',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _pageErrors.remove(pageNum);
                                    _pageCache.remove(pageNum);
                                  });
                                  _loadPage(pageNum);
                                },
                                child: const Text('ລອງໃໝ່'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    if (cached == null) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return GestureDetector(
                      onHorizontalDragEnd: (details) {
                        if (details.primaryVelocity == null) return;
                        if (details.primaryVelocity! < -50) {
                          if (_currentPage < _totalPages) {
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
                        child: _buildPageText(cached.page.text),
                      ),
                    );
                  },
                ),
              ),
              _buildTtsBar(),
            ],
          ),
          if (!_isFullScreen && _currentPage > 1)
            Positioned(
              left: 0,
              top: 0,
              bottom: 80,
              child: Center(
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.brown.withValues(alpha: 0.5),
                    size: 30,
                  ),
                  onPressed: () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ),
            ),
          if (!_isFullScreen && _currentPage < _totalPages)
            Positioned(
              right: 0,
              top: 0,
              bottom: 80,
              child: Center(
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.brown.withValues(alpha: 0.5),
                    size: 30,
                  ),
                  onPressed: () {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ),
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
          if (!_isFullScreen)
            Positioned(bottom: 100, right: 16, child: _buildVolumeFab()),
        ],
      ),
      bottomNavigationBar: _isFullScreen
          ? null
          : Container(
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
                  GestureDetector(
                    onTap: _showPageJumpDialog,
                    child: Text(
                      '$_currentPage / $_totalPages',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                    onPressed: _currentPage < _totalPages
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

  Widget _buildTitle() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 200) {
          return Text(
            widget.title,
            style: const TextStyle(
              fontSize: 14,
              letterSpacing: 0.5,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 14,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (_totalPages > 0)
              GestureDetector(
                onTap: _showPageJumpDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_currentPage',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ),
            Text(
              ' / $_totalPages',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPageText(String text) {
    final query = widget.highlightQuery;
    final isToc = _isTocPage(text);

    if (isToc) {
      return _buildTocContent(text, query);
    }

    if (_audioMode == _AudioMode.tts && _ttsWords.isNotEmpty) {
      return _buildTtsHighlightedText(text, query);
    }

    if (query == null || query.isEmpty) {
      return TextField(
        controller: TextEditingController(text: text),
        readOnly: true,
        showCursor: true,
        style: TextStyle(
          fontSize: _fontSize,
          height: 1.6,
          fontFamily: 'NotoSerifLao',
          color: _textColor,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        maxLines: null,
      );
    }

    return _buildHighlightedText(text, query);
  }

  bool _isTocPage(String text) {
    if (text.contains('ສາລະບານ') || text.contains('สารບັນ')) return true;
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return false;
    final tocPattern = RegExp(r'^(.*?)[\s\.…]+(\d+)$');
    final tocLines = lines.where((l) => tocPattern.hasMatch(l)).length;
    return lines.isNotEmpty && (tocLines / lines.length) >= 0.5;
  }

  Widget _buildTocContent(String text, String? query) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.startsWith('ສາລະບານ')) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SelectableText(
              line,
              style: TextStyle(
                fontSize: _fontSize + 4,
                fontWeight: FontWeight.bold,
                fontFamily: 'NotoSerifLao',
                color: _textColor,
              ),
            ),
          );
        }

        final tocMatch = RegExp(r'^(.*?)[\s\.…]+(\d+)$').firstMatch(line);
        if (tocMatch != null) {
          final title = tocMatch.group(1)!;
          final pageNum = int.parse(tocMatch.group(2)!);
          final viewerPage = pageNum;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: InkWell(
              onTap: () => _goToPage(viewerPage),
              child: Row(
                children: [
                  Expanded(
                    child: query != null && query.isNotEmpty
                        ? _buildHighlightedInline(title, query)
                        : SelectableText(
                            title,
                            style: TextStyle(
                              fontSize: _fontSize,
                              fontFamily: 'NotoSerifLao',
                              color: _textColor,
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.brown.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$viewerPage',
                      style: TextStyle(
                        fontSize: _fontSize - 2,
                        fontWeight: FontWeight.bold,
                        color: Colors.brown,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: SelectableText(
            line,
            style: TextStyle(
              fontSize: _fontSize,
              fontFamily: 'NotoSerifLao',
              color: _textColor,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTtsHighlightedText(String text, String? query) {
    final spans = <TextSpan>[];
    int wordIndex = 0;
    int lastEnd = 0;

    for (int i = 0; i < _ttsWords.length; i++) {
      final r = _ttsWords[i];
      if (r.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, r.start)));
      }
      final wordText = text.substring(r.start, r.end);
      final isCurrent = wordIndex == _ttsCurrentWordIndex;
      spans.add(
        TextSpan(
          text: wordText,
          style: TextStyle(
            backgroundColor: isCurrent ? Colors.yellow : null,
            color: isCurrent && _bookTheme == BookTheme.dark ? Colors.black : null,
            fontWeight: isCurrent ? FontWeight.bold : null,
          ),
        ),
      );
      lastEnd = r.end;
      wordIndex++;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return SelectableText.rich(
      TextSpan(
        style: TextStyle(
          fontSize: _fontSize,
          height: 1.6,
          fontFamily: 'NotoSerifLao',
          color: _textColor,
        ),
        children: spans,
      ),
    );
  }

  Widget _buildHighlightedText(String text, String query) {
    return TextField(
      controller: _SearchHighlightController(
        text: text,
        query: query,
        isDark: _bookTheme == BookTheme.dark,
      ),
      readOnly: true,
      showCursor: true,
      style: TextStyle(
        fontSize: _fontSize,
        height: 1.6,
        fontFamily: 'NotoSerifLao',
        color: _textColor,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      maxLines: null,
    );
  }

  Widget _buildHighlightedInline(String text, String query) {
    final escaped = RegExp.escape(query);
    final regex = RegExp('($escaped)', caseSensitive: false);
    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.brown.shade900,
            backgroundColor: const Color(0xFFFFD700),
          ),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return SelectableText.rich(
      TextSpan(
        style: TextStyle(
          fontSize: _fontSize,
          fontFamily: 'NotoSerifLao',
          color: _textColor,
        ),
        children: spans,
      ),
    );
  }

  void _showPageJumpDialog() {
    final controller = TextEditingController(text: '$_currentPage');
    final cols = MediaQuery.of(context).size.width > 600 ? 10 : 7;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ໄປທີ່ໜ້າ'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '1 – $_totalPages',
                        prefixIcon: const Icon(Icons.edit),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final v = int.tryParse(controller.text);
                      if (v != null && v >= 1 && v <= _totalPages) {
                        Navigator.pop(ctx);
                        _goToPage(v);
                      }
                    },
                    child: const Text('ໄປ'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 300,
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 1.5,
                  ),
                  itemCount: _totalPages,
                  itemBuilder: (_, i) {
                    final p = i + 1;
                    final isCurrent = p == _currentPage;
                    return Material(
                      color: isCurrent
                          ? Colors.orange.shade100
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          Navigator.pop(ctx);
                          _goToPage(p);
                        },
                        child: Center(
                          child: Text(
                            '$p',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrent
                                  ? Colors.brown.shade800
                                  : Colors.brown.shade600,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ຍົກເລີກ'),
          ),
        ],
      ),
    );
  }

  void _sharePage() {
    final base = 'https://buddhaword-web.hf.space';
    final queryParam =
        widget.highlightQuery != null && widget.highlightQuery!.isNotEmpty
        ? '?q=${Uri.encodeComponent(widget.highlightQuery!)}'
        : '';
    final url =
        '$base/search-books/${widget.slug}/page/$_currentPage$queryParam';
    final title = '${widget.title} - ໜ້າ $_currentPage';
    SharePlus.instance.share(ShareParams(text: url, title: title));
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
                  color: Colors.white,
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
      _ttsWords = [];
      _ttsCurrentWordIndex = -1;
      _ttsChunkIndex = 0;
      _ttsChunkEnds = [];
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  List<_WordRange> _buildWordRanges(String text) {
    final ranges = <_WordRange>[];
    int start = -1;
    for (int i = 0; i < text.length; i++) {
      if (text[i] == ' ' ||
          text[i] == '\n' ||
          text[i] == '\t' ||
          text[i] == '\r') {
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
    final chunkStart =
        _ttsChunkIndex > 0 && _ttsChunkIndex <= _ttsChunkEnds.length
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
    if (_isLoadingAudio) return;
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
    // Reconstruct original end positions (reverse .trim() from _chunkText)
    _ttsChunkEnds = [];
    int pos = 0;
    for (final chunk in chunks) {
      final found = content.indexOf(chunk, pos);
      if (found == -1) {
        pos += chunk.length;
      } else {
        pos = found + chunk.length;
      }
      _ttsChunkEnds.add(pos);
    }

    _ttsWords = _buildWordRanges(content);
    _ttsCurrentWordIndex = -1;

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
    // ensure the frame with spinner renders before blocking on API
    await Future.delayed(Duration.zero);

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
      if (mounted) {
        setState(() {
          _position = position;
          _updateTtsWordIndex();
        });
      }
    });

    File? file = await _fetchTtsChunk(0, chunks[0]);
    if (file == null ||
        runId != _ttsRunId ||
        !mounted ||
        _audioMode != _AudioMode.tts) {
      if (mounted && _audioMode == _AudioMode.tts) {
        setState(() {
          _audioMode = _AudioMode.none;
          _isLoadingAudio = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoadingAudio = false);
    _ttsChunkIndex = 0;
    await _player.setFilePath(file.path);
    await _player.setSpeed(0.85);
    await _player.play();
    _ttsChunkBytes.add(await file.readAsBytes());
    try {
      await file.delete();
    } catch (_) {}

    for (int i = 1; i < chunks.length; i++) {
      if (runId != _ttsRunId || !mounted || _audioMode != _AudioMode.tts) break;

      Future<File?> prefetch = _fetchTtsChunk(i, chunks[i]);

      try {
        final state = _player.processingState;
        if (state != ProcessingState.completed &&
            state != ProcessingState.idle) {
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('TTS error')));
        }
        break;
      }

      _ttsChunkIndex = i;
      await _player.setFilePath(file.path);
      await _player.setSpeed(0.85);
      await _player.play();
      _ttsChunkBytes.add(await file.readAsBytes());
      try {
        await file.delete();
      } catch (_) {}
    }

    if (mounted && runId == _ttsRunId && _audioMode == _AudioMode.tts) {
      try {
        final state = _player.processingState;
        if (state != ProcessingState.completed &&
            state != ProcessingState.idle) {
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
      final file = File('${dir.path}/${widget.slug}_page$_currentPage.mp3');
      final allBytes = Uint8List(
        _ttsChunkBytes.fold(0, (sum, b) => sum + b.length),
      );
      int offset = 0;
      for (final chunk in _ttsChunkBytes) {
        allBytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      await file.writeAsBytes(allBytes);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved: ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
  }

  void _increaseFontSize() {
    setState(() => _fontSize += 2.0);
    _saveFontSize(_fontSize);
  }

  void _decreaseFontSize() {
    setState(() => _fontSize = _fontSize > 2.0 ? _fontSize - 2.0 : _fontSize);
    _saveFontSize(_fontSize);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ບໍ່ພົບຜົນການຄົ້ນຫາ')));
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: results.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
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
                      _goToPage(r.page);
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
