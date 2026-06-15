// ignore_for_file: prefer_const_constructors, must_be_immutable, file_names, library_private_types_in_public_api, prefer_const_constructors_in_immutables, prefer_const_declarations, depend_on_referenced_packages, deprecated_member_use

import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'PlayVideoPage.dart';
import 'VideoPage.dart';

class CategoryListPage extends StatefulWidget {
  final List<List<dynamic>> data;
  final String selectedCategory;
  final String searchTerm;

  CategoryListPage({
    super.key,
    required this.data,
    required this.selectedCategory,
    required this.searchTerm,
  });

  @override
  _CategoryListPageState createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> {
  late List<List<dynamic>> _filteredData;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, YoutubePlayerController> _controllers = {};

  static String? _accessToken;

  @override
  void initState() {
    super.initState();
    _filteredData = _filterData(widget.searchTerm).reversed.toList();
    _searchController.text = widget.searchTerm;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controllers.forEach((key, controller) => controller.close());
    super.dispose();
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

  List<List<dynamic>> _filterData(String searchTerm) {
    return widget.data
        .where(
          (row) =>
              row.length > 3 &&
              row[3] == widget.selectedCategory &&
              row.any(
                (cell) => cell.toString().toLowerCase().contains(
                  searchTerm.toLowerCase(),
                ),
              ),
        )
        .toList();
  }

  Widget _buildVideoCard(BuildContext context, int index) {
    if (_filteredData.isEmpty ||
        index >= _filteredData.length ||
        _filteredData[index].length < 5) {
      return SizedBox.shrink();
    }

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
      final videoId = YoutubePlayerController.convertUrlToId(videoLinks.trim());

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
              // Display the thumbnail image using an HTML img tag
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(15.0),
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(15.0),
                    ),
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
  }

  @override
  Widget build(BuildContext context) {
    final isTabletOrDesktop = MediaQuery.of(context).size.width > 600;

    double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth < 600 ? 3 : (screenWidth > 900 ? 5 : 4);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown,
        title: Text(
          widget.selectedCategory,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => VideoPage(title: '')),
            );
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
                hintText: 'ຄົ້ນຫາ...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _filteredData = _filterData('');
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  _filteredData = _filterData(value);
                });
              },
            ),
          ),
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
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16.0,
                          mainAxisSpacing: 16.0,
                          childAspectRatio: constraints.maxWidth <= 667
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
    );
  }
}
