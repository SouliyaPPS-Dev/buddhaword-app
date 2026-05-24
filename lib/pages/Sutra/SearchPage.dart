// ignore_for_file: depend_on_referenced_packages, file_names, use_key_in_widget_constructors, library_private_types_in_public_api, prefer_const_constructors, deprecated_member_use, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart'
    show AudioPlayer, PlayerState, ProcessingState, LoopMode;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as yt;

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'BookReadingScreenPage.dart';
import 'DetailPage.dart';

class SearchPage extends StatefulWidget {
  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<List<dynamic>> _data = [];
  List<List<dynamic>> _filteredData = [];
  String _searchTerm = '';
  String _selectedCategory = ''; // Define _selectedCategory

  int? _currentlyPlayingIndex;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _currentUrl;
  // Add the repeat functionality
  bool _isRepeating = false;
  yt.YoutubePlayerController? _ytController;
  StreamSubscription<yt.YoutubeVideoState>? _ytPositionSubscription;
  StreamSubscription<yt.YoutubePlayerValue>? _ytStateSubscription;

  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    fetchData(_searchTerm);

    // Request focus on the TextField when the widget builds
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
              // Automatically play the next audio when current audio finishes
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
      // If there's an error setting up audio, try to play the next one
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
      // If the current audioUrl is invalid, try to find the next valid one
      final nextIndex = _findNextValidAudioIndex(index);
      if (nextIndex != -1) {
        final nextAudio = _filteredData[nextIndex][5].toString();
        _playPauseAudio(nextIndex, nextAudio);
      }
      return; // Stop if no valid audio found
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

    super.dispose();
  }

  int _findNextValidAudioIndex(int currentIndex) {
    for (int i = currentIndex + 1; i < _filteredData.length; i++) {
      final audio = _filteredData[i][5].toString();
      if (audio.isNotEmpty && audio != '/') {
        return i;
      }
    }
    return -1; // No next valid audio found
  }

  int _findPreviousValidAudioIndex(int currentIndex) {
    for (int i = currentIndex - 1; i >= 0; i--) {
      final audio = _filteredData[i][5].toString();
      if (audio.isNotEmpty && audio != '/') {
        return i;
      }
    }
    return -1; // No previous valid audio found
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

    // Call updateData without _selectedCategory
    updateData(searchTerm, _selectedCategory);
  }

  void updateData(String searchTerm, String selectedCategory) {
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
      body: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(8.0),
              child: LayoutBuilder(
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
                                        fetchData(_searchTerm);
                                      });
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchTerm = value;
                              fetchData(_searchTerm);
                            });
                          },
                        ),
                      ),
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
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _selectedCategory, // Display selected category value
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
                                              updateData(
                                                _searchTerm,
                                                _selectedCategory,
                                              );
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
                                updateData(_searchTerm, _selectedCategory);
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
                  );
                },
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredData.length,
                itemBuilder: (context, index) {
                  final rowData = _filteredData[index];
                  final title = rowData[1].toString();
                  final audio = rowData[5].toString();

                  return Card(
                    elevation: 8,
                    margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
                                        await _playPauseAudio(index, audio);
                                      },
                                    ),
                                  ),
                                ),
                            ],
                          ),
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
                                          if (_ytController != null &&
                                              _isPlaying)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                                                      if (previousIndex != -1) {
                                                        final previousAudio =
                                                            _filteredData[previousIndex][5]
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
                                                    icon: Icon(Icons.skip_next),
                                                    onPressed: () {
                                                      final nextIndex =
                                                          _findNextValidAudioIndex(
                                                            index,
                                                          );
                                                      if (nextIndex != -1) {
                                                        final nextAudio =
                                                            _filteredData[nextIndex][5]
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
                                                          ? Icons.repeat_one
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
                                                              ? LoopMode.one
                                                              : LoopMode.off,
                                                        );
                                                      });
                                                    },
                                                  ),
                                                  SizedBox(width: 0),
                                                  IconButton(
                                                    icon: Icon(Icons.download),
                                                    color: Colors
                                                        .brown, // Icon color
                                                    iconSize: 25,
                                                    onPressed: () {
                                                      _downloadAudio(audio);
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
                                ],
                              )
                            : null,
                        onTap: () async {
                          {
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
                                          'id': e[0],
                                          'title': e[1],
                                          'details': e[3],
                                          'category': e[4],
                                          'audio': e[5],
                                        },
                                      )
                                      .toList(),
                                  initialIndex: index,
                                  searchTerm: _searchTerm,
                                  onFavoriteChanged: () {
                                    fetchData(_searchTerm);
                                  },
                                ),
                              ),
                            );
                          }
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
      floatingActionButton: _filteredData.isNotEmpty
          ? FloatingActionButton(
              onPressed: () {
                // Implement your action here, e.g., navigate to book reading screen
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
}
