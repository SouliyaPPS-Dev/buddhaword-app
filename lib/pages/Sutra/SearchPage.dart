// ignore_for_file: depend_on_referenced_packages, file_names, use_key_in_widget_constructors, library_private_types_in_public_api, prefer_const_constructors, deprecated_member_use, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart'
    show AudioPlayer, PlayerState, ProcessingState, LoopMode;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as yt;

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../services/etipitaka_database_service.dart';
import '../../themes/ThemeProvider.dart';
import 'AnakameSutraContentPage.dart';
import 'BookReadingScreenPage.dart';
import 'DetailPage.dart';
import 'UttayarndhamContentPage.dart';
import 'etipitaka_content_page.dart';
import '../SearchBooks/search_books_reader_page.dart';
import '../../providers/search_books_provider.dart';

class SearchPage extends StatefulWidget {
  final String initialSource;
  final String initialQuery;

  const SearchPage({
    super.key,
    this.initialSource = 'all',
    this.initialQuery = '',
  });

  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<List<dynamic>> _data = [];
  List<List<dynamic>> _filteredData = [];
  String _searchTerm = '';
  String _selectedCategory = '';

  late String _selectedSource;
  List<Map<String, dynamic>> _externalResults = [];
  bool _isSearching = false;
  Timer? _debounceTimer;
  String _etipitakaCode = 'thai';
  final List<String> _etipitakaCodes = [
    'thai',
    'pali',
    'english',
    'burma',
    'myan',
    'sri',
    'siam',
    'chinese',
    'tibetan',
    'korean',
    'vietnamese',
    'japanese',
    'roman',
  ];

  List<String> _favorites = [];

