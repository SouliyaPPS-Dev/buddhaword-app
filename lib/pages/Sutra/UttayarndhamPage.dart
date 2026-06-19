// ignore_for_file: file_names, library_private_types_in_public_api, prefer_const_constructors, deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../themes/ThemeProvider.dart';
import '../../layouts/NavigationDrawer.dart' as custom_nav;
import 'UttayarndhamContentPage.dart';

class UttayarndhamItem {
  final String title;
  final String url;

  UttayarndhamItem({required this.title, required this.url});
}

class _Tag {
  final String name;
  final String url;
  const _Tag(this.name, this.url);
}

class UttayarndhamPage extends StatefulWidget {
  const UttayarndhamPage({super.key});

  @override
  _UttayarndhamPageState createState() => _UttayarndhamPageState();
}

class _UttayarndhamPageState extends State<UttayarndhamPage> {
  static const String _baseUrl = 'https://uttayarndham.org';

  List<_Tag> _allTags = [];
  List<_Tag> _filteredTags = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _currentPage = 0;
  int _requestId = 0;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  bool _isContentSearching = false;
  final Set<String> _contentMatchedTagUrls = {};

  bool _isOffline = false;
  StreamSubscription? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchPage(0);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) setState(() => _isOffline = results.contains(ConnectivityResult.none));
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _connectivitySubscription?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() {
    final nextPage = _currentPage + 1;
    return _fetchPage(nextPage);
  }

  Future<void> _fetchPage(int page) async {
    final rid = ++_requestId;
    final isInitial = page == 0;
    setState(() {
      if (isInitial) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
      _error = null;
    });
    try {
      final url = '$_baseUrl/keyword/tags${page > 0 ? '?page=$page' : ''}';
      final response = await http.get(Uri.parse(url));
      if (rid != _requestId) return;
      if (response.statusCode == 200) {
        final tags = _parseTags(response.body);
        if (mounted) {
          setState(() {
            if (isInitial) {
              _allTags = tags;
            } else {
              final existingUrls = _allTags.map((e) => e.url).toSet();
              _allTags.addAll(tags.where((e) => !existingUrls.contains(e.url)));
            }
            _hasMore = _hasNextPage(response.body);
            _applySearch();
            _currentPage = page;
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load (${response.statusCode})';
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!_isOffline) _error = 'ການໂຫຼດຂໍ້ມູນລົ້ມເຫຼວ (ກະລຸນາກວດສອບການເຊື່ອມຕໍ່)';
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  bool _hasNextPage(String html) {
    return RegExp(r'rel="next"').hasMatch(html);
  }

  List<_Tag> _parseTags(String html) {
    final results = <_Tag>[];
    final seen = <String>{};
    final regex = RegExp(
      r'<a\s+href="(/taxonomy/term/\d+)"[^>]*>\s*([^<]+?)\s*</a>',
      dotAll: true,
    );
    for (final m in regex.allMatches(html)) {
      final name = m.group(2)!.trim();
      final url = m.group(1)!.trim();
      if (name.isNotEmpty && seen.add(url)) {
        results.add(_Tag(name, url));
      }
    }
    return results;
  }

  void _applySearch() {
    if (_searchQuery.isEmpty) {
      _filteredTags = List.from(_allTags);
    } else {
      final lower = _searchQuery.toLowerCase();
      _filteredTags = _allTags.where((tag) {
        if (tag.name.toLowerCase().contains(lower)) return true;
        if (_contentMatchedTagUrls.contains(tag.url)) return true;
        return false;
      }).toList();
    }
  }

  void _onSearch(String query) {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = query;
      _applySearch();
      _isContentSearching = false;
    });
    if (query.length >= 2) {
      _searchDebounce = Timer(const Duration(milliseconds: 500), () {
        _searchContent(query);
      });
    }
  }

  Future<void> _searchContent(String query) async {
    if (query.length < 2) return;
    final q = query.toLowerCase();
    final candidates = _allTags.where((tag) {
      if (tag.name.toLowerCase().contains(q)) return false;
      if (_contentMatchedTagUrls.contains(tag.url)) return false;
      return true;
    }).take(8).toList();

    if (candidates.isEmpty) return;

    setState(() => _isContentSearching = true);

    final matched = <String>{};
    for (final tag in candidates) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl${tag.url}'),
          headers: {'User-Agent': 'Mozilla/5.0'},
        );
        if (response.statusCode != 200) continue;
        final items = _parseTagPageItems(response.body);
        for (final item in items) {
          if (item.title.toLowerCase().contains(q)) {
            matched.add(tag.url);
            break;
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _contentMatchedTagUrls.addAll(matched);
        _applySearch();
        _isContentSearching = false;
      });
    }
  }

  void _onTagSelected(_Tag tag) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl${tag.url}'));
      if (response.statusCode == 200) {
        final items = _parseTagPageItems(response.body);
        if (items.isNotEmpty && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UttayarndhamContentPage(
                title: tag.name,
                contentUrl: items.first.url.startsWith('http')
                    ? items.first.url
                    : '$_baseUrl${items.first.url}',
                items: items,
                itemIndex: 0,
                tagListing: true,
              ),
            ),
          );
          return;
        }
      }
    } catch (_) {}
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UttayarndhamContentPage(
            title: tag.name,
            contentUrl: '$_baseUrl${tag.url}',
            items: null,
            itemIndex: 0,
          ),
        ),
      );
    }
  }

  List<UttayarndhamItem> _parseTagPageItems(String html) {
    final results = <UttayarndhamItem>[];
    final seenUrls = <String>{};
    final regex = RegExp(
      r'<h4[^>]*>.*?<a\s+href="\s*([^"]+)"[^>]*>\s*([^<]+?)\s*</a>',
      dotAll: true,
    );
    for (final m in regex.allMatches(html)) {
      final href = m.group(1)!.trim();
      final title = m.group(2)!.trim();
      final normalized = href.startsWith('http') ? Uri.parse(href).path : href;
      if (title.isNotEmpty && seenUrls.add(normalized)) {
        results.add(UttayarndhamItem(title: title, url: normalized));
      }
    }
    return results;
  }

  List<TextSpan> _highlightText(String text, String query) {
    if (query.isEmpty) return [TextSpan(text: text)];
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final qLower = query.toLowerCase();
    int start = 0;
    int idx = lower.indexOf(qLower, start);
    while (idx != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.orange.shade800,
          backgroundColor: Colors.yellow.withValues(alpha: 0.3),
        ),
      ));
      start = idx + query.length;
      idx = lower.indexOf(qLower, start);
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown,
        title: Text(
          'Tags',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return IconButton(
                icon: Text(
                  themeProvider.isDarkMode ? "☀️" : "🌙",
                  style: const TextStyle(fontSize: 16),
                ),
                onPressed: () =>
                    themeProvider.toggleTheme(!themeProvider.isDarkMode),
              );
            },
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu_open, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ],
      ),
      drawer: const custom_nav.NavigationDrawer(),
      body: Column(
        children: [
          _buildOfflineBanner(),
          _buildSearchBar(),
          if (_isContentSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Searching in content...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    if (!_isOffline) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.shade800,
      child: const Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'No internet connection',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearch,
        style: TextStyle(color: isDark ? Colors.grey[100] : Colors.grey[900]),
        decoration: InputDecoration(
          hintText: 'Search tags...',
          hintStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
          prefixIcon: Icon(Icons.tag, color: isDark ? Colors.brown[200] : Colors.brown),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: isDark ? Colors.brown[200] : Colors.brown),
                  onPressed: () {
                    _searchController.clear();
                    _onSearch('');
                  },
                )
              : null,
          filled: true,
          fillColor: isDark ? Colors.grey[700] : Colors.brown.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: Colors.red)),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _fetchPage(_currentPage),
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_filteredTags.isEmpty && !_isLoadingMore) {
      return Center(
        child: Text(_allTags.isEmpty ? 'No tags loaded' : 'No matching tags'),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      itemCount: _filteredTags.length + (_isLoadingMore ? 1 : 0),
      separatorBuilder: (context, index) => Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == _filteredTags.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.brown,
                ),
              ),
            ),
          );
        }
        final tag = _filteredTags[index];
        return ListTile(
          leading: Icon(Icons.label, color: Colors.brown, size: 22),
          title: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: isDark ? Colors.grey[100] : Colors.grey[900],
              ),
              children: [
                TextSpan(text: '${index + 1}. '),
                ..._highlightText(tag.name, _searchQuery),
              ],
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: Colors.brown),
          onTap: () => _onTagSelected(tag),
        );
      },
    );
  }
}
