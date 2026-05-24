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
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'DetailPage.dart';
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
    setState(() {
      _currentPageIndex = index;
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
                                        TextSpan(
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
                        return const Center(child: CircularProgressIndicator());
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
                size: 24, // Optional: Adjust icon size if needed
                color: Color.fromARGB(241, 179, 93, 78),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48, // Adjusted width for custom size
            height: 48, // Adjusted height for custom size
            child: FloatingActionButton(
              heroTag: 'fab2',
              onPressed: _decreaseFontSize,
              backgroundColor: const Color(0xFFF5F5F5),
              child: const Icon(
                Icons.remove,
                size: 24, // Optional: Adjust icon size if needed
                color: Color.fromARGB(241, 179, 93, 78),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48, // Adjusted width for custom size
            height: 48, // Adjusted height for custom size
            child: FloatingActionButton(
              heroTag: 'fab3',
              onPressed: _copyContentToClipboard,
              backgroundColor: const Color(0xFFF5F5F5),
              child: const Icon(
                Icons.content_copy,
                size: 24, // Optional: Adjust icon size if needed
                color: Color.fromARGB(241, 179, 93, 78),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48, // Adjusted width for custom size
            height: 48, // Adjusted height for custom size
            child: FloatingActionButton(
              heroTag: 'fab4',
              onPressed: _shareDetailLink,
              backgroundColor: const Color(0xFFF5F5F5),
              child: const Icon(
                Icons.share,
                size: 24, // Optional: Adjust icon size if needed
                color: Color.fromARGB(241, 179, 93, 78),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _shareDetailLink() {
    final currentTitle = getCurrentTitle();

    final currentRoute =
        'https://buddhaword.free.nf/sutra/details/${widget.filteredData[_currentPageIndex][0]}';

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
