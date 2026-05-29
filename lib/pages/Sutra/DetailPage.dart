// ignore_for_file: depend_on_referenced_packages, file_names, use_key_in_widget_constructors, library_private_types_in_public_api, unrelated_type_equality_checks, prefer_const_constructors, avoid_web_libraries_in_flutter, unused_local_variable, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:just_audio/just_audio.dart'
    show AudioPlayer, PlayerState, LoopMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'RandomImagePage.dart';
import 'SearchPage.dart';

class DetailPage extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final int initialIndex;
  final String searchTerm;
  final VoidCallback onFavoriteChanged;

  const DetailPage({
    required this.items,
    required this.initialIndex,
    required this.searchTerm,
    required this.onFavoriteChanged,
  });

  @override
  _DetailPageState createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late PageController _pageController;
  late int _currentIndex;
  double _fontSize = 18.0;
  bool _isFavorited = false;
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isRepeating = false;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  bool _isFullScreen = false;
  bool _playerReady = false;
  bool _isLoadingAudio = false;

  bool get _isDarkMode => context.watch<ThemeProvider>().isDarkMode;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  String _extractUrl(String raw) {
    if (raw == '/') return raw;
    final match = RegExp(r'https?://[^\s]+').firstMatch(raw.toString());
    return match?.group(0) ?? raw.toString();
  }

  String _getAudioUrl() {
    return _extractUrl(widget.items[_currentIndex]['audio'] ?? '/');
  }

  bool _isYouTubeAudio(String url) =>
      url.contains('youtube.com') || url.contains('youtu.be');

  String? _extractVideoId(String url) {
    if (!_isYouTubeAudio(url)) return null;
    final regex = RegExp(
      r'(?:youtube\.com/watch\?v=|youtu\.be/|youtube\.com/embed/)([a-zA-Z0-9_-]{11})',
    );
    final match = regex.firstMatch(url);
    return match?.group(1);
  }

  Future<void> _setupYouTubeAudio(String url) async {
    final videoId = _extractVideoId(url);
    if (videoId == null) {
      if (mounted) {
        setState(() => _isLoadingAudio = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid YouTube URL')));
      }
      return;
    }

    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);

      StreamInfo? audioStream = manifest.muxed.firstOrNull;
      audioStream ??= manifest.audioOnly.firstOrNull;
      if (audioStream == null) {
        if (mounted) {
          setState(() => _isLoadingAudio = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No audio stream found')),
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/yt_$videoId.${audioStream.container.name}',
      );

      if (!file.existsSync()) {
        final stream = yt.videos.streamsClient.get(audioStream);
        final sink = file.openWrite();
        await stream.pipe(sink);
        await sink.flush();
      }

      await _player.stop();
      _playerStateSubscription?.cancel();
      _durationSubscription?.cancel();
      _positionSubscription?.cancel();

      await _player.setFilePath(file.path);
      _playerStateSubscription = _player.playerStateStream.listen((
        playerState,
      ) {
        if (mounted) {
          setState(() {
            _isPlaying = playerState.playing;
          });
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
      if (mounted) {
        setState(() {
          _playerReady = true;
          _isLoadingAudio = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAudio = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Audio error: $e')));
      }
    } finally {
      yt.close();
    }
  }

  Future<void> _setupDirectAudio(String audioUrl) async {
    await _player.stop();
    await _player.setUrl(audioUrl);
    _playerStateSubscription?.cancel();
    _playerStateSubscription = _player.playerStateStream.listen((playerState) {
      if (mounted) {
        setState(() {
          _isPlaying = playerState.playing;
        });
      }
    });
    _durationSubscription?.cancel();
    _durationSubscription = _player.durationStream.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration ?? Duration.zero;
        });
      }
    });
    _positionSubscription?.cancel();
    _positionSubscription = _player.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });
    if (mounted) {
      setState(() {
        _playerReady = true;
        _isLoadingAudio = false;
      });
    }
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _player.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _disposeAudioPlayer() {
    _player.stop();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
  }

  Future<void> _playPauseAudio() async {
    String audioUrl = _getAudioUrl();

    if (_isPlaying) {
      await _player.pause();
      return;
    }

    if (_isLoadingAudio) return;

    if (!_playerReady) {
      setState(() {
        _isLoadingAudio = true;
      });
      if (_isYouTubeAudio(audioUrl)) {
        await _setupYouTubeAudio(audioUrl);
      } else {
        await _setupDirectAudio(audioUrl);
      }
      if (!_playerReady) {
        setState(() {
          _isLoadingAudio = false;
        });
        return;
      }
    }
    try {
      await _player.play();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAudio = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Playback error: $e')));
      }
    }
  }

  String formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return [
      if (duration.inHours > 0) twoDigits(duration.inHours),
      minutes,
      seconds,
    ].join(':');
  }

  Future<void> _downloadAudio(String urlAudio) async {
    if (_isYouTubeAudio(urlAudio)) {
      if (await canLaunch(urlAudio)) {
        await launch(urlAudio);
      }
      return;
    }
    try {
      final response = await http.get(Uri.parse(urlAudio));
      if (response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final fileName = urlAudio.split('/').last;
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Downloaded: $fileName')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed')));
      }
    }
  }

  Future<void> _loadFavoriteState() async {
    final prefs = await SharedPreferences.getInstance();
    final item = widget.items[_currentIndex];
    List<String>? currentFavorites = prefs.getStringList('favorites');
    if (!mounted) return;
    if (currentFavorites != null) {
      setState(() {
        _isFavorited = currentFavorites.any((fav) {
          Map<String, dynamic> current = json.decode(fav);
          return current['id'] == item['id'] &&
              current['title'] == item['title'];
        });
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    final item = widget.items[_currentIndex];
    setState(() {
      _isFavorited = !_isFavorited;
      List<String> currentFavorites = prefs.getStringList('favorites') ?? [];
      if (_isFavorited) {
        currentFavorites.add(json.encode(item));
      } else {
        currentFavorites.removeWhere((fav) {
          Map<String, dynamic> current = json.decode(fav);
          return current['id'] == item['id'] &&
              current['title'] == item['title'];
        });
      }
      prefs.setStringList('favorites', currentFavorites);
      widget.onFavoriteChanged();
    });
  }

  void _onPageChanged(int index) {
    _player.stop();
    setState(() {
      _currentIndex = index;
      _isPlaying = false;
      _isLoadingAudio = false;
      _playerReady = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    _loadFavoriteState();
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.items[_currentIndex];

    return Scaffold(
      appBar: _isFullScreen
          ? PreferredSize(
              preferredSize: Size.zero,
              child: const SizedBox.shrink(),
            )
          : AppBar(
              backgroundColor: Colors.brown,
              title: const Text(
                'ພຣະສູດ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () {
                  _disposeAudioPlayer();
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
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: () {
                    _disposeAudioPlayer();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SearchPage()),
                    );
                  },
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
                        style: TextStyle(fontSize: 16),
                      ),
                      onPressed: () =>
                          themeProvider.toggleTheme(!themeProvider.isDarkMode),
                    );
                  },
                ),
                const SizedBox(width: 10),
              ],
            ),
      drawer: const custom_nav.NavigationDrawer(),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return _buildPageContent(item);
            },
          ),
          // Navigation Buttons Overlay
          if (!_isFullScreen && _currentIndex > 0)
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
                  onPressed: () => _pageController.previousPage(
                    duration: Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                ),
              ),
            ),
          if (!_isFullScreen && _currentIndex < widget.items.length - 1)
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
                  onPressed: () => _pageController.nextPage(
                    duration: Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
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
        ],
      ),
      floatingActionButton: _isFullScreen
          ? null
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildFAB(Icons.add, _increaseFontSize, 'fab1'),
                const SizedBox(width: 12),
                _buildFAB(Icons.remove, _decreaseFontSize, 'fab2'),
                const SizedBox(width: 12),
                _buildFAB(Icons.content_copy, _copyContentToClipboard, 'fab3'),
                const SizedBox(width: 12),
                _buildFAB(Icons.share, _shareDetailLink, 'fab4'),
              ],
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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

  Widget _buildPageContent(Map<String, dynamic> item) {
    final String audioUrl = _extractUrl(item['audio'] ?? '/');
    final bool hasAudio = audioUrl != '/';

    return Container(
      color: _isDarkMode ? Colors.black : Color.fromRGBO(246, 238, 217, 1.0),
      child: Column(
        children: [
          const SizedBox(height: 10),
          if (hasAudio) _buildAudioPlayer(audioUrl),
          Expanded(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: RepaintBoundary(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: SelectableText(
                          item['title'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Divider(
                        color: Colors.black,
                        thickness: 1,
                        height: 1,
                      ),
                      const SizedBox(height: 0),
                      _buildSutraContent(item['details']),
                      const SizedBox(height: 150),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioPlayer(String audioUrl) {
    return Center(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.brown),
                onPressed: () {
                  final newPosition = _position - const Duration(seconds: 10);
                  if (newPosition < Duration.zero) {
                    _player.seek(Duration.zero);
                  } else {
                    _player.seek(newPosition);
                  }
                },
              ),
              IconButton(
                icon: Icon(
                  _isRepeating ? Icons.repeat_one : Icons.repeat,
                  color: Colors.brown,
                ),
                onPressed: () {
                  setState(() {
                    _isRepeating = !_isRepeating;
                    _player.setLoopMode(
                      _isRepeating ? LoopMode.one : LoopMode.off,
                    );
                  });
                },
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.brown.shade600,
                child: IconButton(
                  icon: _isLoadingAudio
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                  onPressed: _playPauseAudio,
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.download, color: Colors.brown),
                onPressed: () => _downloadAudio(audioUrl),
              ),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.brown),
                onPressed: () {
                  final newPosition = _position + const Duration(seconds: 10);
                  if (newPosition > _duration) {
                    _player.seek(_duration);
                  } else {
                    _player.seek(newPosition);
                  }
                },
              ),
            ],
          ),
          if (_isPlaying || _position > Duration.zero)
            Column(
              children: [
                Slider(
                  min: 0.0,
                  max: _duration.inSeconds.toDouble(),
                  value: _position.inSeconds.toDouble().clamp(
                    0.0,
                    _duration.inSeconds.toDouble(),
                  ),
                  onChanged: (value) async {
                    await _player.seek(Duration(seconds: value.toInt()));
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatTime(_position)),
                      Text(formatTime(_duration - _position)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSutraContent(String url) {
    return FutureBuilder<String>(
      future: _fetchData(url),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final bool isMobile = constraints.maxWidth < 600;
              final double paddingValue = isMobile
                  ? 0.0
                  : constraints.maxWidth * 0.1;
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: paddingValue,
                  vertical: 16.0,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: isMobile
                          ? constraints.maxWidth
                          : constraints.maxWidth * 0.8,
                      maxWidth: constraints.maxWidth,
                    ),
                    child: SelectableText.rich(
                      TextSpan(
                        children: highlightSearchTerm(
                          context,
                          snapshot
                              .data!, // Fixed: passing fetched content, not URL
                          widget.searchTerm,
                          _fontSize,
                        ),
                      ),
                      style: TextStyle(
                        fontSize: _fontSize,
                        height: 1.8,
                        letterSpacing: 0.5,
                        color: _isDarkMode
                            ? Colors.white
                            : Color.fromRGBO(88, 74, 54, 1.0),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        } else if (snapshot.hasError) {
          return Text('Error loading content');
        } else {
          return const LoadingImage();
        }
      },
    );
  }

  List<TextSpan> highlightSearchTerm(
    BuildContext context,
    String text,
    String searchTerm,
    double fontSize,
  ) {
    final TextStyle defaultStyle = TextStyle(
      fontSize: fontSize,
      color: _isDarkMode ? Colors.white : Color.fromRGBO(88, 74, 54, 1.0),
    );

    if (searchTerm.isEmpty) {
      return parseContent(context, text, fontSize, _isDarkMode);
    }

    final RegExp regex = RegExp(searchTerm, caseSensitive: false);
    final List<TextSpan> spans = [];
    int lastIndex = 0;

    regex.allMatches(text).forEach((match) {
      final String beforeMatch = text.substring(lastIndex, match.start);
      final String matchedText = text.substring(match.start, match.end);

      spans.addAll(parseContent(context, beforeMatch, fontSize, _isDarkMode));
      spans.add(
        TextSpan(
          text: matchedText,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: fontSize,
            color: Colors.black,
            backgroundColor: const Color(0xFFFFD700),
          ),
        ),
      );
      lastIndex = match.end;
    });

    spans.addAll(
      parseContent(context, text.substring(lastIndex), fontSize, _isDarkMode),
    );
    return spans;
  }

  void _shareDetailLink() {
    final item = widget.items[_currentIndex];
    final shareText =
        '${item['title']}\n https://buddhaword.free.nf/sutra/details/${item['id']}';
    Share.share(shareText, subject: item['title']);
  }

  Future<String> _fetchData(String detail) async {
    if (!detail.startsWith('http')) {
      return detail;
    }
    try {
      final response = await http.get(Uri.parse(detail));
      if (response.statusCode == 200) {
        return response.body;
      } else {
        return 'Error: Failed to load content (Status: ${response.statusCode})';
      }
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<void> _copyContentToClipboard() async {
    final item = widget.items[_currentIndex];
    String content = await _fetchData(item['details']);
    String cleanedText = content.replaceAll(RegExp(r'<\/?b>'), '');
    Clipboard.setData(ClipboardData(text: cleanedText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content copied to clipboard')),
      );
    }
  }

  Future<void> _saveFontSizeToSharedPreferences(double fontSize) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', fontSize);
  }

  void _increaseFontSize() {
    setState(() => _fontSize += 2.0);
    _saveFontSizeToSharedPreferences(_fontSize);
  }

  void _decreaseFontSize() {
    setState(() => _fontSize = _fontSize > 2.0 ? _fontSize - 2.0 : _fontSize);
    _saveFontSizeToSharedPreferences(_fontSize);
  }
}

List<TextSpan> parseContent(
  BuildContext context,
  String content,
  double fontSize,
  bool isDarkMode,
) {
  final TextStyle defaultStyle = TextStyle(
    fontSize: fontSize,
    color: isDarkMode ? Colors.white : Color.fromRGBO(88, 74, 54, 1.0),
  );

  final List<TextSpan> children = [];
  final List<String> parts = content.split(RegExp(r'(<b>|<\/b>)'));

  for (int i = 0; i < parts.length; i++) {
    final String part = parts[i];
    if (i % 2 == 0) {
      children.add(TextSpan(text: part, style: defaultStyle));
    } else {
      children.add(
        TextSpan(
          text: part,
          style: defaultStyle.copyWith(fontWeight: FontWeight.bold),
        ),
      );
    }
  }
  return children;
}
