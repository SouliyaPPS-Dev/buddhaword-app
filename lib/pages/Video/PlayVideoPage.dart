// ignore_for_file: prefer_const_constructors, library_private_types_in_public_api, must_be_immutable, file_names, unrelated_type_equality_checks, avoid_web_libraries_in_flutter, unnecessary_null_comparison, use_build_context_synchronously, sized_box_for_whitespace, unused_local_variable, prefer_const_constructors_in_immutables, depend_on_referenced_packages, prefer_const_declarations, deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'RandomImagePage.dart';
import 'VideoPage.dart';

class PlayVideoPage extends StatefulWidget {
  final String? id;
  final String? title;
  final String? details;
  final String? category;
  final String? link;

  PlayVideoPage({
    super.key,
    this.id,
    this.title,
    this.details,
    this.category,
    this.link,
  });

  @override
  _PlayVideoPageState createState() => _PlayVideoPageState();
}

class _PlayVideoPageState extends State<PlayVideoPage> {
  List<List<dynamic>> _data = [];

  String? _videoLink;
  String _videoTitle = '';
  String _videoID = '';

  InAppWebViewController? _webviewController;

  bool hasInternet = false;

  static String? _accessToken;

  @override
  void initState() {
    super.initState();

    _videoID = widget.id ?? ''; // Initialize ID
    _videoTitle = widget.title ?? ''; // Initialize title
    _videoLink = widget.link; // Initialize video link

    _checkConnectivity();
    _initialize();

    _loadVideoInInAppWebView(_videoLink ?? '', 0);
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

  @override
  void didUpdateWidget(covariant PlayVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.id != oldWidget.id || widget.link != oldWidget.link) {
      _videoTitle = widget.title ?? ''; // Update title when widget updates
      _initializeVideoLink(widget.link);
    }
  }

  Future<void> _initialize() async {
    await _checkConnectivity();
    _checkRouteAndFetchData();
    _initializeVideoLink(widget.link);
  }

  Future<void> _initializeVideoLink(String? videoLink) async {
    if (videoLink != null && videoLink.isNotEmpty) {
      setState(() {
        _videoLink = videoLink;
        _loadVideoInInAppWebView(
          videoLink,
          MediaQuery.of(context).size.width > 600 ? 130 : 500,
        );
      });
    }
  }

  String _loadVideoInInAppWebView(String videoLink, double height) {
    if (_webviewController == null) {
      // The InAppWebViewController is not initialized
      return '';
    }

    String url = '';
    if (videoLink.contains('youtube.com') || videoLink.contains('youtu.be')) {
      final videoYoutubeLink = convertYoutubeLink(videoLink);
      final videoId = YoutubePlayerController.convertUrlToId(videoYoutubeLink);
      if (videoId != null) {
        url = 'https://www.youtube.com/embed/$videoId?autoplay=1&playsinline=1';
      }
    } else if (videoLink.contains('facebook.com')) {
      url = getFacebookEmbedUrl(videoLink, height);
    }

    // Avoid reloading the same URL
    if (url.isNotEmpty && _webviewController != null) {
      _webviewController?.getUrl().then((currentUrl) {
        if (currentUrl != url) {
          _webviewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
        }
      });
    }
    if (kDebugMode) {
      print('Loading video: $url');
    }

    return url;
  }

  String getFacebookEmbedUrl(String videoLink, double height) {
    // Parse the video URL
    final uri = Uri.parse(videoLink);
    final videoId = uri.pathSegments.last; // Extract video ID

    // Build the Facebook embed URL
    return 'https://www.facebook.com/plugins/video.php?height=${height.toInt()}&href=${Uri.encodeComponent(videoLink)}';
  }

  String convertYoutubeLink(String shortLink) {
    // Extract the video ID and parameters
    final uri = Uri.parse(shortLink);
    final videoId = uri.pathSegments[0];
    final params = uri.query;

    // Construct the embed link
    return 'https://www.youtube.com/embed/$videoId?$params';
  }

  Future<void> _checkConnectivity() async {
    var result = await Connectivity().checkConnectivity();
    setState(() {
      hasInternet = !result.contains(ConnectivityResult.none);
    });
  }

  Future<void> _checkRouteAndFetchData() async {
    if (hasInternet) {
      await fetchDataFromAPI();
    } else {
      await _loadDataFromSharedPreferences();
    }
  }

  Future<void> _loadDataFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('videoLocalData');
      if (cachedData != null && cachedData.isNotEmpty) {
        setState(() {
          _data = json
              .decode(cachedData)
              .cast<List<dynamic>>()
              .reversed
              .toList();
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading data from SharedPreferences: $e');
      }
    }
  }

