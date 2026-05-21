// ignore_for_file: library_private_types_in_public_api, file_names, prefer_const_constructors, unnecessary_null_comparison, deprecated_member_use
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/sutra_provider.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'BookReadingScreenPage.dart';
import 'DetailPage.dart';

class CategoryListPage extends StatefulWidget {
  final List<List<dynamic>>? data;
  final String selectedCategory;
  final String searchTerm;

  const CategoryListPage({
    super.key,
    this.data,
    required this.selectedCategory,
    required this.searchTerm,
  });

  @override
  _CategoryListPageState createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> {
  late List<List<dynamic>> _filteredData;
  final TextEditingController _searchController = TextEditingController();

  int? _currentlyPlayingIndex;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _currentUrl;
  // Add the repeat functionality
  bool _isRepeating = false;

  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    final data =
        widget.data ?? Provider.of<SutraProvider>(context, listen: false).data;
    _filteredData = _filterData(widget.searchTerm, data);
    _searchController.text = widget.searchTerm;
  }

  int _findNextValidAudioIndex(int currentIndex) {
    for (int i = currentIndex + 1; i < _filteredData.length; i++) {
      final audio = _filteredData[i][5].toString();
      if (audio.isNotEmpty && audio != '/') {
        return i;
      }
    }
    return -1; // No next valid audio
  }

  int _findPreviousValidAudioIndex(int currentIndex) {
    for (int i = currentIndex - 1; i >= 0; i--) {
      final audio = _filteredData[i][5].toString();
      if (audio.isNotEmpty && audio != '/') {
        return i;
      }
    }
    return -1; // No previous valid audio
  }

  Future<void> _setupAudio(int index, String audio) async {
    try {
      if (audio.isNotEmpty && audio != '/' && audio != _currentUrl) {
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
    await _playerStateSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _player.pause();
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

    if (_currentlyPlayingIndex == index) {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } else {
      setState(() {
        _currentlyPlayingIndex = index;
      });
      await _setupAudio(index, audioUrl); // Setup the new audio
      await _player.play(); // Play the audio immediately after setup
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

  void _downloadAudio(String urlAudio) async {
    if (await canLaunch(urlAudio)) {
      await launch(urlAudio);
    } else {
      throw 'Could not launch $urlAudio';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _disposeAudioPlayer();

    super.dispose();
  }

  List<List<dynamic>> _filterData(String searchTerm, List<List<dynamic>> data) {
    return data
        .where(
          (row) =>
              row.length > 4 &&
              row[4] == widget.selectedCategory &&
              row.any(
                (cell) => cell.toString().toLowerCase().contains(
                  searchTerm.toLowerCase(),
                ),
              ),
        )
        .toList();
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
        title: Text(
          widget.selectedCategory,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(2.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 17.0, letterSpacing: 0.5),
              decoration: InputDecoration(
                hintText: 'ຄົ້ນຫາພຣະສູດ...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            final data =
                                widget.data ??
                                Provider.of<SutraProvider>(
                                  context,
                                  listen: false,
                                ).data;
                            _filteredData = _filterData('', data);
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  final data =
                      widget.data ??
                      Provider.of<SutraProvider>(context, listen: false).data;
                  _filteredData = _filterData(value, data);
                });
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredData.length,
              itemBuilder: (context, index) {
                final rowData = _filteredData[index];
                final id = rowData[0].toString();
                final title = rowData[1]
                    .toString(); // Assuming the first column contains the title
                final detailLink = rowData[3]
                    .toString(); // Assuming the second column contains the detail link
                final category = rowData[4].toString();
                final audio = rowData[5].toString();

                return Card(
                  elevation: 8,
                  margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15.0),
                  ),
                  shadowColor: Color.fromARGB(255, 91, 50, 35).withOpacity(0.9),
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
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          IconButton(
                                            icon: Icon(Icons.skip_previous),
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
                                          SizedBox(width: 0),
                                          IconButton(
                                            icon: Icon(Icons.download),
                                            color: Colors.brown, // Icon color
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
                            )
                          : null,
                      onTap: () {
                        // Navigate to detail page or perform other actions
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DetailPage(
                              id: id,
                              title: title,
                              details: detailLink,
                              category: category,
                              audio: audio,
                              searchTerm: _searchController.text,
                              onFavoriteChanged: () => setState(() {}),
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