  int? _currentlyPlayingIndex;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _currentUrl;
  bool _isRepeating = false;
  yt.YoutubePlayerController? _ytController;
  StreamSubscription<yt.YoutubeVideoState>? _ytPositionSubscription;
  StreamSubscription<yt.YoutubePlayerValue>? _ytStateSubscription;

  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  final List<Map<String, dynamic>> _sourceInfo = [
    {'key': 'all', 'label': 'ທັງໝົດ', 'icon': Icons.search},
    {'key': 'main', 'label': 'ພຣະສູດ', 'icon': Icons.auto_stories},
    {'key': 'search_books', 'label': 'ໜັງສື', 'icon': Icons.book},
    {'key': 'etipitaka', 'label': 'E-Tipitaka', 'icon': Icons.menu_book},
    {'key': 'anakame', 'label': 'Anakame', 'icon': Icons.language},
    {'key': 'uttayarndham', 'label': 'Uttayarndham', 'icon': Icons.language},
  ];

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.initialSource;
    if (widget.initialQuery.isNotEmpty) {
      _searchController.text = widget.initialQuery;
      _searchTerm = widget.initialQuery;
    }
    fetchData(_searchTerm);
    _loadFavorites();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _setupAudio(int index, String audio) async {
    try {
      if (audio.isNotEmpty && audio != '/' && audio != _currentUrl) {
        _ytController?.close();
        _ytController = null;

        if (audio.contains('youtube.com') || audio.contains('youtu.be')) {
          await _player.stop();
          _ytPositionSubscription?.cancel();
          _ytStateSubscription?.cancel();
          final videoId = yt.YoutubePlayerController.convertUrlToId(audio);
          if (videoId != null) {
            _ytController = yt.YoutubePlayerController.fromVideoId(
              videoId: videoId,
              autoPlay: true,
              params: const yt.YoutubePlayerParams(
                showControls: true,
                mute: false,
              ),
            );
            _ytPositionSubscription = _ytController!.videoStateStream.listen((
              state,
            ) {
              if (!mounted) return;
              setState(() {
                _position = state.position;
              });
            });
            _ytStateSubscription = _ytController!.stream.listen((value) {
              if (!mounted) return;
              setState(() {
                _isPlaying = value.playerState == yt.PlayerState.playing;
                if (value.metaData.duration > Duration.zero) {
                  _duration = value.metaData.duration;
                }
              });
            });
          }
          if (mounted) {
            setState(() {
              _currentUrl = audio;
              _currentlyPlayingIndex = index;
              _isPlaying = true;
            });
          }
          return;
        }

        await _player.setUrl(audio);
        _currentUrl = audio;

        _playerStateSubscription?.cancel();
        _durationSubscription?.cancel();
        _positionSubscription?.cancel();

        _playerStateSubscription = _player.playerStateStream.listen((
          playerState,
        ) {
          setState(() {
            _isPlaying = playerState.playing;
            if (playerState.processingState == ProcessingState.completed) {
              if (index < _filteredData.length - 1) {
                final nextAudio = _filteredData[index + 1][5].toString();
                _playPauseAudio(index + 1, nextAudio);
              }
            }
          });
        });

        _durationSubscription = _player.durationStream.listen((duration) {
          setState(() {
            _duration = duration ?? Duration.zero;
          });
        });

        _positionSubscription = _player.positionStream.listen((position) {
          setState(() {
            _position = position;
          });
        });

        if (mounted) {
          setState(() {
            _currentlyPlayingIndex = index;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing player: $e');
      }
      if (index < _filteredData.length - 1) {
        final nextAudio = _filteredData[index + 1][5].toString();
        _playPauseAudio(index + 1, nextAudio);
      }
    }
  }

  Future<void> _disposeAudioPlayer() async {
    _ytPositionSubscription?.cancel();
    _ytStateSubscription?.cancel();
    await _playerStateSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _player.pause();
    _ytController?.close();
    _player.dispose();
  }

  Future<void> _playPauseAudio(int index, String audioUrl) async {
    if (audioUrl.isEmpty || audioUrl == '/') {
      final nextIndex = _findNextValidAudioIndex(index);
      if (nextIndex != -1) {
        final nextAudio = _filteredData[nextIndex][5].toString();
        _playPauseAudio(nextIndex, nextAudio);
      }
      return;
    }

    bool isYouTube =
        audioUrl.contains('youtube.com') || audioUrl.contains('youtu.be');

    if (_currentlyPlayingIndex == index) {
      if (_isPlaying) {
        if (isYouTube) {
          _ytController?.pauseVideo();
        } else {
          await _player.pause();
        }
      } else {
        if (isYouTube) {
          _ytController?.playVideo();
        } else {
          await _player.play();
        }
      }
    } else {
      setState(() {
        _currentlyPlayingIndex = index;
        _isPlaying = true;
      });
      await _setupAudio(index, audioUrl);
      if (!isYouTube) {
        await _player.play();
      }
    }
  }

  void _seek(Duration position) {
    _player.seek(position);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _disposeAudioPlayer();
    _debounceTimer?.cancel();
    super.dispose();
  }

  int _findNextValidAudioIndex(int currentIndex) {
    for (int i = currentIndex + 1; i < _filteredData.length; i++) {
      final audio = _filteredData[i].length > 5
          ? _filteredData[i][5].toString()
          : '';
      if (audio.isNotEmpty && audio != '/') {
        return i;
      }
    }
    return -1;
  }

  int _findPreviousValidAudioIndex(int currentIndex) {
    for (int i = currentIndex - 1; i >= 0; i--) {
      final audio = _filteredData[i].length > 5
          ? _filteredData[i][5].toString()
          : '';
      if (audio.isNotEmpty && audio != '/') {
        return i;
      }
    }
    return -1;
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _favorites = prefs.getStringList('favorites') ?? [];
      });
    }
  }

  bool _isItemFavorited(List<dynamic> rowData) {
    final id = rowData.isNotEmpty ? rowData[0].toString() : '';
    final title = rowData.length > 1 ? rowData[1].toString() : '';
    return _favorites.any((fav) {
      final current = json.decode(fav) as Map<String, dynamic>;
      return current['id'] == id && current['title'] == title;
    });
  }

  Future<void> _toggleFavoriteItem(List<dynamic> rowData) async {
    final prefs = await SharedPreferences.getInstance();
    final id = rowData.isNotEmpty ? rowData[0].toString() : '';
    final title = rowData.length > 1 ? rowData[1].toString() : '';
    final image = rowData.length > 2 ? rowData[2].toString() : '';
    final details = rowData.length > 3 ? rowData[3].toString() : '';
    final category = rowData.length > 4 ? rowData[4].toString() : '';
    final audio = rowData.length > 5 ? rowData[5].toString() : '/';

    final item = {
      'id': id,
      'title': title,
      'image': image,
      'details': details,
      'category': category,
      'audio': audio,
    };

    final isFavorited = _isItemFavorited(rowData);
    final currentFavorites = prefs.getStringList('favorites') ?? [];

    if (isFavorited) {
      currentFavorites.removeWhere((fav) {
        final current = json.decode(fav) as Map<String, dynamic>;
        return current['id'] == id && current['title'] == title;
      });
    } else {
      currentFavorites.add(json.encode(item));
    }

    await prefs.setStringList('favorites', currentFavorites);
    if (mounted) {
      setState(() {
        _favorites = currentFavorites;
      });
    }
  }

