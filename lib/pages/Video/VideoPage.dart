// ignore_for_file: library_private_types_in_public_api, prefer_const_constructors, use_key_in_widget_constructors, file_names, avoid_web_libraries_in_flutter, unnecessary_null_comparison, unrelated_type_equality_checks, use_build_context_synchronously, prefer_const_constructors_in_immutables, no_leading_underscores_for_local_identifiers, prefer_final_fields, depend_on_referenced_packages, unused_import, constant_identifier_names, prefer_const_declarations, deprecated_member_use

import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'CategoryListPage.dart';
import 'PlayVideoPage.dart';
import 'RandomImagePage.dart';

const initialAccessToken =
    'EAARKtLa78sIBO6y3OZBT7jHgOPfFprCZC6UZBZCsvsNONC5Jya6bZAQKFkcHMhuBJJXj88mYPUDMlhaMOoPTFI85oOQrKCgePq6dKZBrOkigQyjVEITNQPD5jT2aPZC8FH8Qu164CrcpHjBsSdr8veY2ZBe9bPeRuofKyPNycpJr9Vw68hBWEQnYBYKmY3kCAbdGHI9F3z8Qhy83wBIZApAZDZD';

class VideoPage extends StatefulWidget {
  final String title;

  VideoPage({super.key, required this.title});

  @override
  _VideoPageState createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  final TextEditingController _searchController = TextEditingController();

  String get title => widget.title;

  List<List<dynamic>> _data = [];
  List<String> _categories = [];
  List<List<dynamic>> _filteredData = [];
  String _searchTerm = '';

  bool hasInternet = false;

  Map<int, List<YoutubePlayerController>> _controllers = {};

  static String? _accessToken;

  @override
  void initState() {
    super.initState();

    _initialize();
  }

  static Future<String?> getAccessToken() async {
    if (_accessToken == null || await _isTokenExpired()) {
      _accessToken = await _refreshFacebookAccessToken();
    }
    return _accessToken;
  }

