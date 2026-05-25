// ignore_for_file: library_private_types_in_public_api, use_key_in_widget_constructors, depend_on_referenced_packages, use_build_context_synchronously, unrelated_type_equality_checks, prefer_const_constructors, unnecessary_null_comparison, deprecated_member_use

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart'
    show AudioPlayer, PlayerState, ProcessingState, LoopMode;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as yt;

import 'layouts/NavigationDrawer.dart' as custom_nav;
import 'pages/Books/BooksPage.dart';
import 'pages/Calendar/CalendarPage.dart';
import 'pages/Sutra/CategoryListPage.dart';
import 'pages/Sutra/ContactInfoPage.dart';
import 'pages/Sutra/DetailPage.dart';
import 'pages/Sutra/FavoritePage.dart';
import 'pages/Sutra/RandomImagePage.dart';
import 'pages/Video/VideoPage.dart';
import 'providers/books_provider.dart';
import 'providers/calendar_provider.dart';
import 'providers/sutra_provider.dart';
import 'providers/video_provider.dart';
import 'pages/Video/PlayVideoPage.dart';
import 'themes/ThemeProvider.dart';

import 'pages/Sutra/SearchPage.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SutraProvider()),
        ChangeNotifierProvider(create: (_) => VideoProvider()),
        ChangeNotifierProvider(create: (_) => CalendarProvider()),
        ChangeNotifierProvider(create: (_) => BooksProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) => const MyHomePage(title: 'ພຣະສູດ & ສຽງ'),
        ),
        GoRoute(
          path: '/sutra/details/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return Consumer<SutraProvider>(
              builder: (context, sutraProvider, child) {
                if (sutraProvider.data.isEmpty) {
                  if (!sutraProvider.isLoading) {
                    Future.microtask(() => sutraProvider.fetchData());
                  }
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final sutra = sutraProvider.getSutraById(id);
                if (sutra == null) {
                  return const Scaffold(
                    body: Center(child: Text('Sutra not found')),
                  );
                }
                final initialIndex = sutraProvider.data.indexWhere(
                  (e) => e.isNotEmpty && e[0].toString() == id,
                );

                if (initialIndex == -1) {
                  return const Scaffold(
                    body: Center(child: Text('Sutra not found in data')),
                  );
                }

                return DetailPage(
                  items: sutraProvider.data
                      .map(
                        (e) => {
                          'id': e.isNotEmpty ? e[0].toString() : '',
                          'title': e.length > 1 ? e[1].toString() : '',
                          'details': e.length > 3 ? e[3].toString() : '',
                          'category': e.length > 4 ? e[4].toString() : '',
                          'audio': e.length > 5 ? e[5].toString() : '/',
                        },
                      )
                      .toList(),
                  initialIndex: initialIndex,
                  searchTerm: '',
                  onFavoriteChanged: () {},
                );
              },
            );
          },
        ),
        GoRoute(
          path: '/sutra/:category',
          builder: (context, state) {
            final category = state.pathParameters['category']!;
            return Consumer<SutraProvider>(
              builder: (context, sutraProvider, child) {
                if (sutraProvider.data.isEmpty) {
                  if (!sutraProvider.isLoading) {
                    Future.microtask(() => sutraProvider.fetchData());
                  }
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                return CategoryListPage(
                  selectedCategory: category,
                  searchTerm: '',
                );
              },
            );
          },
        ),
        GoRoute(path: '/book', builder: (context, state) => BooksPage()),
        GoRoute(
          path: '/video',
          builder: (context, state) => VideoPage(title: 'ວີດີໂອ Video'),
        ),
        GoRoute(
          path: '/video/view/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return Consumer<VideoProvider>(
              builder: (context, videoProvider, child) {
                if (videoProvider.data.isEmpty) {
                  if (!videoProvider.isLoading) {
                    Future.microtask(() => videoProvider.fetchData());
                  }
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final video = videoProvider.getVideoById(id);
                if (video == null) {
                  return const Scaffold(
                    body: Center(child: Text('Video not found')),
                  );
                }
                return PlayVideoPage(
                  id: video.isNotEmpty ? video[0].toString() : '',
                  title: video.length > 1 ? video[1].toString() : '',
                  details: video.length > 2 ? video[2].toString() : '',
                  category: video.length > 3 ? video[3].toString() : '',
                  link: video.length > 4 ? video[4].toString() : '',
                );
              },
            );
          },
        ),
        GoRoute(
          path: '/book/view/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return Consumer<BooksProvider>(
              builder: (context, booksProvider, child) {
                if (booksProvider.data.isEmpty) {
                  if (!booksProvider.isLoading) {
                    Future.microtask(() => booksProvider.fetchData());
                  }
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final book = booksProvider.getBookById(id);
                if (book != null) {
                  final link = book.length > 4 ? book[4].toString() : '';
                  if (link.isNotEmpty) {
                    Future.microtask(() => launch(link));
                  }
                }
                return BooksPage();
              },
            );
          },
        ),
        GoRoute(path: '/calendar', builder: (context, state) => CalendarPage()),
        GoRoute(
          path: '/calendar/view/:id',
          builder: (context, state) => CalendarPage(),
        ),
        GoRoute(
          path: '/favorites',
          builder: (context, state) => FavoritePage(),
        ),
        GoRoute(
          path: '/contact',
          builder: (context, state) => ContactInfoPage(),
        ),
        GoRoute(path: '/search', builder: (context, state) => SearchPage()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Buddhaword',
      theme: ThemeData(primarySwatch: Colors.brown, fontFamily: 'NotoSerifLao'),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.brown,
        fontFamily: 'NotoSerifLao',
      ),
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      routerConfig: _router,
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Delay then navigate to home
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      context.go('/');
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Approximate CSS: width: clamp(120px, 30vw, 300px)
    final double logoWidth = (screenWidth * 0.30).clamp(120.0, 300.0);

    const logos = <String>[
      'assets/buddha_nature_logo.png',
      'assets/dhammakonnon.png',
      'assets/ຮຸ່ງເເສງເເຫ່ງທັມ.png',
      'assets/tathakod_logo.png',
      'assets/ພຸທທະວົງສ໌.png',
      'assets/ວິນັຍສຸຄົຕ.png',
      'assets/ວັດບ້ານນາຈິກ.png',
      'assets/buddha_nature_logo_old.png',
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Container width ~92vw like the CSS example
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: screenWidth * 0.92),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final path in logos)
                        Semantics(
                          label: 'partner logo',
                          image: true,
                          child: Image.asset(
                            path,
                            width: logoWidth,
                            fit: BoxFit.contain,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;

  const MyHomePage({super.key, required this.title});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<String> _categories = [];
  List<List<dynamic>> _filteredData = [];
  String _searchTerm = '';

  String get title => widget.title;

  bool hasInternet = true;

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
    Provider.of<SutraProvider>(context, listen: false).fetchData();
  }

  void updateData(String searchTerm, List<List<dynamic>> data) {
    _categories = data
        .map((row) => row.length > 4 ? row[4].toString() : '')
        .toSet()
        .toList();

    _filteredData = data
        .where((row) {
          return row.any(
            (cell) => cell.toString().toLowerCase().contains(
              searchTerm.toLowerCase(),
            ),
          );
        })
        .where((row) => row.isNotEmpty && row[0] != '0')
        .toList();

    setState(() {
      _filteredData = _filteredData.reversed.toList();
    });
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

  int _findNextValidAudioIndex(int currentIndex) {
    for (int i = currentIndex + 1; i < _filteredData.length; i++) {
      final audio = _filteredData[i].length > 5 ? _filteredData[i][5].toString() : '';
      if (audio.isNotEmpty && audio != '/') {
        return i;
      }
    }
    return -1; // No next valid audio
  }

  int _findPreviousValidAudioIndex(int currentIndex) {
    for (int i = currentIndex - 1; i >= 0; i--) {
      final audio = _filteredData[i].length > 5 ? _filteredData[i][5].toString() : '';
      if (audio.isNotEmpty && audio != '/') {
        return i;
      }
    }
    return -1; // No previous valid audio
  }

  Future<void> fetchDataFromAPI(String searchTerm) async {
    final sutraProvider = Provider.of<SutraProvider>(context, listen: false);
    await sutraProvider.fetchData(searchTerm: searchTerm);
    updateData(searchTerm, sutraProvider.data);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
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

  // void _openLinkVideo() async {
  //   if (await canLaunch('https://buddhaword.free.nf/video')) {
  //     await launch('https://buddhaword.free.nf/video');
  //   } else {
  //     throw 'Could not launch';
  //   }
  // }

  // void _openLinkCalendar() async {
  //   if (await canLaunch('https://buddhaword.free.nf/calendar')) {
  //     await launch('https://buddhaword.free.nf/calendar');
  //   } else {
  //     throw 'Could not launch';
  //   }
  // }

  // Create a safer filtered list with null safety
  List<String> get safeCategories {
    if (_categories.isEmpty) return [];
    return _categories
        .where((category) => category != null && category.isNotEmpty)
        .map((category) => category.trim())
        .where((category) => category.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth < 600 ? 3 : (screenWidth > 900 ? 5 : 4);
    double aspectRatio = screenWidth < 900 ? 0.8 : 1;
    double cardHeight = screenWidth < 900 ? 200.0 : 250.0;

    TextSpan highlightSearchTerm(
      BuildContext context,
      String text,
      String searchTerm,
    ) {
      if (searchTerm.isEmpty) {
        return TextSpan(
          text: text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        );
      }

      final RegExp regex = RegExp(
        searchTerm,
        caseSensitive: false,
      ); //Case Insensitive
      final List<TextSpan> spans = [];
      int lastIndex = 0;

      regex.allMatches(text).forEach((match) {
        final String beforeMatch = text.substring(lastIndex, match.start);
        final String matchedText = text.substring(match.start, match.end);

        // Add normal text before match
        spans.add(
          TextSpan(
            text: beforeMatch,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        );

        // Add highlighted matched text
        spans.add(
          TextSpan(
            text: matchedText,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: Colors.black, // Highlight color
              backgroundColor: Color(0xFFFFD700), // Yellow highlight
            ),
          ),
        );

        lastIndex = match.end;
      });

      // Add remaining text with theme color
      spans.add(
        TextSpan(
          text: text.substring(lastIndex),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
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
        title: Image.asset('assets/buddha_nature_logo.png', height: 36),
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.calendar_month, color: Colors.white),
          //   onPressed: () => _openLinkCalendar(),
          // ),
          // const SizedBox(width: 10),
          // IconButton(
          //   icon: const Icon(Icons.video_library, color: Colors.white),
          //   onPressed: () => _openLinkVideo(),
          // ),
          // const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => context.push('/search'),
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.update_outlined, color: Colors.white),
            onPressed: () async {
              await fetchDataFromAPI(_searchTerm);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Information has been successfully updated'),
                  duration: Duration(seconds: 2),
                  backgroundColor:
                      Colors.green, // Set the background color to green
                ),
              );
            },
          ),
          const SizedBox(width: 10),
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
      body: Consumer<SutraProvider>(
        builder: (context, sutraProvider, child) {
          if (sutraProvider.isLoading && sutraProvider.data.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (sutraProvider.data.isEmpty) {
            return RandomImagePage();
          }

          // Use provider data
          _categories = sutraProvider.categories;

          // Re-filter if search term is active
          if (_searchTerm.isNotEmpty) {
            _filteredData = sutraProvider.data
                .where((row) {
                  return row.any(
                    (cell) => cell.toString().toLowerCase().contains(
                      _searchTerm.toLowerCase(),
                    ),
                  );
                })
                .where((row) => row.isNotEmpty && row[0] != '0')
                .toList()
                .reversed
                .toList();
          }

          return Padding(
            padding: const EdgeInsets.all(1.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 17.0),
                  decoration: InputDecoration(
                    hintText: 'ຄົ້ນຫາພຣະສູດ...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchTerm = '';
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchTerm = value;
                    });
                  },
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: _searchTerm.isEmpty
                      ? GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 1.0,
                                crossAxisSpacing: 1.0,
                                childAspectRatio: aspectRatio,
                              ),
                          itemCount: _categories.length,
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            final imageAsset = 'assets/$category.jpg';
                            return GestureDetector(
                              onTap: () {
                                context.push('/sutra/$category');
                              },
                              child: Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: AspectRatio(
                                  aspectRatio: aspectRatio,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(2),
                                              ),
                                          child: AspectRatio(
                                            aspectRatio: aspectRatio,
                                            child: FutureBuilder<bool>(
                                              future: _checkAssetExists(
                                                imageAsset,
                                              ),
                                              builder: (context, snapshot) {
                                                if (snapshot.connectionState ==
                                                    ConnectionState.waiting) {
                                                  // Loading state
                                                  return const Center(
                                                    child:
                                                        CircularProgressIndicator(),
                                                  );
                                                } else if (snapshot.hasData &&
                                                    snapshot.data!) {
                                                  // Asset exists, load it
                                                  return Image.asset(
                                                    imageAsset,
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    height: cardHeight,
                                                  );
                                                } else {
                                                  // Asset doesn't exist, load default image
                                                  return Image.asset(
                                                    'assets/default_image_old.jpg',
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    height: cardHeight,
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Container(
                                                alignment: Alignment.center,
                                                child: Text(
                                                  category,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 0.5,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          itemCount: _filteredData.length,
                          itemBuilder: (context, index) {
                            final rowData = _filteredData[index];
                            final id = rowData.isNotEmpty ? rowData[0].toString() : '';
                            final title = rowData.length > 1 ? rowData[1].toString() : '';
                            final audio = rowData.length > 5 ? rowData[5].toString() : '/';

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
                                    padding: const EdgeInsets.only(top: 1.5),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Expanded(
                                          child: RichText(
                                            text: highlightSearchTerm(
                                              context,
                                              title,
                                              _searchTerm,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
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
                                                  _currentlyPlayingIndex ==
                                                              index &&
                                                          _isPlaying
                                                      ? Icons.pause
                                                      : Icons.play_arrow,
                                                  color: Colors.white,
                                                ),
                                                iconSize: 20,
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
                                                      audio.contains(
                                                        'youtu.be',
                                                      ))
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
                                                                Icons
                                                                    .skip_previous,
                                                              ),
                                                              onPressed: () {
                                                                final previousIndex =
                                                                    _findPreviousValidAudioIndex(
                                                                      index,
                                                                    );
                                                                if (previousIndex !=
                                                                    -1) {
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
                                                                            _duration.inMilliseconds,
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
                                                                    ? Icons
                                                                          .repeat_one
                                                                    : Icons
                                                                          .repeat,
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
                                                                horizontal:
                                                                    14.0,
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
                                    if (id.isNotEmpty) {
                                      context.push('/sutra/details/$id');
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
          );
        },
      ),
    );
  }

  Future<bool> _checkAssetExists(String assetName) async {
    try {
      // Load the asset as a byte list
      final ByteData data = await rootBundle.load(assetName);
      return data.buffer.asUint8List().isNotEmpty; // If not empty, asset exists
    } catch (e) {
      return false; // Error loading asset, asset doesn't exist
    }
  }
}
