// ignore_for_file: library_private_types_in_public_api, depend_on_referenced_packages, file_names, use_build_context_synchronously, unnecessary_null_comparison, prefer_const_constructors, deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart'
    show AudioPlayer, PlayerState, ProcessingState, LoopMode;
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as yt;

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'BookReadingScreenPage.dart';
import 'DetailPage.dart';
import 'SearchPage.dart';

class FavoritePage extends StatefulWidget {
  const FavoritePage({super.key});

  @override
  _FavoritePageState createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> {
  final TextEditingController _searchController = TextEditingController();

  List<String> _favorites = [];
  List<String> _filteredFavorites = []; // Add a list for filtered favorites
  String _searchTerm = '';

  int? _currentlyPlayingIndex;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _currentUrl;
  // Add the repeat functionality
  bool _isRepeating = false;
  yt.YoutubePlayerController? _ytController;

  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  int _findNextValidAudioIndex(int currentIndex) {
    for (int i = currentIndex + 1; i < _filteredFavorites.length; i++) {
      final itemData = jsonDecode(_filteredFavorites[i]);
      final audio = itemData['audio'].toString();
      if (audio.isNotEmpty && audio != '/') {
        return i;
      }
    }
    return -1; // No next valid audio
  }

  int _findPreviousValidAudioIndex(int currentIndex) {
    for (int i = currentIndex - 1; i >= 0; i--) {
      final itemData = jsonDecode(_filteredFavorites[i]);
      final audio = itemData['audio'].toString();
      if (audio.isNotEmpty && audio != '/') {
        return i;
      }
    }
    return -1; // No previous valid audio
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Load the list of favorites
      _favorites = prefs.getStringList('favorites') ?? [];
      _filteredFavorites =
          _favorites; // Initialize filtered favorites with all favorites
    });
  }

  void _filterFavorites(String query) {
    setState(() {
      _searchTerm = query;
      _filteredFavorites = _favorites.where((favorite) {
        final itemData = jsonDecode(favorite);
        final id = itemData['id'].toLowerCase();
        final title = itemData['title'].toLowerCase();
        final detail = itemData['details'].toLowerCase(); // Get details
        final category = itemData['category'].toLowerCase(); // Get category
        return id.contains(query.toLowerCase()) ||
            title.contains(
              query.toLowerCase(),
            ) || // Check if title contains query
            detail.contains(
              query.toLowerCase(),
            ) || // Check if detail contains query
            category.contains(
              query.toLowerCase(),
            ); // Check if category contains query
      }).toList();
    });
  }

  Future<void> _deleteAllFavorites() async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            "ລຶບລາຍການທີ່ຖືກໃຈທັງໝົດບໍ?",
            style: TextStyle(letterSpacing: 0.5),
          ),
          content: const Text("ທ່ານແນ່ໃຈບໍ່ວ່າຕ້ອງການລຶບລາຍການທີ່ຖືກໃຈທັງໝົດ?"),
          actions: <Widget>[
            TextButton(
              child: const Text("ຍົກເລີກ"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text("ລຶບ"),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('favorites');

                setState(() {
                  _favorites.clear();
                  _filteredFavorites.clear();
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _setupAudio(int index, String audio) async {
    try {
      if (audio.isNotEmpty && audio != '/' && audio != _currentUrl) {
        _ytController?.close();
        _ytController = null;

        if (audio.contains('youtube.com') || audio.contains('youtu.be')) {
          await _player.stop();
          final videoId = yt.YoutubePlayerController.convertUrlToId(audio);
          if (videoId != null) {
            _ytController = yt.YoutubePlayerController.fromVideoId(
              videoId: videoId,
              params: const yt.YoutubePlayerParams(
                showControls: true,
                mute: false,
              ),
            );
            _ytController?.cueVideoById(videoId: videoId);
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
              // Automatically play the next audio when current audio finishes
              if (index < _filteredFavorites.length - 1) {
                final nextAudio = jsonDecode(
                  _filteredFavorites[index + 1],
                )['audio']; // Decode and get the next audio URL
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
      // If there's an error setting up audio, try to play the next one
      if (index < _filteredFavorites.length - 1) {
        final nextAudio = jsonDecode(
          _filteredFavorites[index + 1],
        )['audio']; // Decode and get the next audio URL
        _playPauseAudio(index + 1, nextAudio);
      }
    }
  }

  Future<void> _disposeAudioPlayer() async {
    await _playerStateSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _player.pause();
    _ytController?.close();
    _player.dispose();
  }

  Future<void> _playPauseAudio(int index, String audioUrl) async {
    if (audioUrl.isEmpty || audioUrl == '/') {
      // If the current audioUrl is invalid, try to find the next valid one
      final nextIndex = _findNextValidAudioIndex(index);
      if (nextIndex != -1) {
        final nextAudio = jsonDecode(
          _filteredFavorites[nextIndex],
        )['audio'].toString();
        _playPauseAudio(nextIndex, nextAudio);
      }
      return; // Stop if no valid audio found
    }

    bool isYouTube =
        audioUrl.contains('youtube.com') || audioUrl.contains('youtu.be');

    if (_currentlyPlayingIndex == index) {
      if (isYouTube) {
        if (_isPlaying) {
          _ytController?.pauseVideo();
        } else {
          _ytController?.playVideo();
        }
        setState(() {
          _isPlaying = !_isPlaying;
        });
      } else {
        if (_player.playing) {
          await _player.pause();
        } else {
          await _player.play();
        }
      }
    } else {
      setState(() {
        _currentlyPlayingIndex = index;
        _isPlaying = true;
      });
      await _setupAudio(index, audioUrl); // Setup the new audio
      if (!isYouTube) {
        await _player.play(); // Play the audio immediately after setup
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
    _disposeAudioPlayer();

    super.dispose();
  }

  void _downloadAudio(String urlAudio) async {
    if (await canLaunch(urlAudio)) {
      await launch(urlAudio);
    } else {
      throw 'Could not launch $urlAudio';
    }
  }

  @override
  Widget build(BuildContext context) {
    TextSpan highlightSearchTerm(
      BuildContext context,
      String text,
      String searchTerm,
    ) {
      final theme = Theme.of(context);
      final textColor =
          theme.textTheme.bodyLarge?.color; // Dynamically get the color

      if (searchTerm.isEmpty) {
        return TextSpan(
          text: text,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        );
      }

      final RegExp regex = RegExp(searchTerm, caseSensitive: false);
      final List<TextSpan> spans = [];
      int lastIndex = 0;

      regex.allMatches(text).forEach((match) {
        final String beforeMatch = text.substring(lastIndex, match.start);
        final String matchedText = text.substring(match.start, match.end);

        spans.add(
          TextSpan(
            text: beforeMatch,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        );

        spans.add(
          TextSpan(
            text: matchedText,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: Colors.black, // Keep highlight color for visibility
              backgroundColor: Color(0xFFFFD700),
            ),
          ),
        );

        lastIndex = match.end;
      });

      spans.add(
        TextSpan(
          text: text.substring(lastIndex),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: textColor, // Dynamically get theme color
          ),
        ),
      );

      return TextSpan(children: spans);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_open, color: Colors.white),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: const Text(
          'ພຣະສູດຖືກໃຈ',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.white,
          ), // Adjust the font size as needed
        ),
        actions:
            _favorites
                .isNotEmpty // Show delete button only if favorites is not empty
            ? [
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SearchPage()),
                    );
                  },
                ),
                const SizedBox(width: 6), // Custom space
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.white),
                  onPressed: _deleteAllFavorites,
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
                            themeProvider.toggleTheme(
                              !themeProvider.isDarkMode,
                            );
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
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SearchPage()),
                    );
                  },
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
                            themeProvider.toggleTheme(
                              !themeProvider.isDarkMode,
                            );
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
      body: _favorites.isEmpty
          ? const Center(child: Text('No favorites added.'))
          : Padding(
              padding: const EdgeInsets.all(2.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width,
                    ), // Constrain width of the row
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(
                              fontSize: 17.0,
                              letterSpacing: 0.5,
                            ),
                            decoration: InputDecoration(
                              hintText: 'ຄົ້ນຫາ...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchTerm.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        setState(() {
                                          _searchController.clear();
                                          _searchTerm = '';
                                          _filterFavorites(_searchTerm);
                                        });
                                      },
                                    )
                                  : null,
                            ),
                            onChanged: (value) {
                              setState(() {
                                _filterFavorites(value);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _filteredFavorites.length,
                      itemBuilder: (context, index) {
                        final item = _filteredFavorites[index];
                        // Assuming each item is a JSON string, parse it
                        final itemData = jsonDecode(item);
                        final title = itemData['title'];
                        final audio = itemData['audio'];

                        return Card(
                          elevation: 8,
                          margin: EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15.0),
                          ),
                          shadowColor: Color.fromARGB(
                            255,
                            91,
                            50,
                            35,
                          ).withOpacity(0.9),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15.0),
                            ),
                            child: ListTile(
                              title: Padding(
                                padding: const EdgeInsets.only(
                                  top: 1.5,
                                ), // Add top margin here
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Expanded(
                                      child: Consumer<ThemeProvider>(
                                        builder:
                                            (context, themeProvider, child) {
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
                                    SizedBox(
                                      width: 10,
                                    ), // Space between the button and title
                                    if (audio != '/')
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
                                              _currentlyPlayingIndex == index &&
                                                      _isPlaying
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                              color: Colors.white, // Icon color
                                            ),
                                            iconSize: 20, // Smaller icon size
                                            onPressed: () async {
                                              await _playPauseAudio(
                                                index,
                                                audio,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              subtitle: audio != '/'
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (_currentlyPlayingIndex == index)
                                          Column(
                                            children: [
                                              if (audio.contains(
                                                    'youtube.com',
                                                  ) ||
                                                  audio.contains('youtu.be'))
                                                if (_ytController != null &&
                                                    _isPlaying)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 8.0,
                                                        ),
                                                    child: yt.YoutubePlayer(
                                                      controller:
                                                          _ytController!,
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
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        IconButton(
                                                          icon: Icon(
                                                            Icons.skip_previous,
                                                          ),
                                                          onPressed: () {
                                                            final previousIndex =
                                                                _findPreviousValidAudioIndex(
                                                                  index,
                                                                );
                                                            if (previousIndex !=
                                                                -1) {
                                                              final previousAudio =
                                                                  jsonDecode(
                                                                        _filteredFavorites[previousIndex],
                                                                      )['audio']
                                                                      .toString();
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
                                                          icon: Icon(
                                                            Icons.skip_next,
                                                          ),
                                                          onPressed: () {
                                                            final nextIndex =
                                                                _findNextValidAudioIndex(
                                                                  index,
                                                                );
                                                            if (nextIndex !=
                                                                -1) {
                                                              final nextAudio =
                                                                  jsonDecode(
                                                                        _filteredFavorites[nextIndex],
                                                                      )['audio']
                                                                      .toString();
                                                              _playPauseAudio(
                                                                nextIndex,
                                                                nextAudio,
                                                              );
                                                            }
                                                          },
                                                        ),
                                                        SizedBox(width: 0),
                                                        IconButton(
                                                          icon: Icon(
                                                            _isRepeating
                                                                ? Icons
                                                                      .repeat_one
                                                                : Icons.repeat,
                                                          ),
                                                          color: Colors
                                                              .brown, // Icon color
                                                          iconSize: 25,
                                                          onPressed: () {
                                                            setState(() {
                                                              _isRepeating =
                                                                  !_isRepeating;
                                                              _player.setLoopMode(
                                                                _isRepeating
                                                                    ? LoopMode
                                                                          .one
                                                                    : LoopMode
                                                                          .off,
                                                              );
                                                            });
                                                          },
                                                        ),
                                                        SizedBox(width: 0),
                                                        IconButton(
                                                          icon: Icon(
                                                            Icons.download,
                                                          ),
                                                          color: Colors
                                                              .brown, // Icon color
                                                          iconSize: 25,
                                                          onPressed: () {
                                                            _downloadAudio(
                                                              audio,
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ),
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
                                                            _formatDuration(
                                                              _position,
                                                            ),
                                                          ),
                                                          Text(
                                                            _formatDuration(
                                                              _duration -
                                                                  _position,
                                                            ),
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
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DetailPage(
                                      items: _filteredFavorites
                                          .map(
                                            (e) =>
                                                json.decode(e)
                                                    as Map<String, dynamic>,
                                          )
                                          .toList(),
                                      initialIndex: index,
                                      searchTerm: _searchTerm,
                                      onFavoriteChanged: _loadFavorites,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: _filteredFavorites.isNotEmpty
          ? FloatingActionButton(
              onPressed: () {
                // Implement your action here, e.g., navigate to book reading screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BookReadingScreenPage(
                      filteredData: _filteredFavorites.map((fav) {
                        return [
                          jsonDecode(fav)['id'],
                          jsonDecode(fav)['title'],
                          jsonDecode(fav)['image'],
                          jsonDecode(fav)['details'],
                          jsonDecode(fav)['category'],
                          jsonDecode(fav)['audio'],
                        ];
                      }).toList(),
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
}
