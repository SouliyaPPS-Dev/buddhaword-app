// ignore_for_file: library_private_types_in_public_api, use_key_in_widget_constructors, depend_on_referenced_packages, use_build_context_synchronously, unrelated_type_equality_checks, prefer_const_constructors, unnecessary_null_comparison, deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'layouts/NavigationDrawer.dart' as custom_nav;
import 'pages/Sutra/CategoryListPage.dart';
import 'pages/Sutra/DetailPage.dart';
import 'pages/Sutra/RandomImagePage.dart';
import 'themes/ThemeProvider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: '',
            theme: ThemeData(
              primarySwatch: Colors.brown,
              fontFamily: 'NotoSerifLao',
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              primarySwatch: Colors.brown,
              fontFamily: 'NotoSerifLao',
            ),
            themeMode: themeProvider.isDarkMode
                ? ThemeMode.dark
                : ThemeMode.light,
            initialRoute: '/splash',
            routes: {
              '/': (context) => const MyHomePage(title: 'ພຣະສູດ & ສຽງ'),
              '/splash': (context) => const SplashScreen(),
            },
          );
        },
      ),
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
      Navigator.of(context).pushReplacementNamed('/');
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

  List<List<dynamic>> _data = [];
  List<String> _categories = [];
  List<List<dynamic>> _filteredData = [];
  String _searchTerm = '';

  String get title => widget.title;

  bool hasInternet =
      Connectivity().checkConnectivity() != ConnectivityResult.none;

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
    if (title == 'ພຣະສູດ & ສຽງ') {
      fetchData(_searchTerm);
    } else {
      fetchDataFromAPI(_searchTerm);
    }
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

  Future<void> fetchDataFromAPI(String searchTerm) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    String? cachedData = prefs.getString('cachedData');

    bool hasInternet =
        await Connectivity().checkConnectivity() != ConnectivityResult.none;

    if (!hasInternet) {
      if (cachedData != null && cachedData.isNotEmpty) {
        final List<dynamic> cachedValues = json.decode(cachedData);
        _data = cachedValues.cast<List<dynamic>>();

        // Update data with cached values
        updateData(searchTerm); // Update data here
      }
    }

    try {
      final response = await http.get(
        Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/1mKtgmZ_Is4e6P3P5lvOwIplqx7VQ3amicgienGN9zwA/values/Sheet1!1:1000000?key=AIzaSyDFjIl-SEHUsgK0sjMm7x0awpf8tTEPQjs',
        ),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final List<dynamic> sheetValues =
            jsonResponse['values'] as List<dynamic>;

        final List<List<dynamic>> values = sheetValues
            .skip(1)
            .map((row) => List<dynamic>.from(row))
            .toList();

        _data = values;
        prefs.setString('cachedData', json.encode(_data));

        // Update data with fetched values
        updateData(searchTerm); // Update data here
      } else {
        if (kDebugMode) {
          print('Failed to load data: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching data: $e');
      }
    }
  }

  Future<void> fetchData(String searchTerm) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? cachedData = prefs.getString('cachedData');

    bool hasInternet =
        await Connectivity().checkConnectivity() != ConnectivityResult.none;

    if (!hasInternet) {
      if (cachedData != null && cachedData.isNotEmpty) {
        final List<dynamic> cachedValues = json.decode(cachedData);
        _data = cachedValues.cast<List<dynamic>>();

        // Update data with cached values
        updateData(searchTerm); // Update data here
      }
    }

    if (cachedData == null || cachedData.isEmpty) {
      try {
        final response = await http.get(
          Uri.parse(
            'https://sheets.googleapis.com/v4/spreadsheets/1mKtgmZ_Is4e6P3P5lvOwIplqx7VQ3amicgienGN9zwA/values/Sheet1!1:1000000?key=AIzaSyDFjIl-SEHUsgK0sjMm7x0awpf8tTEPQjs',
          ),
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> jsonResponse = json.decode(response.body);
          final List<dynamic> sheetValues =
              jsonResponse['values'] as List<dynamic>;

          final List<List<dynamic>> values = sheetValues
              .skip(1)
              .map((row) => List<dynamic>.from(row))
              .toList();

          _data = values;
          prefs.setString('cachedData', json.encode(_data));

          // Update data with fetched values
          updateData(searchTerm); // Update data here
        } else {
          if (kDebugMode) {
            print('Failed to load data: ${response.statusCode}');
          }
        }
      } catch (e) {
        // If no internet, load data from cache
        if (cachedData != null && cachedData.isNotEmpty) {
          final List<dynamic> cachedValues = json.decode(cachedData);
          _data = cachedValues.cast<List<dynamic>>();

          // Update data with cached values
          updateData(searchTerm); // Update data here
        }
      }
    } else {
      // If no internet, load data from cache
      if (cachedData.isNotEmpty) {
        final List<dynamic> cachedValues = json.decode(cachedData);
        _data = cachedValues.cast<List<dynamic>>();

        // Update data with cached values
        updateData(searchTerm); // Update data here
      }
    }
  }

  void updateData(String searchTerm) {
    _categories = _data
        .map((row) => row.length > 4 ? row[4].toString() : '')
        .toSet()
        .toList();

    _filteredData = _data
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
  //     await launch('https://buddhaword.net/video');
  //   } else {
  //     throw 'Could not launch';
  //   }
  // }

  // void _openLinkCalendar() async {
  //   if (await canLaunch('https://buddhaword.net/calendar')) {
  //     await launch('https://buddhaword.net/calendar');
  //   } else {
  //     throw 'Could not launch';
  //   }
  // }

  void _openLinkBooks() async {
    if (await canLaunch('https://buddhaword.net/book')) {
      await launch('https://buddhaword.net/book');
    } else {
      throw 'Could not launch';
    }
  }

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
            icon: const Icon(Icons.auto_stories_outlined, color: Colors.white),
            onPressed: () => _openLinkBooks(),
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
      body: _data.isEmpty
          ? RandomImagePage()
          : Padding(
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
                                  updateData(
                                    _searchTerm,
                                  ); // Update data directly
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchTerm = value;
                        updateData(
                          _searchTerm,
                        ); // Update data when search term changes
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
                            itemCount: safeCategories.length,
                            itemBuilder: (context, index) {
                              final category = safeCategories[index];
                              final imageAsset = 'assets/$category.jpg';
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CategoryListPage(
                                        data: _data,
                                        selectedCategory: category,
                                        searchTerm: _searchTerm,
                                      ),
                                    ),
                                  );
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
                                                  if (_filteredData.isEmpty) {
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
                                                      fontWeight:
                                                          FontWeight.bold,
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
                              final id = rowData[0].toString();
                              final title = rowData[1].toString();
                              final detailLink = rowData[3].toString();
                              final category = rowData[4].toString();
                              final audio = rowData[5].toString();

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
                                              backgroundColor:
                                                  Colors.transparent,
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
                                              if (_currentlyPlayingIndex ==
                                                  index)
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
                                                            horizontal: 14.0,
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
                                          )
                                        : null,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => DetailPage(
                                            id: id,
                                            title: title,
                                            details: detailLink,
                                            category: category,
                                            audio: audio,
                                            searchTerm: _searchTerm,
                                            onFavoriteChanged: () {
                                              fetchData(_searchTerm);
                                            },
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