  void _downloadAudio(String urlAudio) async {
    if (await canLaunch(urlAudio)) {
      await launch(urlAudio);
    } else {
      throw 'Could not launch $urlAudio';
    }
  }

  Future<void> fetchData(String searchTerm) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? cachedData = prefs.getString('cachedData');

    if (cachedData != null && cachedData.isNotEmpty) {
      final List<dynamic> cachedValues = json.decode(cachedData);
      _data = cachedValues.cast<List<dynamic>>();
    }
    _runSearch(searchTerm, _selectedCategory);
  }

  void _runSearch(String searchTerm, String selectedCategory) {
    _debounceTimer?.cancel();
    if (searchTerm.trim().isEmpty) {
      setState(() {
        _filteredData = [];
        _externalResults = [];
        _isSearching = false;
      });
      return;
    }
    if (_selectedSource == 'main' || _selectedSource == 'all') {
      updateData(searchTerm, selectedCategory);
    }
    if (_selectedSource != 'main') {
      if (_externalResults.isNotEmpty) {
        setState(() => _externalResults = []);
      }
      setState(() => _isSearching = true);
      _debounceTimer = Timer(const Duration(milliseconds: 400), () {
        _searchExternalSources(searchTerm);
      });
    }
  }

  void updateData(String searchTerm, String selectedCategory) {
    if (searchTerm.trim().isEmpty) {
      setState(() => _filteredData = []);
      return;
    }
    _filteredData = _data
        .where((row) {
          return row.any(
            (cell) => cell.toString().toLowerCase().contains(
              searchTerm.toLowerCase(),
            ),
          );
        })
        .where((row) => row.isNotEmpty && row[0] != '0')
        .where(
          (row) =>
              selectedCategory.isEmpty ||
              row.length > 4 && row[4] == selectedCategory,
        )
        .toList();

    setState(() {
      _filteredData = _filteredData.reversed.toList();
    });
  }

  Future<void> _searchExternalSources(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _externalResults = []);
      return;
    }

    final List<Map<String, dynamic>> results = [];

    if (_selectedSource == 'etipitaka' || _selectedSource == 'all') {
      try {
        final db = EtipitakaDatabaseService();
        final dbResults = await db.search(_etipitakaCode, query);
        for (final r in dbResults) {
          final desc = r.content.replaceAll(RegExp(r'\s+'), ' ').trim();
          final firstLine = desc.length > 120
              ? '${desc.substring(0, 120)}...'
              : desc;
          results.add({
            'source': 'etipitaka',
            'sourceLabel': 'E-Tipitaka',
            'title': 'เล่มที่ ${r.volume} · หน้า ${r.page}',
            'subtitle': firstLine,
            'payload': {
              'code': _etipitakaCode,
              'volume': r.volume,
              'page': r.page,
              'title': 'E-Tipitaka',
            },
          });
        }
      } catch (e) {
        if (kDebugMode) print('E-Tipitaka search error: $e');
      }
    }

    if (_selectedSource == 'anakame' || _selectedSource == 'all') {
      try {
        const listingUrl =
            'http://anakame.com/page/1_Sutas/main/1_Sutta_number.htm';
        final listingResponse = await http.get(
          Uri.parse(listingUrl),
          headers: {'User-Agent': 'Mozilla/5.0'},
        );
        if (listingResponse.statusCode == 200) {
          final decoded = utf8.decode(listingResponse.bodyBytes);
          final items = _parseAnakameListing(decoded);
          final q = query.toLowerCase();
          int contentFetches = 0;
          for (final item in items) {
            if (item['title'].toString().toLowerCase().contains(q)) {
              String snippet = item['number'];
              if (contentFetches < 5) {
                try {
                  final contentUrl = item['url'].toString().startsWith('http')
                      ? item['url'].toString()
                      : Uri.parse(listingUrl).resolve(item['url']).toString();
                  final contentRes = await http.get(
                    Uri.parse(contentUrl),
                    headers: {'User-Agent': 'Mozilla/5.0'},
                  );
                  if (contentRes.statusCode == 200) {
                    final text = utf8
                        .decode(contentRes.bodyBytes)
                        .replaceAll(RegExp(r'<[^>]*>'), ' ')
                        .replaceAll(RegExp(r'\s+'), ' ')
                        .trim();
                    snippet = text.length > 100
                        ? '${text.substring(0, 100)}...'
                        : text;
                  }
                } catch (_) {}
                contentFetches++;
              }
              results.add({
                'source': 'anakame',
                'sourceLabel': 'Anakame',
                'title': item['title'],
                'subtitle': snippet,
                'payload': {
                  'contentUrl': item['url'].toString().startsWith('http')
                      ? item['url'].toString()
                      : Uri.parse(listingUrl).resolve(item['url']).toString(),
                  'title': 'Anakame',
                },
              });
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('Anakame search error: $e');
      }
    }

    if (_selectedSource == 'uttayarndham' || _selectedSource == 'all') {
      try {
        final Set<String> seenUrls = {};
        for (int page = 0; page <= 3; page++) {
          final url = page == 0
              ? 'https://uttayarndham.org/dhamma-sharing'
              : 'https://uttayarndham.org/dhamma-sharing?page=$page';
          final response = await http.get(
            Uri.parse(url),
            headers: {'User-Agent': 'Mozilla/5.0'},
          );
          if (response.statusCode == 200) {
            final items = _parseUttayarndhamListing(response.body);
            final q = query.toLowerCase();
            for (final item in items) {
              final itemUrl = item['url'] as String;
              if (item['title'].toString().toLowerCase().contains(q) && seenUrls.add(itemUrl)) {
                results.add({
                  'source': 'uttayarndham',
                  'sourceLabel': 'Uttayarndham',
                  'title': item['title'],
                  'payload': {
                    'contentUrl': itemUrl.startsWith('http') ? itemUrl : 'https://uttayarndham.org$itemUrl',
                    'title': 'Uttayarndham',
                  },
                });
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('Uttayarndham search error: $e');
      }
    }

    if (_selectedSource == 'search_books' || _selectedSource == 'all') {
      try {
        final provider = context.read<SearchBooksProvider>();
        final bookResults = await provider.searchAll(query);
        for (final r in bookResults) {
          results.add({
            'source': 'search_books',
            'sourceLabel': 'ໜັງສື',
            'title': '${r.bookTitle} · ໜ້າ ${r.page}',
            'subtitle': r.snippet,
            'payload': {
              'slug': r.slug,
              'title': r.bookTitle,
              'page': r.page,
              'query': query,
            },
          });
        }
      } catch (e) {
        if (kDebugMode) print('Search books error: $e');
      }
    }

    if (mounted) {
      setState(() {
        _externalResults = results;
        _isSearching = false;
      });
    }
  }

  List<Map<String, dynamic>> _parseAnakameListing(String html) {
    final items = <Map<String, dynamic>>[];
    final tdRegex = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);
    final linkRegex = RegExp(
      r'<a\s+href="([^"]*)"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    final rows = RegExp(r'<tr>(.*?)</tr>', dotAll: true).allMatches(html);
    for (final row in rows) {
      final tds = tdRegex.allMatches(row.group(1)!).toList();
      if (tds.length < 2) continue;
      final number = tds[0].group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (number.isEmpty ||
          int.tryParse(number.replaceAll(RegExp(r'[^0-9]'), '')) == null &&
              !number.startsWith(RegExp(r'[BS]'))) {
        continue;
      }
      final linkMatch = linkRegex.firstMatch(tds[1].group(1)!);
      if (linkMatch != null) {
        final href = linkMatch.group(1)!;
        if (!href.contains('.htm')) continue;
        items.add({
          'number': number,
          'title': linkMatch
              .group(2)!
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .trim(),
          'url': href,
        });
      }
    }
    return items;
  }

  List<Map<String, dynamic>> _parseUttayarndhamListing(String html) {
    final items = <Map<String, dynamic>>[];
    final entryRegex = RegExp(
      r'<h4><a\s+href="\s*(/[^"]+)"[^>]*>\s*([^<]+?)\s*</a></h4>',
      dotAll: true,
    );
    final matches = entryRegex.allMatches(html);
    for (final m in matches) {
      items.add({'url': m.group(1)!.trim(), 'title': m.group(2)!.trim()});
    }
    if (items.isEmpty) {
      final fallbackRegex = RegExp(
        r'<a\s+href="([^"]+)"[^>]*>\s*([^<]+?)\s*</a>',
        dotAll: true,
      );
      final fallbackMatches = fallbackRegex.allMatches(html);
      for (final m in fallbackMatches) {
        final url = m.group(1)!.trim();
        final title = m.group(2)!.trim();
        if (url.contains('dhamma-sharing') && title.isNotEmpty) {
          final normalized = url.startsWith('http') ? Uri.parse(url).path : url;
          items.add({'url': normalized, 'title': title});
        }
      }
    }
    return items;
  }

  Color _sourceColor(String source) {
    switch (source) {
      case 'main':
        return Colors.brown;
      case 'etipitaka':
        return Colors.teal;
      case 'anakame':
        return Colors.indigo;
      case 'uttayarndham':
        return Colors.deepOrange;
      case 'search_books':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  TextSpan highlightSearchTerm(
    BuildContext context,
    String text,
    String searchTerm, {
    TextStyle? baseStyle,
    double highlightFontSize = 17,
    Color highlightColor = const Color(0xFFFFD700),
    Color highlightTextColor = Colors.black,
  }) {
    final theme = Theme.of(context);
    final themeStyle = theme.textTheme.bodyLarge;
    
    final effectiveStyle = (baseStyle ?? themeStyle)?.copyWith(
      fontSize: baseStyle?.fontSize ?? highlightFontSize,
      fontWeight: baseStyle?.fontWeight ?? FontWeight.bold,
      letterSpacing: baseStyle?.letterSpacing ?? 0.5,
      color: baseStyle?.color ?? themeStyle?.color,
    );

    if (searchTerm.isEmpty) {
      return TextSpan(text: text, style: effectiveStyle);
    }

    final RegExp regex = RegExp(
      RegExp.escape(searchTerm),
      caseSensitive: false,
    );
    final List<TextSpan> spans = [];
    int lastIndex = 0;

    regex.allMatches(text).forEach((match) {
      final String beforeMatch = text.substring(lastIndex, match.start);
      final String matchedText = text.substring(match.start, match.end);

      if (beforeMatch.isNotEmpty) {
        spans.add(TextSpan(text: beforeMatch, style: effectiveStyle));
      }

      spans.add(
        TextSpan(
          text: matchedText,
          style: effectiveStyle?.copyWith(
            color: highlightTextColor,
            backgroundColor: highlightColor,
          ),
        ),
      );

      lastIndex = match.end;
    });

    if (lastIndex < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastIndex),
          style: effectiveStyle,
        ),
      );
    }

    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown,
        title: const Text(
          'ຄົ້ນຫາ',
          style: TextStyle(letterSpacing: 0.5, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu_open, color: Colors.white),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          ),
          const SizedBox(width: 15),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      themeProvider.toggleTheme(!themeProvider.isDarkMode);
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          themeProvider.isDarkMode ? "☀️" : "🌙",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 15),
        ],
      ),
      drawer: const custom_nav.NavigationDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: _searchController,
                              focusNode: _focusNode,
                              style: const TextStyle(
                                fontSize: 17.0,
                                letterSpacing: 0.5,
                              ),
                              decoration: InputDecoration(
                                hintText: 'ຄົ້ນຫາ...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          setState(() {
                                            _searchController.clear();
                                            _searchTerm = '';
                                            _externalResults = [];
                                            fetchData(_searchTerm);
                                          });
                                        },
                                      )
                                    : null,
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _searchTerm = value;
                                  _runSearch(_searchTerm, _selectedCategory);
                                });
                              },
                            ),
                          ),
                          if (_selectedSource == 'main' ||
                              _selectedSource == 'all') ...[
                            const SizedBox(width: 2),
                            Expanded(
                              flex: 1,
                              child: DropdownButtonFormField<String>(
                                value: _selectedCategory.isNotEmpty
                                    ? _selectedCategory
                                    : null,
                                decoration: InputDecoration(
                                  hintText: 'ໝວດທັມ',
                                  suffixIcon: _selectedCategory.isNotEmpty
                                      ? Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _selectedCategory,
                                                textAlign: TextAlign.end,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey[600],
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.clear),
                                              onPressed: () {
                                                setState(() {
                                                  _selectedCategory = '';
                                                  if (_searchTerm.isEmpty) {
                                                    _runSearch(_searchTerm, '');
                                                  } else {
                                                    fetchData(_searchTerm);
                                                  }
                                                });
                                              },
                                            ),
                                          ],
                                        )
                                      : null,
                                ),
                                onChanged: (String? newValue) {
                                  setState(() {
                                    _selectedCategory = newValue ?? '';
                                    if (_searchTerm.isEmpty) {
                                      _runSearch(
                                        _searchTerm,
                                        _selectedCategory,
                                      );
                                    } else {
                                      fetchData(_searchTerm);
                                    }
                                  });
                                },
                                items: _data.isEmpty
                                    ? null
                                    : _data
                                          .map(
                                            (row) => row.length > 4
                                                ? row[4].toString()
                                                : '',
                                          )
                                          .toSet()
                                          .toList()
                                          .map<DropdownMenuItem<String>>((
                                            String value,
                                          ) {
                                            return DropdownMenuItem<String>(
                                              value: value,
                                              child: Text(value),
                                            );
                                          })
                                          .toList(),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _sourceInfo.map((info) {
                        final key = info['key'] as String;
                        final label = info['label'] as String;
                        final isSelected = _selectedSource == key;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(
                              label,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.brown,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: _sourceColor(key),
                            backgroundColor: Colors.brown.shade50,
                            onSelected: (selected) {
                              setState(() {
                                _selectedSource = key;
                                _externalResults = [];
                                _runSearch(_searchTerm, _selectedCategory);
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (_selectedSource == 'etipitaka')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Text(
                            'Edition: ',
                            style: TextStyle(fontSize: 13, color: Colors.brown),
                          ),
                          DropdownButton<String>(
                            value: _etipitakaCode,
                            underline: const SizedBox(),
                            items: _etipitakaCodes.map((code) {
                              return DropdownMenuItem(
                                value: code,
                                child: Text(
                                  code,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                            onChanged: (code) {
                              if (code != null) {
                                setState(() => _etipitakaCode = code);
                                _runSearch(_searchTerm, _selectedCategory);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: _selectedSource == 'main'
                  ? _buildMainResults()
                  : _selectedSource == 'all'
                  ? _buildAllResults()
                  : _buildExternalResults(),
            ),
          ],
        ),
      ),
      floatingActionButton:
          (_selectedSource == 'main' || _selectedSource == 'all') &&
              _filteredData.isNotEmpty
          ? FloatingActionButton(
              heroTag: null,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BookReadingScreenPage(
                      filteredData: _filteredData,
                      onFavoriteChanged: () => setState(() {}),
                    ),
                  ),
                );
              },
              tooltip: 'ອ່ານປຶ້ມ',
              backgroundColor: Colors.brown,
              child: const Icon(
                Icons.auto_stories_outlined,
                color: Colors.white,
              ),
            )
          : null,
    );
  }

  Widget _buildMainResults() {
    if (_filteredData.isEmpty && _searchTerm.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'ກະລຸນາປ້ອນຂໍ້ຄວາມເພື່ອຄົ້ນຫາ',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _filteredData.length,
      itemBuilder: (context, index) => _buildMainResultCard(index),
    );
  }

  Widget _buildMainResultCard(int index) {
    final rowData = _filteredData[index];
    final title = rowData.length > 1 ? rowData[1].toString() : '';
    final audio = rowData.length > 5 ? rowData[5].toString() : '/';

    final hasSearchTerm = _searchTerm.isNotEmpty;
    return Card(
      elevation: hasSearchTerm ? 12 : 8,
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15.0),
        side: hasSearchTerm
            ? BorderSide(color: Colors.brown.withOpacity(0.5), width: 2.5)
            : BorderSide.none,
      ),
      shadowColor: hasSearchTerm
          ? Color(0xFFFFD700).withOpacity(0.5)
          : Color.fromARGB(255, 91, 50, 35).withOpacity(0.9),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(15.0)),
        child: ListTile(
          title: Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Consumer<ThemeProvider>(
                    builder: (context, themeProvider, child) {
                      return RichText(
                        text: highlightSearchTerm(
                          context,
                          title,
                          _searchController.text,
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(width: 10),
                if (audio != '/')
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.brown.shade600,
                            Colors.brown.shade600,
                            Colors.brown.shade600,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          _currentlyPlayingIndex == index && _isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        iconSize: 20,
                        onPressed: () async {
                          await _playPauseAudio(index, audio);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          trailing: IconButton(
            icon: Icon(
              _isItemFavorited(rowData)
                  ? Icons.favorite
                  : Icons.favorite_border,
              color: Colors.red,
            ),
            onPressed: () => _toggleFavoriteItem(rowData),
          ),
          subtitle: audio != '/'
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_currentlyPlayingIndex == index)
                      Column(
                        children: [
                          if (audio.contains('youtube.com') ||
                              audio.contains('youtu.be'))
                            if (_ytController != null && _isPlaying)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8.0,
                                ),
                                child: yt.YoutubePlayer(
                                  controller: _ytController!,
                                  aspectRatio: 16 / 9,
                                ),
                              )
                            else
                              const SizedBox.shrink()
                          else
                            Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.skip_previous),
                                      onPressed: () {
                                        final previousIndex =
                                            _findPreviousValidAudioIndex(index);
                                        if (previousIndex != -1) {
                                          final previousAudio =
                                              _filteredData[previousIndex]
                                                      .length >
                                                  5
                                              ? _filteredData[previousIndex][5]
                                                    .toString()
                                              : '/';
                                          _playPauseAudio(
                                            previousIndex,
                                            previousAudio,
                                          );
                                        }
                                      },
                                    ),
                                    Expanded(
                                      child: Slider(
                                        min: 0.0,
                                        max: _duration.inMilliseconds
                                            .toDouble(),
                                        value: _position.inMilliseconds
                                            .toDouble()
                                            .clamp(
                                              0.0,
                                              _duration.inMilliseconds
                                                  .toDouble(),
                                            ),
                                        onChanged: (value) {
                                          _seek(
                                            Duration(
                                              milliseconds: value.toInt().clamp(
                                                0,
                                                _duration.inMilliseconds,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.skip_next),
                                      onPressed: () {
                                        final nextIndex =
                                            _findNextValidAudioIndex(index);
                                        if (nextIndex != -1) {
                                          final nextAudio =
                                              _filteredData[nextIndex].length >
                                                  5
                                              ? _filteredData[nextIndex][5]
                                                    .toString()
                                              : '/';
                                          _playPauseAudio(nextIndex, nextAudio);
                                        }
                                      },
                                    ),
                                    SizedBox(width: 0),
                                    IconButton(
                                      icon: Icon(
                                        _isRepeating
                                            ? Icons.repeat_one
                                            : Icons.repeat,
                                      ),
                                      color: Colors.brown,
                                      iconSize: 25,
                                      onPressed: () {
                                        setState(() {
                                          _isRepeating = !_isRepeating;
                                          _player.setLoopMode(
                                            _isRepeating
                                                ? LoopMode.one
                                                : LoopMode.off,
                                          );
                                        });
                                      },
                                    ),
                                    SizedBox(width: 0),
                                    IconButton(
                                      icon: Icon(Icons.download),
                                      color: Colors.brown,
                                      iconSize: 25,
                                      onPressed: () {
                                        _downloadAudio(audio);
                                      },
                                    ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_formatDuration(_position)),
                                      Text(
                                        _formatDuration(_duration - _position),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                  ],
                )
              : null,
          onTap: () async {
            if (audio != '/') {
              await _playPauseAudio(index, audio);
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DetailPage(
                  items: _filteredData
                      .map(
                        (e) => {
                          'id': e.isNotEmpty ? e[0] : '',
                          'title': e.length > 1 ? e[1] : '',
                          'details': e.length > 3 ? e[3] : '',
                          'category': e.length > 4 ? e[4] : '',
                          'audio': e.length > 5 ? e[5] : '/',
                        },
                      )
                      .toList(),
                  initialIndex: index,
                  searchTerm: _searchTerm,
                  onFavoriteChanged: () {
                    _loadFavorites();
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildExternalResults() {
    if (_searchTerm.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'ກະລຸນາປ້ອນຂໍ້ຄວາມເພື່ອຄົ້ນຫາ',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('ກຳລັງຄົ້ນຫາ...', style: TextStyle(color: Colors.brown)),
          ],
        ),
      );
    }

    if (_externalResults.isEmpty && _searchTerm.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'ບໍ່ພົບຜົນການຄົ້ນຫາ',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _externalResults.length,
      itemBuilder: (context, index) =>
          _buildExternalResultCard(_externalResults[index]),
    );
  }

  Widget _buildExternalResultCard(Map<String, dynamic> result) {
    final source = result['source'] as String;
    final sourceLabel = result['sourceLabel'] as String;
    final title = result['title'] as String;
    final subtitle = result['subtitle'] as String? ?? '';

    final hasSearchTerm = _searchTerm.isNotEmpty;
    return Card(
      elevation: hasSearchTerm ? 6 : 4,
      margin: EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: hasSearchTerm
            ? BorderSide(color: Colors.brown.withOpacity(0.5), width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: _sourceColor(source).withOpacity(0.15),
          child: Icon(
            source == 'etipitaka'
                ? Icons.menu_book
                : source == 'search_books'
                ? Icons.book
                : Icons.language,
            color: _sourceColor(source),
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: RichText(
                text: highlightSearchTerm(
                  context,
                  title,
                  _searchTerm,
                  baseStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _sourceColor(source).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                sourceLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _sourceColor(source),
                ),
              ),
            ),
          ],
        ),
        subtitle: subtitle.isNotEmpty
            ? RichText(
                text: highlightSearchTerm(
                  context,
                  subtitle,
                  _searchTerm,
                  baseStyle: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  highlightFontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        onTap: () {
          _navigateToSource(source, result['payload'] as Map<String, dynamic>);
        },
      ),
    );
  }

  Widget _buildAllResults() {
    final hasMain = _filteredData.isNotEmpty;
    final hasExternal = _externalResults.isNotEmpty;

    if (!hasMain && !hasExternal) {
      if (_searchTerm.isEmpty) {
        return _buildMainResults();
      }
      if (_isSearching) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('ກຳລັງຄົ້ນຫາ...', style: TextStyle(color: Colors.brown)),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'ບໍ່ພົບຜົນການຄົ້ນຫາ',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final mainCount = hasMain ? _filteredData.length : 0;
    final extCount = hasExternal ? _externalResults.length : 0;
    final loadingExtra = (hasMain && _isSearching) ? 1 : 0;

    return ListView.builder(
      itemCount: mainCount + extCount + loadingExtra,
      itemBuilder: (context, index) {
        if (index < mainCount) {
          return _buildMainResultCard(index);
        }
        final extIndex = index - mainCount;
        if (extIndex < extCount) {
          return _buildExternalResultCard(_externalResults[extIndex]);
        }
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  'ກຳລັງຄົ້ນຫາແຫຼ່ງອື່ນ...',
                  style: TextStyle(color: Colors.brown, fontSize: 13),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _navigateToSource(String source, Map<String, dynamic> payload) {
    switch (source) {
      case 'etipitaka':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EtipitakaContentPage(
              title: payload['title'] ?? '',
              code: payload['code'] ?? _etipitakaCode,
              volume: payload['volume'] ?? 1,
              page: payload['page'] ?? 1,
              searchQuery: _searchTerm,
            ),
          ),
        );
        break;
      case 'anakame':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AnakameSutraContentPage(
              title: payload['title'] ?? '',
              contentUrl: payload['contentUrl'] ?? '',
              searchQuery: _searchTerm,
            ),
          ),
        );
        break;
      case 'uttayarndham':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UttayarndhamContentPage(
              title: payload['title'] ?? '',
              contentUrl: payload['contentUrl'] ?? '',
              searchQuery: _searchTerm,
            ),
          ),
        );
        break;
      case 'search_books':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SearchBooksReaderPage(
              slug: payload['slug'] ?? '',
              title: payload['title'] ?? '',
              highlightQuery: payload['query'],
              initialPage: payload['page'],
            ),
          ),
        );
        break;
    }
  }
}
