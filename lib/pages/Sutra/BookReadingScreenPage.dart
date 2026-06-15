// ignore_for_file: file_names, avoid_web_libraries_in_flutter, unnecessary_null_comparison, depend_on_referenced_packages, unrelated_type_equality_checks, prefer_const_constructors, deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:just_audio/just_audio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'DetailPage.dart';
import 'RandomImagePage.dart';
import 'SearchPage.dart';

class BookReadingScreenPage extends StatefulWidget {
  final List<List<dynamic>> filteredData;
  final int initialPageIndex;
  final VoidCallback onFavoriteChanged; // Add this line

  const BookReadingScreenPage({
    super.key,
    required this.filteredData,
    this.initialPageIndex = 0,
    required this.onFavoriteChanged, // Add this line
  });

  @override
  State<BookReadingScreenPage> createState() => _BookReadingScreenPageState();
}

class _BookReadingScreenPageState extends State<BookReadingScreenPage> {
  double _fontSize = 18.0;
  double get fontSize => _fontSize;

  late PageController _pageController;
  int _currentPageIndex = 0;

  // check if the item is favorited on local storage data or not
  bool _isFavorited = false;

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  // Add the repeat functionality
  bool _isRepeating = false;
  int? _currentlyPlayingIndex;
  String? _currentUrl;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  bool hasInternet = false;

  static const String _ttsBaseUrl = 'https://buddhaword-web.hf.space';
  static const int _ttsChunkSize = 1200;
  static const int _maxTtsChars = 50000;
  bool _isTtsSpeaking = false;
  bool _isTtsLoading = false;
  final List<Uint8List> _ttsChunkBytes = [];
  int _ttsRunId = 0;
  List<_WordRange> _ttsWords = [];
  int _ttsCurrentWordIndex = -1;

  // check if the current theme is dark or not
  bool? isDarkMode;
  Timer? _themeCheckTimer;

  @override
  void initState() {
    super.initState();

    _initialize().then((_) {
      _initAudioPlayer();
    });

    _currentPageIndex = widget.initialPageIndex;
    _pageController = PageController(initialPage: widget.initialPageIndex);

    _checkInternetConnectivity();
  }

  // Remove redundant theme-checking timer, instead rely on Theme changes directly via the provider
  @override
  void didChangeDependencies() {
    // Track theme changes based on the current provider
    final themeProvider = Provider.of<ThemeProvider>(context);
    if (themeProvider.isDarkMode != isDarkMode) {
      setState(() {
        isDarkMode = themeProvider.isDarkMode;
      });
    }
    super.didChangeDependencies();
  }

  Future<void> _initialize() async {
    await _loadFavoriteState();
    await _loadFontSizeFromSharedPreferences();
  }

  String getCurrentID() {
    return widget.filteredData[_currentPageIndex][0].toString();
  }

  String getCurrentTitle() {
    return widget.filteredData[_currentPageIndex][1].toString();
  }

  String getCurrentDetail() {
    return widget.filteredData[_currentPageIndex][3].toString();
  }

  String getCurrentCategory() {
    return widget.filteredData[_currentPageIndex][4].toString();
  }

  String getCurrentAudio() {
    return widget.filteredData[_currentPageIndex][5].toString();
  }