  Future<dynamic> getFromSharedPreferences(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting from SharedPreferences: $e');
      }
    }
    return null;
  }

  Future<void> saveToSharedPreferences(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value.toString());
    } catch (e) {
      if (kDebugMode) {
        print('Error saving to SharedPreferences: $e');
      }
    }
  }

  Future<void> fetchDataFromAPI() async {
    try {
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

        setState(() {
          _data = values.reversed.toList();
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('videoLocalData', json.encode(_data));
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

  Widget _buildVideoCard(BuildContext context, int index) {
    if (_data.isEmpty || index >= _data.length || _data[index].length < 5) {
      return SizedBox.shrink(); // Prevents RangeError by returning an empty widget
    }

    if (_data.isNotEmpty && index < _data.length) {
      final id = _data[index][0].toString();
      final title = _data[index][1].toString();
      final details = _data[index][2].toString();
      final category = _data[index][3].toString();
      final videoLinks = _data[index][4].toString();

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

        final thumbnailUrl =
            'https://corsproxy.io/?https://img.youtube.com/vi/$videoId/hqdefault.jpg';

        return GestureDetector(
          onTap: () {
            setState(() {
              _videoTitle = title; // Update the title
              _videoLink = videoLinks; // Update the video link
              _videoID = id; // Update the widget ID
              _initializeVideoLink(videoLinks); // Load the video
            });
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
      } else if (isFacebook) {
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
                setState(() {
                  _videoTitle = title; // Update the title
                  _videoLink = videoLinks; // Update the video link
                  _videoID = id; // Update the widget ID
                  _initializeVideoLink(videoLinks); // Load the video
                });
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

  void _shareVideoLink() {
    final url = 'https://buddhaword.free.nf/video/view/$_videoID';

    final shareText = '$_videoTitle\n $url';

    if (_videoLink != null) {
      Share.share(shareText, subject: _videoTitle);
    } else {
      if (kDebugMode) {
        print('Video link is null, cannot share.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Safeguard: Ensure videoModel has enough elements before accessing
    final videoModel = _data.firstWhere(
      (row) => row.isNotEmpty && row[0] == widget.id,
      orElse: () => [],
    );

    double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth < 600 ? 3 : (screenWidth > 900 ? 5 : 4);
    double aspectRatio = screenWidth < 900 ? 0.8 : 1;
    double cardHeight = screenWidth < 900 ? 200.0 : 250.0;

    return _videoLink == null
        ? RandomImagePage()
        : Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.brown,
              title: Text(
                _videoTitle, // Use the updated title
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => VideoPage(title: ''),
                    ),
                  );
                },
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.white),
                  onPressed: _shareVideoLink,
                ),
                const SizedBox(width: 10),
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
            body: LayoutBuilder(
              builder: (context, constraints) {
                // Define a base aspect ratio for the video player
                const double aspectRatio = 16 / 9;

                // Set different heights for mobile and tablet/desktop
                double videoPlayerHeight;
                double videoListHeight;

                if (constraints.maxWidth < 600) {
                  // Considered mobile
                  videoPlayerHeight = constraints.maxHeight * 0.6;
                  videoListHeight = constraints.maxHeight - videoPlayerHeight;
                } else {
                  // Considered tablet/desktop
                  videoPlayerHeight =
                      constraints.maxHeight *
                      0.6; // Custom height for desktop (50% of screen height)
                  videoListHeight = constraints.maxHeight - videoPlayerHeight;
                }

                final double videoWidth = constraints.maxWidth;

                final isTabletOrDesktop =
                    MediaQuery.of(context).size.width > 600;

                // Assume getFromLocalStorage is a function that returns the list of videos
                final videoLocalData = getFromSharedPreferences(
                  'videoLocalData',
                );

                // final String videoLinks = _loadVideoInInAppWebView(
                //     _videoLink ?? '', videoPlayerHeight);

                final String videoLinks = convertYoutubeLink(_videoLink ?? '');

                return Column(
                  children: [
                    // Video Player
                    Container(
                      width: double.infinity,
                      height: videoPlayerHeight,
                      child: InAppWebView(
                        initialUrlRequest: URLRequest(url: WebUri(videoLinks)),
                        initialOptions: InAppWebViewGroupOptions(
                          crossPlatform: InAppWebViewOptions(
                            javaScriptEnabled: true,
                            mediaPlaybackRequiresUserGesture: false,
                            supportZoom: true,
                          ),
                        ),
                        onWebViewCreated: (InAppWebViewController controller) {
                          _webviewController = controller;
                        },
                      ),
                    ),

                    // Divider between video player and video list
                    const Divider(height: 1, thickness: 1),
                    // Video List
                    Expanded(
                      child: isTabletOrDesktop
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
                                  itemCount: _data.length,
                                  itemBuilder: (context, index) =>
                                      _buildVideoCard(context, index),
                                );
                              },
                            )
                          : ListView.builder(
                              padding: EdgeInsets.all(5.0),
                              itemCount: _data.length,
                              itemBuilder: (context, index) =>
                                  _buildVideoCard(context, index),
                            ),
                    ),
                  ],
                );
              },
            ),
          );
  }
}