  static Future<String?> _refreshFacebookAccessToken() async {
    const clientId = '1208039927182018';
    const clientSecret = 'd720fe369470ee03f731846fa319d7cc';
    const shortLivedAccessToken = initialAccessToken;

    final refreshTokenUrl = Uri.parse(
      'https://graph.facebook.com/oauth/access_token'
      '?grant_type=fb_exchange_token'
      '&client_id=$clientId'
      '&client_secret=$clientSecret'
      '&fb_exchange_token=$shortLivedAccessToken',
    );

    final response = await http.get(refreshTokenUrl);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final accessToken = data['access_token'];
      final expiresIn = data['expires_in']; // Typically in seconds

      if (accessToken != null && expiresIn != null) {
        final prefs = await SharedPreferences.getInstance();
        final expiresAt =
            DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000);

        await prefs.setString('access_token', accessToken);
        await prefs.setInt('expires_at', expiresAt as int);

        return accessToken;
      } else {
        // Handle missing data scenario
        return null;
      }
    } else {
      // Log the error response for debugging
      return null;
    }
  }

  static Future<bool> _isTokenExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = prefs.getInt('expires_at') ?? 0;

    return DateTime.now().millisecondsSinceEpoch >= expiresAt;
  }

  Future<void> _initialize() async {
    try {
      await Future.delayed(Duration(seconds: 1));
      if (title != '') {
        await fetchDataFromAPI(_searchTerm);
      } else {
        await fetchDataOffline(_searchTerm);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Initialization error: $e');
      }
    }
  }

  @override
  void dispose() {
    for (var controllers in _controllers.values) {
      for (var controller in controllers) {
        controller.close();
      }
    }

    super.dispose();
  }

  void checkConnectivity() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    if (!connectivityResult.contains(ConnectivityResult.none)) {
      hasInternet = true;
    } else {
      hasInternet = false;
    }
  }

  // This method will return the video IDs for a particular row
  List<String> _getVideoIdsForRow(int rowIndex) {
    // Implement your logic to get the video IDs based on the row index
    // For example:
    List<String> videoIds = [];
    // Add logic to populate videoIds based on rowIndex
    return videoIds;
  }

  void _initializeControllers() {
    // Clear previous controllers
    _controllers.forEach((index, controllers) {
      for (var controller in controllers) {
        controller.close();
      }
    });
    _controllers.clear();

    // Initialize new controllers
    for (int index = 0; index < _filteredData.length; index++) {
      final videoIds = _getVideoIdsForRow(index);
      if (videoIds.isNotEmpty) {
        _controllers[index] = videoIds
            .map(
              (videoId) => YoutubePlayerController.fromVideoId(
                videoId: videoId,
                params: const YoutubePlayerParams(
                  showControls: true,
                  showFullscreenButton: true,
                ),
              ),
            )
            .toList();
      }
    }
  }

  Widget _buildVideoCard(BuildContext context, int index) {
    if (_filteredData.isEmpty ||
        index >= _filteredData.length ||
        _filteredData[index].length < 5) {
      return SizedBox.shrink(); // Prevents RangeError by returning an empty widget
    }

    if (_data.isNotEmpty && index < _data.length) {
      final id = _filteredData[index][0].toString();
      final title = _filteredData[index][1].toString();
      final details = _filteredData[index][2].toString();
      final category = _filteredData[index][3].toString();
      final videoLinks = _filteredData[index][4].toString();

      // Check if the link is from YouTube or Facebook
      final isYouTube =
          videoLinks.contains('youtube.com') || videoLinks.contains('youtu.be');
      final isFacebook = videoLinks.contains('facebook.com');

      if (isYouTube) {
        final videoId = YoutubePlayerController.convertUrlToId(
          videoLinks.trim(),
        );

        if (videoId == null) {
          return SizedBox.shrink(); // Skip invalid video links
        }

        // Get the thumbnail URL from YouTube
        final thumbnailUrl =
            'https://corsproxy.io/?https://img.youtube.com/vi/$videoId/hqdefault.jpg';

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PlayVideoPage(
                  id: id,
                  title: title,
                  details: details,
                  category: category,
                  link: videoLinks,
                ),
              ),
            );
          },
          child: Card(
            elevation: 8,
            margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15.0),
            ),
            shadowColor: Color.fromARGB(255, 91, 50, 35).withOpacity(0.9),
            child: Column(
              children: [
                // Display the thumbnail image using CachedNetworkImage
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(15.0),
                    ),
                    color: Colors.black,
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CachedNetworkImage(
                      imageUrl: thumbnailUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
                ListTile(
                  title: Padding(
                    padding: const EdgeInsets.only(top: 1.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis, // Handle overflow
                            maxLines: 2, // Limit to one line
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      if (isFacebook) {
        Future<String?> getFacebookVideoThumbnailUrl(String videoId) async {
          final accessToken = await getAccessToken();
          if (accessToken == null) {
            return null;
          }

          final url =
              'https://graph.facebook.com/v20.0/$videoId?fields=thumbnails&access_token=$accessToken';

          final response = await http.get(Uri.parse(url));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final thumbnailsData = data['thumbnails']?['data'];

            if (thumbnailsData != null && thumbnailsData.isNotEmpty) {
              // Get the URI from the first thumbnail in the list
              final firstThumbnail = thumbnailsData[0];
              return firstThumbnail['uri'];
            }
          }

          return null;
        }

        final uri = Uri.parse(videoLinks);
        final videoId = uri.pathSegments.last;

        return FutureBuilder<String?>(
          future: getFacebookVideoThumbnailUrl(videoId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (!snapshot.hasData || snapshot.data == null) {
              return SizedBox.shrink(); // Skip invalid video links
            }

            final thumbnailUrl = snapshot.data!;

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PlayVideoPage(
                      id: id,
                      title: title,
                      details: details,
                      category: category,
                      link: videoLinks,
                    ),
                  ),
                );
              },
              child: Card(
                elevation: 8,
                margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15.0),
                ),
                shadowColor: Color.fromARGB(255, 91, 50, 35).withOpacity(0.9),
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(15.0),
                        ),
                      ),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: CachedNetworkImage(
                          imageUrl: thumbnailUrl,
                          placeholder: (context, url) =>
                              Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    ),
                    ListTile(
                      title: Padding(
                        padding: const EdgeInsets.only(top: 0.5),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      } else {
        return SizedBox.shrink(); // Skip non-video links
      }
    } else {
      return SizedBox.shrink();
    }
  }

  void updateData(String searchTerm) {
    _categories = _data
        .map((row) => row.length > 3 ? row[3].toString() : '')
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
      _initializeControllers(); // Initialize controllers after filtering data
    });
  }

  Future<void> fetchDataFromAPI(String searchTerm) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    bool hasInternet =
        ! (await Connectivity().checkConnectivity()).contains(ConnectivityResult.none);

    try {
      if (hasInternet) {
        final response = await http.get(
          Uri.parse(
            'https://sheets.googleapis.com/v4/spreadsheets/1mKtgmZ_Is4e6P3P5lvOwIplqx7VQ3amicgienGN9zwA/values/video!1:1000000?key=AIzaSyDFjIl-SEHUsgK0sjMm7x0awpf8tTEPQjs',
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
          prefs.setString('videoLocalData', json.encode(_data));

          // Update data with fetched values
          updateData(searchTerm); // Update data here
        } else {
          if (kDebugMode) {
            print('Failed to load data: ${response.statusCode}');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching data: $e');
      }
    }
  }

  Future<void> fetchDataOffline(String searchTerm) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? cachedData = prefs.getString('videoLocalData');

    bool hasInternet =
        ! (await Connectivity().checkConnectivity()).contains(ConnectivityResult.none);

    if (!hasInternet || title == '' || title.isEmpty) {
      if (cachedData != null && cachedData.isNotEmpty) {
        final List<dynamic> cachedValues = json.decode(cachedData);
        _data = cachedValues.cast<List<dynamic>>();
        setState(() {
          _data = cachedValues.cast<List<dynamic>>();
        });
        // Update data with cached values
        updateData(searchTerm); // Update data here
      }
    }

    try {
      if (!hasInternet) {
        // Check local storage for cached data

        if (cachedData != null && cachedData.isNotEmpty) {
          final List<dynamic> cachedValues = json.decode(cachedData);
          setState(() {
            _data = _data = cachedValues
                .cast<List<dynamic>>()
                .reversed
                .toList(); // Reverse the list
          });
          return;
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
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth < 600 ? 3 : (screenWidth > 900 ? 5 : 4);
    double aspectRatio = screenWidth < 900 ? 0.8 : 1;
    double cardHeight = screenWidth < 900 ? 200.0 : 250.0;

    final isTabletOrDesktop = MediaQuery.of(context).size.width > 600;

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
        title: Text(
          'ວີດີໂອ Video',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: _data.isEmpty
                ? const SizedBox(
                    width: 20.0, // Custom width
                    height: 20.0, // Custom height
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ), // Change color here
                      strokeWidth: 2.0, // Optional: change the stroke width
                    ),
                  )
                : const Icon(Icons.update_outlined),
            onPressed: () async {
              await fetchDataFromAPI(_searchTerm);

              if (_data.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Data has been successfully updated'),
                    duration: Duration(seconds: 2),
                    backgroundColor:
                        Colors.green, // Set the background color to green
                  ),
                );
              }
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
                    style: const TextStyle(fontSize: 17.0, letterSpacing: 0.5),
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
                                  updateData(
                                    _searchTerm,
                                  ); // Update data directly
                                  // Clear all controllers
                                  for (var controllers in _controllers.values) {
                                    for (var controller in controllers) {
                                      controller.close();
                                    }
                                  }
                                });

                                // Clear search term and update data

                                // Clear all controllers
                                for (var controllers in _controllers.values) {
                                  for (var controller in controllers) {
                                    controller.close();
                                  }
                                }
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
                            itemCount: _categories.length,
                            itemBuilder: (context, index) {
                              final category = _categories[index];
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
                        : isTabletOrDesktop
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              // Adjust crossAxisCount based on the orientation
                              if (constraints.maxWidth > 375) {
                                crossAxisCount = 3;
                              } else {
                                crossAxisCount = 4;
                              }

                              return GridView.builder(
                                padding: EdgeInsets.all(16.0),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      crossAxisSpacing: 16.0,
                                      mainAxisSpacing: 16.0,
                                      childAspectRatio:
                                          16 / constraints.maxWidth >= 667
                                          ? 0.8
                                          : constraints.maxWidth >= 1024
                                          ? 1.3
                                          : 1.2,
                                    ),
                                itemCount: _filteredData.length,
                                itemBuilder: (context, index) =>
                                    _buildVideoCard(context, index),
                              );
                            },
                          )
                        : ListView.builder(
                            padding: EdgeInsets.all(16.0),
                            itemCount: _filteredData.length,
                            itemBuilder: (context, index) =>
                                _buildVideoCard(context, index),
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
