// ignore_for_file: depend_on_referenced_packages, file_names, use_key_in_widget_constructors, library_private_types_in_public_api, unrelated_type_equality_checks, prefer_const_constructors, avoid_web_libraries_in_flutter, unused_local_variable, deprecated_member_use
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
import 'SearchPage.dart';

class DetailPage extends StatefulWidget {
  final String id;
  final String title;
  final String details;
  final String category;
  final String audio;
  final String searchTerm; // ✅ Add searchTerm
  final VoidCallback onFavoriteChanged; // Add this line
  const DetailPage({
    required this.id,
    required this.title,
    required this.details,
    required this.category,
    required this.audio,
    required this.searchTerm,
    required this.onFavoriteChanged, // Add this line
  });
  @override
  _DetailPageState createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  double _fontSize = 18.0;
  double get fontSize => _fontSize;
  bool _isFavorited = false; // Add this line
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  // Add the repeat functionality
  bool _isRepeating = false;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  bool hasInternet =
      Connectivity().checkConnectivity() != ConnectivityResult.none;
  // check if the current theme is dark or not
  bool? isDarkMode;
  Timer? _themeCheckTimer;
  @override
  void initState() {
    super.initState();
    _loadFavoriteState();
    _loadFontSizeFromSharedPreferences();
    if (hasInternet && widget.audio != '/') {
      _initializePlayer();
    }
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

  void _initializePlayer() async {
    try {
      await _player.setUrl(widget.audio);
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
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing audio player: $e');
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _themeCheckTimer?.cancel();
    super.dispose();
  }

  void _disposeAudioPlayer() {
    // clear state playing audio
    _player.stop();
    // Cancel subscriptions here to avoid LateInitializationError
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
  }

  Future<void> _playPauseAudio() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
    if (mounted) {
      setState(() {
        _isPlaying = !_isPlaying;
      });
    }
  }

  String formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return [if (duration.inHours > 0) hours, minutes, seconds].join(':');
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
          return current['id'] == widget.id &&
              current['title'] == widget.title &&
              current['details'] == widget.details &&
              current['category'] == widget.category &&
              current['audio'] == widget.audio;
        });
      } else {
        _isFavorited = false;
        // Initialize the favorites list
        prefs.setStringList('favorites', []);
        // Initialize the favorite state for the current detail
        prefs.setBool(
          '${widget.id}_${widget.title}_${widget.details}_${widget.category}_${widget.audio}',
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
        '${widget.id}_${widget.title}_${widget.details}_${widget.category}_${widget.audio}',
        _isFavorited,
      );
      List<String> currentFavorites = prefs.getStringList('favorites') ?? [];
      if (_isFavorited) {
        currentFavorites.add(
          json.encode({
            'id': widget.id,
            'title': widget.title,
            'details': widget.details,
            'category': widget.category,
            'audio': widget.audio,
          }),
        );
      } else {
        currentFavorites.removeWhere((item) {
          Map<String, dynamic> current = json.decode(item);
          return current['id'] == widget.id &&
              current['title'] == widget.title &&
              current['details'] == widget.details &&
              current['category'] == widget.category &&
              current['audio'] == widget.audio;
        });
      }
      prefs.setStringList('favorites', currentFavorites);
      widget.onFavoriteChanged(); // Notify the parent widget
    });
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
            _disposeAudioPlayer();
            Navigator.of(context).pop();
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
          const SizedBox(width: 4),
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
          const SizedBox(width: 4),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu_open, color: Colors.white),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          ),
          const SizedBox(width: 15),
          // Add a switch to toggle dark mode
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
      body: SingleChildScrollView(
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
                  widget.title,
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
              // Add buttons to control audio playback
              if (widget.audio != '/' && hasInternet)
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
                          ), // Add horizontal padding to center the text
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
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
                                        color: Colors.white, // Icon color
                                        iconSize: 25,
                                        onPressed: _playPauseAudio,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  IconButton(
                                    icon: Icon(Icons.download),
                                    color: Colors.brown, // Icon color
                                    iconSize: 25,
                                    onPressed: () {
                                      _downloadAudio(widget.audio);
                                    },
                                  ),
                                ],
                              ),
                              if (_isPlaying || _position > Duration.zero)
                                Slider(
                                  min: 0.0,
                                  max: _duration.inSeconds.toDouble(),
                                  value: _position.inSeconds.toDouble(),
                                  onChanged: (value) async {
                                    final position = Duration(
                                      seconds: value.toInt(),
                                    );
                                    await _player.seek(position);
                                    setState(() {
                                      _position = position;
                                    });
                                  },
                                ),
                              if (_isPlaying || _position > Duration.zero)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(formatTime(_position)),
                                      Text(formatTime(_duration - _position)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 10),
              FutureBuilder<String>(
                future: _fetchData(widget.details),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final bool isMobile = constraints.maxWidth < 600;
                        final double paddingValue = isMobile
                            ? 0.0 // Smaller padding for mobile devices
                            : constraints.maxWidth *
                                  0.1; // 10% of the width as padding for larger screens
                        List<TextSpan> highlightSearchTerm(
                          BuildContext context,
                          String text,
                          String searchTerm,
                          double fontSize,
                        ) {
                          final TextStyle defaultStyle =
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontSize: fontSize,
                              ) ??
                              TextStyle(
                                fontSize: fontSize,
                                color: Colors.black,
                              );

                          final Color highlightTextColor =
                              Theme.of(context).brightness == Brightness.dark
                              ? Colors.black
                              : Colors.black;

                          if (searchTerm.isEmpty) {
                            return parseContent(
                              context,
                              text,
                              fontSize,
                            ); // ✅ Parse content normally if no search term
                          }

                          final RegExp regex = RegExp(
                            searchTerm,
                            caseSensitive: false,
                          );
                          final List<TextSpan> spans = [];
                          int lastIndex = 0;

                          regex.allMatches(text).forEach((match) {
                            final String beforeMatch = text.substring(
                              lastIndex,
                              match.start,
                            );
                            final String matchedText = text.substring(
                              match.start,
                              match.end,
                            );

                            spans.addAll(
                              parseContent(context, beforeMatch, fontSize),
                            ); // ✅ Parse before highlight

                            spans.add(
                              TextSpan(
                                text: matchedText,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: fontSize,
                                  color:
                                      highlightTextColor, // ✅ Adjusted per theme
                                  backgroundColor: const Color(
                                    0xFFFFD700,
                                  ), // Yellow highlight
                                ),
                              ),
                            );

                            lastIndex = match.end;
                          });

                          spans.addAll(
                            parseContent(
                              context,
                              text.substring(lastIndex),
                              fontSize,
                            ),
                          );

                          return spans;
                        }

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
                                      children: highlightSearchTerm(
                                        context,
                                        widget.details,
                                        widget.searchTerm,
                                        _fontSize,
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
                color: Color.fromARGB(241, 179, 93, 78),
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _shareDetailLink() {
    final shareText =
        '${widget.title}\n https://buddhaword.free.nf/sutra/details/${widget.id}';
    Share.share(shareText, subject: widget.title);
  }

  Future<String> _fetchData(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.body;
      } else {
        return '';
      }
    } catch (e) {
      return '';
    }
  }

  Future<void> _copyContentToClipboard() async {
    String copiedText = widget.details.replaceAll(
      RegExp(r'<\/?b>'),
      '',
    ); // Remove <b> and </b> tags
    Clipboard.setData(ClipboardData(text: copiedText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Content copied to clipboard')),
    );
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

List<TextSpan> parseContent(
  BuildContext context,
  String content,
  double fontSize,
) {
  final TextStyle defaultStyle =
      Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: fontSize) ??
      TextStyle(fontSize: fontSize, color: Colors.black);

  final List<TextSpan> children = [];
  final List<String> parts = content.split(RegExp(r'(<b>|<\/b>)'));

  for (int i = 0; i < parts.length; i++) {
    final String part = parts[i];

    if (i % 2 == 0) {
      // ✅ Normal text
      children.add(TextSpan(text: part, style: defaultStyle));
    } else {
      // ✅ Bold text
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