  Future<void> _checkInternetConnectivity() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      hasInternet = !connectivityResult.contains(ConnectivityResult.none);
    });
    if (hasInternet && getCurrentAudio() != '/') {
      _initAudioPlayer();
    }
  }

  Future<void> _initAudioPlayer() async {
    try {
      String url = getCurrentAudio();
      if (url != null && url != '/') {
        await _player.setUrl(url);

        _playerStateSubscription = _player.playerStateStream.listen((
          playerState,
        ) {
          setState(() {
            _isPlaying = playerState.playing;
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
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing player: $e');
      }
    }
  }

  Future<void> _setupAudio(int index, String audio) async {
    try {
      if (audio != null && audio != '/' && audio != _currentUrl) {
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
              if (index < getCurrentAudio().length - 1) {
                final nextAudio = widget.filteredData[index + 1][5].toString();
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

        setState(() {
          _currentlyPlayingIndex = index;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error setting up audio: $e');
      }
    }
  }

  @override
  void dispose() {
    _ttsRunId++;
    _disposeAudioPlayer();

    _themeCheckTimer?.cancel();

    super.dispose();
  }

  void _disposeAudioPlayer() {
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _player.pause();
  }

  void _playPause() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play(); // Start playing the audio
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

  Future<void> _playPauseAudio(int index, String audioUrl) async {
    if (_currentlyPlayingIndex == index) {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } else {
      await _setupAudio(index, audioUrl);
    }
  }

  void _onPageChanged(int index) {
    _ttsRunId++;
    setState(() {
      _currentPageIndex = index;
      _isTtsSpeaking = false;
      _isTtsLoading = false;
    });
    _loadFavoriteState();

    _updateAudioPlayer();

    if (hasInternet && getCurrentAudio() != '/') {
      _setupAudio(index, getCurrentAudio());
    }
  }

  Future<void> _updateAudioPlayer() async {
    _disposeAudioPlayer(); // Dispose the current audio player
    await _initAudioPlayer(); // Re-initialize audio player on page change
  }

  void _downloadAudio(String urlAudio) async {
    if (await canLaunch(urlAudio)) {
      await launch(urlAudio);
    } else {
      throw 'Could not launch $urlAudio';
    }
  }

  Future<void> _loadFavoriteState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Check if the current detail is in favorites
      List<String>? currentFavorites = prefs.getStringList('favorites');
      if (currentFavorites != null) {
        _isFavorited = currentFavorites.any((item) {
          Map<String, dynamic> current = json.decode(item);
          return current['id'] == getCurrentID() &&
              current['title'] == getCurrentTitle() &&
              current['details'] == getCurrentDetail() &&
              current['category'] == getCurrentCategory() &&
              current['audio'] == getCurrentAudio();
        });
      } else {
        _isFavorited = false;

        // Initialize the favorites list
        prefs.setStringList('favorites', []);

        // Initialize the favorite state for the current detail

        prefs.setBool(
          '${getCurrentID()}_${getCurrentTitle()}_${getCurrentDetail()}_${getCurrentCategory()}',
          false,
        );

        // Notify the parent widget
        widget.onFavoriteChanged();

        // Load the favorite state again
        _loadFavoriteState();

        // Return to avoid calling the setState method
        return;
      }
    });
  }

  Future<void> _toggleFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isFavorited = !_isFavorited;
      prefs.setBool(
        '${getCurrentID()}_${getCurrentTitle()}_${getCurrentDetail()}_${getCurrentCategory()}',
        _isFavorited,
      );

      List<String> currentFavorites = prefs.getStringList('favorites') ?? [];
      if (_isFavorited) {
        currentFavorites.add(
          json.encode({
            'id': getCurrentID(),
            'title': getCurrentTitle(),
            'details': getCurrentDetail(),
            'category': getCurrentCategory(),
            'audio': getCurrentAudio(),
          }),
        );
      } else {
        currentFavorites.removeWhere((item) {
          Map<String, dynamic> current = json.decode(item);
          return current['id'] == getCurrentID() &&
              current['title'] == getCurrentTitle() &&
              current['details'] == getCurrentDetail() &&
              current['category'] == getCurrentCategory() &&
              current['audio'] == getCurrentAudio();
        });
      }
      prefs.setStringList('favorites', currentFavorites);

      widget.onFavoriteChanged(); // Notify the parent widget
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown,
        title: const Text(
          'ພຣະສູດ',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.white,
          ), // Adjust the font size as needed
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              // If the current route is the initial route, handle the back action differently
              Navigator.of(context).maybePop();
            }

            _disposeAudioPlayer();
          },
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorited ? Icons.favorite : Icons.favorite_border,
              color: Colors.white,
            ),
            onPressed: _toggleFavorite,
          ),
          const SizedBox(width: 5),
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
          const SizedBox(width: 5),
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
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.filteredData.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          final title = widget.filteredData[index][1].toString();
          final detailLink = widget.filteredData[index][3].toString();

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Container(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height,
              ),
              padding: const EdgeInsets.all(8.0),
              // Set the background color based on the theme
              color: isDarkMode == true
                  ? Colors
                        .black // Dark theme background color
                  : Color.fromRGBO(
                      246,
                      238,
                      217,
                      1.0,
                    ), // Light theme background color (or any other color you prefer)
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: SelectableText(
                      title,
                      textAlign: TextAlign.center,
                      toolbarOptions: const ToolbarOptions(
                        copy: true,
                        cut: true,
                        paste: true,
                        selectAll: true,
                      ),
                      showCursor: true,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Colors.black, thickness: 1, height: 1),
                  const SizedBox(height: 10),
                  Column(
                    children: [
                      if (getCurrentAudio() != '/' && hasInternet)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final bool isMobile = constraints.maxWidth < 600;
                            final double paddingValue = isMobile
                                ? 8.0 // Smaller padding for mobile devices
                                : constraints.maxWidth *
                                      0.1; // 10% of the width as padding for larger screens

                            return Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: isMobile
                                      ? constraints.maxWidth
                                      : constraints.maxWidth * 0.8,
                                  maxWidth: constraints.maxWidth,
                                ),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isMobile ? 0 : paddingValue,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              _isRepeating
                                                  ? Icons.repeat_one
                                                  : Icons.repeat,
                                            ),
                                            color: Colors.brown, // Icon color
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
                                          SizedBox(width: 10),
                                          CircleAvatar(
                                            radius:
                                                22, // Smaller radius for a smaller button
                                            backgroundColor: Colors
                                                .transparent, // Transparent background for CircleAvatar
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
                                                  _isPlaying
                                                      ? Icons.pause
                                                      : Icons.play_arrow,
                                                ),
                                                color: Colors.white,
                                                iconSize: 25,
                                                onPressed: _playPause,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 10),
                                          IconButton(
                                            icon: Icon(Icons.download),
                                            color: Colors.brown, // Icon color
                                            iconSize: 25,
                                            onPressed: () {
                                              _downloadAudio(getCurrentAudio());
                                            },
                                          ),
                                        ],
                                      ),
                                      Column(
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              if (_isPlaying &&
                                                  _position > Duration.zero &&
                                                  getCurrentAudio() != '/' &&
                                                  hasInternet)
                                                IconButton(
                                                  icon: Icon(
                                                    Icons.skip_previous,
                                                  ),
                                                  onPressed: () {
                                                    if (index > 0) {
                                                      final previousAudio = widget
                                                          .filteredData[index -
                                                              1][5]
                                                          .toString();
                                                      _playPauseAudio(
                                                        index - 1,
                                                        previousAudio,
                                                      ).then(
                                                        (value) => {
                                                          // back Pageview
                                                          _pageController
                                                              .previousPage(
                                                                duration:
                                                                    const Duration(
                                                                      milliseconds:
                                                                          500,
                                                                    ),
                                                                curve: Curves
                                                                    .easeInOut,
                                                              ),
                                                        },
                                                      );
                                                    }
                                                  },
                                                ),
                                              SizedBox(width: 5),
                                              if (_isPlaying &&
                                                  _position > Duration.zero &&
                                                  getCurrentAudio() != '/' &&
                                                  hasInternet)
                                                Expanded(
                                                  child: Slider(
                                                    min: 0.0,
                                                    max: _duration
                                                        .inMilliseconds
                                                        .toDouble(),
                                                    value: _position
                                                        .inMilliseconds
                                                        .toDouble()
                                                        .clamp(
                                                          0.0,
                                                          _duration
                                                              .inMilliseconds
                                                              .toDouble(),
                                                        ),
                                                    onChanged: (value) {
                                                      _seek(
                                                        Duration(
                                                          milliseconds: value
                                                              .toInt()
                                                              .clamp(
                                                                0,
                                                                _duration
                                                                    .inMilliseconds,
                                                              ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              IconButton(
                                                icon: Icon(Icons.skip_next),
                                                onPressed: () {
                                                  if (index <
                                                      widget
                                                              .filteredData
                                                              .length -
                                                          1) {
                                                    final nextAudio = widget
                                                        .filteredData[index +
                                                            1][5]
                                                        .toString();
                                                    _playPauseAudio(
                                                      index + 1,
                                                      nextAudio,
                                                    ).then(
                                                      (value) => {
                                                        // next pageview
                                                        _pageController.nextPage(
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    500,
                                                              ),
                                                          curve:
                                                              Curves.easeInOut,
                                                        ),
                                                      },
                                                    );
                                                  }
                                                },
                                              ),
                                            ],
                                          ),
                                          if (_isPlaying &&
                                              _position > Duration.zero &&
                                              getCurrentAudio() != '/' &&
                                              hasInternet)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16.0,
                                                  ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    _formatDuration(_position),
                                                  ),
                                                  Text(
                                                    _formatDuration(
                                                      _duration - _position,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<String>(
                    future: _fetchData(detailLink),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final bool isMobile = constraints.maxWidth < 600;
                            final double paddingValue = isMobile
                                ? 0.0 // Smaller padding for mobile devices
                                : constraints.maxWidth *
                                      0.1; // 10% of the width as padding for larger screens

                            return SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: paddingValue,
                                  vertical: 16.0,
                                ),
                                child: Align(
                                  alignment: Alignment
                                      .center, // Center align text for larger screens
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: isMobile
                                          ? constraints.maxWidth
                                          : constraints.maxWidth * 0.8,
                                      maxWidth: constraints.maxWidth,
                                    ),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 0 : paddingValue,
                                      ), // Add horizontal padding to center the text
                                      child: SelectableText.rich(
                                        _isTtsSpeaking && _ttsWords.isNotEmpty
                                            ? _buildTtsHighlightedSpan(snapshot.data!)
                                            : TextSpan(
                                                children: parseContent(
                                                  context,
                                                  snapshot.data!,
                                                  _fontSize,
                                                  isDarkMode == true,
                                                ),
                                              ),
                                        toolbarOptions: const ToolbarOptions(
                                          copy: true,
                                          cut: true,
                                          paste: true,
                                          selectAll: true,
                                        ),
                                        showCursor: true,
                                        style: TextStyle(
                                          fontSize: _fontSize,
                                          height: 1.8,
                                          textBaseline: TextBaseline.alphabetic,
                                          letterSpacing: 0.5,
                                          color: isDarkMode == true
                                              ? Colors.white
                                              : Color.fromRGBO(88, 74, 54, 1.0),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      } else if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      } else {
                        return const LoadingImage();
                      }
                    },
                  ),
                  const SizedBox(height: 150),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: FloatingActionButton(
              heroTag: 'fab1',
              onPressed: _increaseFontSize,
              backgroundColor: const Color(0xFFF5F5F5),
              child: const Icon(
                Icons.add,
                size: 24,
                color: Color.fromARGB(241, 179, 93, 78),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            height: 48,
            child: FloatingActionButton(
              heroTag: 'fab2',
              onPressed: _decreaseFontSize,
              backgroundColor: const Color(0xFFF5F5F5),
              child: const Icon(
                Icons.remove,
                size: 24,
                color: Color.fromARGB(241, 179, 93, 78),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            height: 48,
            child: FloatingActionButton(
              heroTag: 'fab3',
              onPressed: _copyContentToClipboard,
              backgroundColor: const Color(0xFFF5F5F5),
              child: const Icon(
                Icons.content_copy,
                size: 24,
                color: Color.fromARGB(241, 179, 93, 78),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            height: 48,
            child: FloatingActionButton(
              heroTag: 'fab4',
              onPressed: _shareDetailLink,
              backgroundColor: const Color(0xFFF5F5F5),
              child: const Icon(
                Icons.share,
                size: 24,
                color: Color.fromARGB(241, 179, 93, 78),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            height: 48,
            child: FloatingActionButton(
              heroTag: 'fab5',
              onPressed: _speakContent,
              backgroundColor: _isTtsSpeaking ? Colors.brown : const Color(0xFFF5F5F5),
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
                      _isTtsSpeaking ? Icons.stop : Icons.volume_up,
                      color: _isTtsSpeaking
                          ? Colors.white
                          : const Color.fromARGB(241, 179, 93, 78),
                    ),
            ),
          ),
        ],
      ),
    );
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
    if (_ttsWords.isEmpty || _duration.inMilliseconds <= 0) return;
    final progress = _position.inMilliseconds / _duration.inMilliseconds;
    final totalChars = _ttsWords.isNotEmpty ? _ttsWords.last.end : 0;
    final charIndex = (progress * totalChars).round();
    int newIndex = -1;
    for (int i = 0; i < _ttsWords.length; i++) {
      if (charIndex >= _ttsWords[i].start && charIndex < _ttsWords[i].end) {
        newIndex = i;
        break;
      }
    }
    if (newIndex != _ttsCurrentWordIndex) {
      _ttsCurrentWordIndex = newIndex;
    }
  }

  TextSpan _buildTtsHighlightedSpan(String text) {
    final clean = text.replaceAll(RegExp(r'<\/?b>'), '');
    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (int i = 0; i < _ttsWords.length; i++) {
      final r = _ttsWords[i];
      if (r.start > lastEnd) {
        spans.add(TextSpan(text: clean.substring(lastEnd, r.start)));
      }
      final wordText = clean.substring(r.start, r.end);
      final isCurrent = i == _ttsCurrentWordIndex;
      spans.add(TextSpan(
        text: wordText,
        style: TextStyle(
          backgroundColor: isCurrent ? Colors.yellow : null,
          fontWeight: isCurrent ? FontWeight.bold : null,
        ),
      ));
      lastEnd = r.end;
    }
    if (lastEnd < clean.length) {
      spans.add(TextSpan(text: clean.substring(lastEnd)));
    }
    return TextSpan(children: spans);
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
    if (_isTtsLoading) return;
    if (_isTtsSpeaking || _isTtsLoading) {
      _ttsRunId++;
      _player.stop();
      if (mounted) {
        setState(() {
          _isTtsSpeaking = false;
          _isTtsLoading = false;
          _ttsWords = [];
          _ttsCurrentWordIndex = -1;
        });
      }
      return;
    }

    String content = await _fetchData(getCurrentDetail());
    content = content.replaceAll(RegExp(r'<\/?b>'), '');
    if (content.length > _maxTtsChars) {
      content = content.substring(0, _maxTtsChars);
    }

    final chunks = _chunkText(content);
    if (chunks.isEmpty) return;

    _ttsWords = _buildWordRanges(content);
    _ttsCurrentWordIndex = -1;

    _ttsRunId++;
    final runId = _ttsRunId;
    _ttsChunkBytes.clear();

    if (mounted) {
      setState(() {
        _isTtsSpeaking = true;
        _isTtsLoading = true;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }

    await Future.delayed(Duration.zero);

    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();

    _playerStateSubscription = _player.playerStateStream.listen((playerState) {
      if (mounted) {
        setState(() {
          _isTtsSpeaking = playerState.playing;
        });
      }
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

    // Fetch and play first chunk
    File? file = await _fetchTtsChunk(0, chunks[0]);
    if (file == null || runId != _ttsRunId || !mounted) {
      if (mounted) {
        setState(() {
          _isTtsSpeaking = false;
          _isTtsLoading = false;
        });
      }
      return;
    }
    _ttsChunkBytes.add(await file.readAsBytes());
    await _player.stop();
    await _player.setFilePath(file.path);
    await _player.setSpeed(0.85);
    await _player.play();
    try {
      await file.delete();
    } catch (_) {}

    if (mounted) {
      setState(() => _isTtsLoading = false);
    }

    // Process remaining chunks: prefetch next while current plays
    for (int i = 1; i < chunks.length; i++) {
      if (runId != _ttsRunId || !mounted) break;

      Future<File?> prefetch = _fetchTtsChunk(i, chunks[i]);

      try {
        final state = _player.processingState;
        if (state != ProcessingState.completed &&
            state != ProcessingState.idle) {
          await _player.processingStateStream.firstWhere(
            (s) =>
                s == ProcessingState.completed || s == ProcessingState.idle,
          );
        }
      } catch (_) {
        break;
      }

      if (runId != _ttsRunId || !mounted) break;

      file = await prefetch;
      if (file == null) break;

      _ttsChunkBytes.add(await file.readAsBytes());
      await _player.setFilePath(file.path);
      await _player.setSpeed(0.85);
      await _player.play();
      try {
        await file.delete();
      } catch (_) {}
    }

    // Wait for last chunk to finish
    if (mounted && runId == _ttsRunId) {
      try {
        final state = _player.processingState;
        if (state != ProcessingState.completed &&
            state != ProcessingState.idle) {
          await _player.processingStateStream.firstWhere(
            (s) =>
                s == ProcessingState.completed || s == ProcessingState.idle,
          );
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isTtsSpeaking = false;
          _isTtsLoading = false;
        });
      }
    }
  }

  void _shareDetailLink() {
    final currentTitle = getCurrentTitle();

    final currentRoute =
        'https://buddhaword-web.hf.space/sutra/details/${widget.filteredData[_currentPageIndex][0]}';

    final shareText = '$currentTitle\n $currentRoute';

    Share.share(shareText, subject: currentTitle);
  }

  Future<void> _copyContentToClipboard() async {
    String detailUrl = widget.filteredData[_currentPageIndex][3].toString();
    String content = await _fetchData(detailUrl);
    String cleanedText = content.replaceAll(
      RegExp(r'<\/?b>'),
      '',
    ); // Remove <b> and </b> tags
    Clipboard.setData(ClipboardData(text: cleanedText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content copied to clipboard')),
      );
    }
  }

  Future<void> _loadFontSizeFromSharedPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final double fontSize = prefs.getDouble('fontSize') ?? 18.0;

    setState(() {
      _fontSize = fontSize;
    });
  }

  Future<void> _saveFontSizeToSharedPreferences(double fontSize) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', fontSize);
  }

  void _increaseFontSize() {
    setState(() {
      _fontSize += 2.0;
    });

    _saveFontSizeToSharedPreferences(_fontSize);
  }

  void _decreaseFontSize() {
    setState(() {
      _fontSize = _fontSize > 2.0 ? _fontSize - 2.0 : _fontSize;
    });

    _saveFontSizeToSharedPreferences(_fontSize);
  }
}

class _WordRange {
  final int start;
  final int end;
  _WordRange(this.start, this.end);
}
