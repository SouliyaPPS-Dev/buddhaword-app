// ignore_for_file: depend_on_referenced_packages, file_names, use_key_in_widget_constructors, library_private_types_in_public_api, unrelated_type_equality_checks, prefer_const_constructors, avoid_web_libraries_in_flutter, unused_local_variable, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:just_audio/just_audio.dart'
    show AudioPlayer, PlayerState, LoopMode, ProcessingState;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'RandomImagePage.dart';
import 'SearchPage.dart';

enum _AudioMode { none, audio, tts }

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

  static const String _ttsBaseUrl = 'https://buddhaword-web.hf.space';
  static const int _ttsMaxChars = 50000;
  static const int _ttsChunkSize = 1200;

  _AudioMode _audioMode = _AudioMode.none;

  final List<Uint8List> _ttsChunkBytes = [];
  int _ttsRunId = 0;

  bool get _isDarkMode => context.watch<ThemeProvider>().isDarkMode;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.items.isEmpty ? 0 : widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _loadFontSizeFromSharedPreferences();
    _loadFavoriteState();
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
      await _player.setSpeed(1.0);
      _playerStateSubscription = _player.playerStateStream.listen((
        playerState,
      ) {
        if (mounted) {
          setState(() {
            _isPlaying = playerState.playing;
            if (playerState.processingState == ProcessingState.completed &&
                _audioMode == _AudioMode.audio) {
              _audioMode = _AudioMode.none;
              _playerReady = false;
              _position = Duration.zero;
              _duration = Duration.zero;
            }
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
    await _player.setSpeed(1.0);
    await _player.setUrl(audioUrl);
    _playerStateSubscription?.cancel();
    _playerStateSubscription = _player.playerStateStream.listen((playerState) {
      if (mounted) {
        setState(() {
          _isPlaying = playerState.playing;
          if (playerState.processingState == ProcessingState.completed &&
              _audioMode == _AudioMode.audio) {
            _audioMode = _AudioMode.none;
            _playerReady = false;
            _position = Duration.zero;
            _duration = Duration.zero;
          }
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

  void _disposeAudioPlayer() {
    _player.stop();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
  }

  Future<void> _playPauseAudio() async {
    final audioUrl = _getAudioUrl();
    final bool hasAudio = audioUrl != '/' && audioUrl.isNotEmpty;

    // If no audio URL, just stop TTS if active and return
    if (!hasAudio) {
      if (_audioMode == _AudioMode.tts) {
        await _player.stop();
        if (mounted) {
          setState(() {
            _audioMode = _AudioMode.none;
            _isPlaying = false;
            _playerReady = false;
            _position = Duration.zero;
            _duration = Duration.zero;
            _isLoadingAudio = false;
          });
        }
      }
      return;
    }

    // If TTS is active, stop it and start audio
    if (_audioMode == _AudioMode.tts) {
      await _player.stop();
      _playerReady = false;
      if (mounted) {
        setState(() {
          _audioMode = _AudioMode.none;
          _isPlaying = false;
          _playerReady = false;
          _position = Duration.zero;
          _duration = Duration.zero;
          _isLoadingAudio = false;
        });
      }
    }

    // If audio already loaded and playing, pause it
    if (_audioMode == _AudioMode.audio && _isPlaying) {
      await _player.pause();
      return;
    }

    // If audio already loaded and paused, resume it
    if (_audioMode == _AudioMode.audio && _playerReady) {
      await _player.play();
      return;
    }

    if (_isLoadingAudio) return;

    setState(() {
      _isLoadingAudio = true;
      _audioMode = _AudioMode.audio;
    });

    if (!_playerReady) {
      if (_isYouTubeAudio(audioUrl)) {
        await _setupYouTubeAudio(audioUrl);
      } else {
        await _setupDirectAudio(audioUrl);
      }
    }

    if (!_playerReady) {
      if (mounted) {
        setState(() {
          _isLoadingAudio = false;
          _audioMode = _AudioMode.none;
        });
      }
      return;
    }

    try {
      await _player.play();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAudio = false;
          _audioMode = _AudioMode.none;
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

  Future<void> _downloadAudio(String audioUrl) async {
    try {
      Uint8List audioData;
      String fileName;

      // 1) TTS bytes
      if (_ttsChunkBytes.isNotEmpty) {
        final int totalLength = _ttsChunkBytes.fold(0, (sum, b) => sum + b.length);
        final Uint8List allBytes = Uint8List(totalLength);
        int offset = 0;
        for (final bytes in _ttsChunkBytes) {
          allBytes.setRange(offset, offset + bytes.length, bytes);
          offset += bytes.length;
        }
        audioData = allBytes;
        final item = widget.items[_currentIndex];
        fileName = '${item['title'] ?? 'tts_audio'}.mp3';
      }
      // 2) Audio URL
      else if (audioUrl != '/') {
        final response = await http.get(Uri.parse(audioUrl));
        if (response.statusCode != 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Download failed: server error')),
            );
          }
          return;
        }
        audioData = response.bodyBytes;
        fileName = audioUrl.split('/').last;
        if (!fileName.contains('.')) fileName = '$fileName.mp3';
      }
      // 3) Nothing to download
      else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No audio to download. Play TTS first.')),
          );
        }
        return;
      }

      // Save to documents directory
      final dir = await getApplicationDocumentsDirectory();
      final String downloadDir = '${dir.path}/Downloads';
      final Directory downloadFolder = Directory(downloadDir);
      if (!await downloadFolder.exists()) {
        await downloadFolder.create(recursive: true);
      }
      final File file = File('$downloadDir/$fileName');
      await file.writeAsBytes(audioData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded: $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
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
    _ttsRunId++;
    _player.stop();
    setState(() {
      _currentIndex = index;
      _isPlaying = false;
      _isLoadingAudio = false;
      _audioMode = _AudioMode.none;
      _playerReady = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    _loadFavoriteState();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
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
          Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.items.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    return _buildPageContent(item);
                  },
                ),
              ),
              _buildTtsBar(),
            ],
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _isFullScreen
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: (_audioMode == _AudioMode.tts || _ttsChunkBytes.isNotEmpty) ? 60 : 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFAB(Icons.add, _increaseFontSize, 'fab1'),
                  const SizedBox(width: 12),
                  _buildFAB(Icons.remove, _decreaseFontSize, 'fab2'),
                  const SizedBox(width: 12),
                  _buildFAB(Icons.content_copy, _copyContentToClipboard, 'fab3'),
                  const SizedBox(width: 12),
                  _buildFAB(Icons.share, _shareDetailLink, 'fab4'),
                  const SizedBox(width: 12),
                  _buildVolumeFab(),
                ],
              ),
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

  Widget _buildPageContent(Map<String, dynamic> item) {
    final String audioUrl = _extractUrl(item['audio'] ?? '/');
    final bool hasAudio = audioUrl != '/';

    return Column(
        children: [
          const SizedBox(height: 10),
          if (hasAudio && _audioMode != _AudioMode.tts) _buildAudioPlayer(audioUrl),
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
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
          SizedBox(width: 4),
          if (_ttsChunkBytes.isNotEmpty)
            IconButton(
              icon: Icon(Icons.download, color: Colors.brown, size: 20),
              onPressed: () => _downloadAudio('/'),
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

  void _stopTts() {
    _ttsRunId++;
    _player.stop();
    _ttsChunkBytes.clear();
    setState(() {
      _audioMode = _AudioMode.none;
      _isPlaying = false;
      _playerReady = false;
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
                          _isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                        ),
                  onPressed: _playPauseAudio,
                ),
              ),
              const SizedBox(width: 10),
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
              if (_ttsChunkBytes.isNotEmpty || audioUrl != '/')
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.brown),
                  onPressed: () => _downloadAudio(audioUrl),
                ),
            ],
          ),
          Column(
            children: [
              Slider(
                min: 0.0,
                max: _duration.inSeconds.toDouble() > 0
                    ? _duration.inSeconds.toDouble()
                    : 1.0,
                value: _position.inSeconds.toDouble().clamp(
                  0.0,
                  _duration.inSeconds.toDouble() > 0
                      ? _duration.inSeconds.toDouble()
                      : 1.0,
                ),
                onChanged: (value) async {
                  if (_duration > Duration.zero) {
                    await _player.seek(Duration(seconds: value.toInt()));
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatTime(_position),
                      style: TextStyle(color: Colors.brown),
                    ),
                    Text(
                      _duration > Duration.zero
                          ? formatTime(_duration - _position)
                          : '--:--',
                      style: TextStyle(color: Colors.brown),
                    ),
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
                      key: ValueKey(snapshot.data),
                      showCursor: true,
                      cursorWidth: 2.0,
                      cursorColor: Colors.brown,
                      TextSpan(
                        children: highlightSearchTerm(
                          context,
                          snapshot.data!,
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
    // Stop existing TTS
    if (_audioMode == _AudioMode.tts) {
      await _player.stop();
      _ttsChunkBytes.clear();
      if (mounted) {
        setState(() {
          _audioMode = _AudioMode.none;
          _isPlaying = false;
          _playerReady = false;
          _position = Duration.zero;
          _duration = Duration.zero;
          _isLoadingAudio = false;
        });
      }
      return;
    }

    // Stop audio if playing
    if (_audioMode == _AudioMode.audio) {
      await _player.stop();
      _playerReady = false;
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
          _duration = Duration.zero;
          _audioMode = _AudioMode.none;
        });
      }
    }

    final item = widget.items[_currentIndex];
    String content = await _fetchData(item['details']);
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
      if (mounted) {
        setState(() {
          _isPlaying = playerState.playing;
        });
      }
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      if (mounted) setState(() => _duration = duration ?? Duration.zero);
    });
    _positionSubscription = _player.positionStream.listen((position) {
      if (mounted) setState(() => _position = position);
    });

    // Pre-fetch first chunk synchronously (nothing is playing yet)
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

    // Process remaining chunks with pre-fetch: while chunk N plays,
    // start fetching chunk N+1 in the background so it's ready when N finishes
    for (int i = 1; i < chunks.length; i++) {
      if (runId != _ttsRunId || !mounted || _audioMode != _AudioMode.tts) break;

      // Start fetching next chunk while current one is still playing
      Future<File?> prefetch = _fetchTtsChunk(i, chunks[i]);

      // Wait for current chunk playback to finish
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

      // Get the pre-fetched file (should be ready by now)
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

    // Wait for last chunk to finish playing
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
          _playerReady = false;
          _position = Duration.zero;
          _duration = Duration.zero;
        });
      }
    }
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

  void _shareDetailLink() {
    final item = widget.items[_currentIndex];
    final shareText =
        '${item['title']}\n https://buddhaword-web.hf.space/sutra/details/${item['id']}';
    Share.share(shareText, subject: item['title']);
  }

  Future<String> _fetchData(String detail) async {
    if (!detail.startsWith('http')) {
      return detail;
    }
    try {
      final response = await http.get(Uri.parse(detail));
      if (response.statusCode == 200) {
        String body = response.body.replaceAll('\uFEFF', '').trimLeft();
        body = body.replaceAll(RegExp(r'^\s*<!DOCTYPE[^>]*>\s*', dotAll: true), '');
        if (body.startsWith('<html') || body.startsWith('<head') || body.startsWith('<body')) {
          return _extractPlainText(body);
        }
        return body;
      } else {
        return 'Error: Failed to load content (Status: ${response.statusCode})';
      }
    } catch (e) {
      return 'Error: $e';
    }
  }

  String _extractPlainText(String html) {
    String text = html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<p[^>]*>'), '\n')
        .replaceAll(RegExp(r'</p>'), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'\u00A0'), ' ')
        .replaceAllMapped(RegExp(r'&#[0-9]+;'), (m) => String.fromCharCode(int.parse(m.group(0)!.substring(2, m.group(0)!.length - 1))))
        .replaceAllMapped(RegExp(r'&#x[0-9a-fA-F]+;'), (m) => String.fromCharCode(int.parse(m.group(0)!.substring(3, m.group(0)!.length - 1), radix: 16)))
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
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

  Future<void> _loadFontSizeFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final double? saved = prefs.getDouble('fontSize');
    if (saved != null && mounted) {
      setState(() {
        _fontSize = saved;
      });
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
