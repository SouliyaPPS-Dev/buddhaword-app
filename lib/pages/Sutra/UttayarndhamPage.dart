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

class UttayarndhamPage extends StatefulWidget {
  const UttayarndhamPage({super.key});

  @override
  _UttayarndhamPageState createState() => _UttayarndhamPageState();
}

class _UttayarndhamPageState extends State<UttayarndhamPage> {
  static const String _baseUrl = 'https://uttayarndham.org';
  static const int _pageSize = 20;

  List<UttayarndhamItem> _allItems = [];
  List<UttayarndhamItem> _filteredItems = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _currentPage = 0;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

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
    _connectivitySubscription?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore &&
        _searchQuery.isEmpty) {
      _loadMore();
    }
  }

  Future<void> _loadMore() {
    final nextPage = _currentPage + 1;
    return _fetchPage(nextPage);
  }

  Future<void> _fetchPage(int page) async {
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
      final url = page == 0
          ? '$_baseUrl/dhamma-sharing'
          : '$_baseUrl/dhamma-sharing?page=$page';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final items = _parseListing(response.body);
        if (mounted) {
          setState(() {
            if (isInitial) {
              _allItems = items;
            } else {
              final existingUrls = _allItems.map((e) => e.url).toSet();
              _allItems.addAll(items.where((e) => !existingUrls.contains(e.url)));
            }
            if (items.length < _pageSize) {
              _hasMore = false;
            }
            _filteredItems = _searchQuery.isEmpty
                ? List.from(_allItems)
                : _allItems
                    .where((item) =>
                        item.title.toLowerCase().contains(_searchQuery.toLowerCase()))
                    .toList();
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

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredItems = List.from(_allItems);
      } else {
        final lower = query.toLowerCase();
        _filteredItems = _allItems
            .where((item) => item.title.toLowerCase().contains(lower))
            .toList();
      }
    });
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

  List<UttayarndhamItem> _parseListing(String html) {
    final results = <UttayarndhamItem>[];
    final itemRegex = RegExp(
      r'<h4><a\s+href="\s*(/[^"]+)"[^>]*>\s*([^<]+?)\s*</a></h4>',
      dotAll: true,
    );
    for (final m in itemRegex.allMatches(html)) {
      final href = m.group(1)!.trim();
      final title = m.group(2)!.trim();
      if (title.isNotEmpty) {
        results.add(UttayarndhamItem(title: title, url: href));
      }
    }
    if (results.isEmpty) {
      final fallbackRegex = RegExp(
        r'<a\s+href="([^"]+)"[^>]*>\s*([^<]+?)\s*</a>',
        dotAll: true,
      );
      for (final m in fallbackRegex.allMatches(html)) {
        final href = m.group(1)!.trim();
        final title = m.group(2)!.trim();
        if (href.contains('dhamma-sharing') && title.isNotEmpty) {
          final normalized = href.startsWith('http')
              ? Uri.parse(href).path
              : href;
          results.add(UttayarndhamItem(title: title, url: normalized));
        }
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown,
        title: Text(
          'Uttayarndham (ธรรมะ)',
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) => true,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearch,
              style: TextStyle(color: isDark ? Colors.grey[100] : Colors.grey[900]),
            decoration: InputDecoration(
              hintText: 'Search...',
              hintStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
              prefixIcon: Icon(Icons.search, color: isDark ? Colors.brown[200] : Colors.brown),
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
          ),
        ),
        if (_filteredItems.isEmpty && !_isLoadingMore)
          Expanded(child: Center(child: Text('No items found')))
        else
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              itemCount: _filteredItems.length + (_isLoadingMore ? 1 : 0),
              separatorBuilder: (context, index) => Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == _filteredItems.length) {
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
                final item = _filteredItems[index];
                return ListTile(
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
                        ..._highlightText(item.title, _searchQuery),
                      ],
                    ),
                  ),
                  trailing: Icon(Icons.chevron_right, color: Colors.brown),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UttayarndhamContentPage(
                          title: item.title,
                          contentUrl: item.url.startsWith('http') ? item.url : '$_baseUrl${item.url}',
                          items: _filteredItems,
                          itemIndex: index,
                          searchQuery: _searchQuery,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
