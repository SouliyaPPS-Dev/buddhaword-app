// ignore_for_file: file_names, library_private_types_in_public_api, prefer_const_constructors, deprecated_member_use
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../themes/ThemeProvider.dart';
import '../../layouts/NavigationDrawer.dart' as custom_nav;
import 'AnakameSutraContentPage.dart';

class AnakameSutraItem {
  final String title;
  final String url;
  AnakameSutraItem({required this.title, required this.url});
}

class _Category {
  final String name;
  final String url;
  final IconData icon;
  final String subtitle;
  const _Category(this.name, this.url, this.icon, this.subtitle);
}

const List<_Category> _categories = [
  _Category(
    'Sutta',
    'http://anakame.com/page/1_Sutas/main/1_Sutta.htm',
    Icons.menu_book,
    '1. Suttas collection',
  ),
  _Category(
    'Sutta Set',
    'http://anakame.com/page/4_Suta_Set/Main/Main_Set01.htm',
    Icons.library_books,
    '4. Sutta Sets',
  ),
  _Category(
    'Short Sutta',
    'http://anakame.com/page/4_Short_Sutta.htm',
    Icons.auto_stories,
    '4. Short Suttas',
  ),
  _Category(
    'Person',
    'http://anakame.com/page/7_person.htm',
    Icons.person,
    '7. Persons',
  ),
  _Category(
    'Misc',
    'http://anakame.com/page/8_Misc.htm',
    Icons.category,
    '8. Miscellaneous',
  ),
];

class _CategorizedItem {
  final String title;
  final String url;
  final String categoryName;
  final int categoryIndex;
  _CategorizedItem({
    required this.title,
    required this.url,
    required this.categoryName,
    required this.categoryIndex,
  });
}

class AnakameSutraPage extends StatefulWidget {
  const AnakameSutraPage({super.key});

  @override
  _AnakameSutraPageState createState() => _AnakameSutraPageState();
}

class _AnakameSutraPageState extends State<AnakameSutraPage> {
  final List<_CategorizedItem> _allItems = [];
  List<_CategorizedItem> _filteredItems = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _loadedCategoryIndex = -1;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  bool _isContentSearching = false;
  final Set<String> _contentMatchedUrls = {};
  final Map<String, String> _contentCache = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadNextCategory();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoadingMore &&
        _loadedCategoryIndex < _categories.length - 1) {
      _loadNextCategory();
    }
  }

  Future<void> _loadNextCategory() async {
    if (_isLoadingMore) return;
    final nextIndex = _loadedCategoryIndex + 1;
    if (nextIndex >= _categories.length) return;

    setState(() {
      if (_loadedCategoryIndex < 0) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
      _error = null;
    });

    final items = await _fetchCategory(_categories[nextIndex], nextIndex);

    if (mounted) {
      setState(() {
        _allItems.addAll(items);
        _applySearch();
        _loadedCategoryIndex = nextIndex;
        _isLoading = false;
        _isLoadingMore = false;
        if (_allItems.isEmpty && _loadedCategoryIndex >= _categories.length - 1) {
          _error = 'No items found';
        }
      });
    }
  }

  void _applySearch() {
    if (_searchQuery.isEmpty) {
      _filteredItems = List.from(_allItems);
    } else {
      final lower = _searchQuery.toLowerCase();
      final seen = <String>{};
      _filteredItems = _allItems.where((item) {
        final match = item.title.toLowerCase().contains(lower) ||
            _contentMatchedUrls.contains(item.url);
        return match && seen.add(item.url);
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
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (query.length >= 2) {
      _searchDebounce = Timer(const Duration(milliseconds: 500), () {
        _searchContent(query);
      });
    }
  }

  static const String _apiBase = 'https://buddhaword-web.hf.space';

  Future<void> _searchContent(String query) async {
    if (query.length < 2 || _allItems.isEmpty) return;
    final q = query.toLowerCase();
    final candidates = _allItems.where((item) {
      if (item.title.toLowerCase().contains(q)) return false;
      if (_contentMatchedUrls.contains(item.url)) return false;
      if (_contentCache.containsKey(item.url)) return false;
      return true;
    }).take(10).toList();

    if (candidates.isEmpty) return;

    setState(() => _isContentSearching = true);

    final matched = <String>{};
    for (final item in candidates) {
      try {
        final uri = Uri.parse('$_apiBase/api/anakame/content')
            .replace(queryParameters: {'url': item.url});
        final response = await http.get(uri);
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final text = (data['content'] as String?) ?? '';
          _contentCache[item.url] = text;
          if (text.toLowerCase().contains(q)) {
            matched.add(item.url);
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _contentMatchedUrls.addAll(matched);
        _applySearch();
        _isContentSearching = false;
      });
    }
  }

  Future<List<_CategorizedItem>> _fetchCategory(_Category cat, int index) async {
    try {
      final response = await http.get(Uri.parse(cat.url));
      if (response.statusCode != 200) return [];

      String decoded = utf8.decode(response.bodyBytes);
      if (decoded.startsWith('\uFEFF')) decoded = decoded.substring(1);

      final items = _parseCategoryItems(decoded, cat.url);
      return items
          .map((item) => _CategorizedItem(
                title: item.title,
                url: item.url,
                categoryName: cat.name,
                categoryIndex: index,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<AnakameSutraItem> _parseCategoryItems(String html, String baseUrl) {
    final seen = <String>{};
    final items = <AnakameSutraItem>[];

    for (final m in RegExp(
      r'<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
    ).allMatches(html)) {
      final href = m.group(1)!.trim();
      final inner = m.group(2)!.trim();

      if (inner.contains('<img') || inner.isEmpty) continue;
      if (href.startsWith('#') || href.startsWith('javascript')) continue;
      if (href.contains('index.htm') || href.contains('favicon')) continue;
      if (!href.contains('.htm') && !href.contains('.html')) continue;

      final title = inner
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isEmpty || title.length < 3) continue;

      final absUrl = _resolveUrl(href, baseUrl);
      if (seen.contains(absUrl)) continue;
      seen.add(absUrl);

      items.add(AnakameSutraItem(title: title, url: absUrl));
    }
    return items;
  }

  String _resolveUrl(String href, String baseUrl) {
    if (href.startsWith('http')) return href;
    final base = Uri.parse(baseUrl);
    return base.resolve(href).toString();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown,
        title: Text(
          'Anakame (ภาษาไทย)',
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _allItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: Colors.red)),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchAllCategoriesFallback,
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
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
        Expanded(child: _buildItemList()),
      ],
    );
  }

  Future<void> _fetchAllCategoriesFallback() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _loadedCategoryIndex = -1;
      _allItems.clear();
    });
    await _loadNextCategory();
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
          hintText: 'Search all collections...',
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
    );
  }

  Widget _buildItemList() {
    if (_filteredItems.isEmpty) {
      return Center(child: Text('No items found'));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sections = <_Section>[];
    int lastCategoryIndex = -1;
    List<_CategorizedItem> currentItems = [];

    for (final item in _filteredItems) {
      if (item.categoryIndex != lastCategoryIndex) {
        if (currentItems.isNotEmpty) {
          sections.add(_Section(
            name: _categories[lastCategoryIndex].name,
            icon: _categories[lastCategoryIndex].icon,
            items: List.from(currentItems),
          ));
        }
        lastCategoryIndex = item.categoryIndex;
        currentItems = [item];
      } else {
        currentItems.add(item);
      }
    }
    if (currentItems.isNotEmpty && lastCategoryIndex >= 0) {
      sections.add(_Section(
        name: _categories[lastCategoryIndex].name,
        icon: _categories[lastCategoryIndex].icon,
        items: List.from(currentItems),
      ));
    }

    final hasMore = _loadedCategoryIndex < _categories.length - 1;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sections.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= sections.length) {
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

        final section = sections[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Icon(section.icon, size: 20, color: Colors.brown),
                  SizedBox(width: 8),
                  Text(
                    section.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown,
                    ),
                  ),
                ],
              ),
            ),
            ...section.items.map((item) => ListTile(
                  title: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.grey[100] : Colors.grey[900],
                      ),
                      children: _highlightText(item.title, _searchQuery),
                    ),
                  ),
                  trailing: Icon(Icons.chevron_right, color: Colors.brown, size: 20),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AnakameSutraContentPage(
                          title: item.title,
                          contentUrl: item.url,
                          tagListing: false,
                        ),
                      ),
                    );
                  },
                )),
          ],
        );
      },
    );
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
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + query.length),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.orange.shade800,
            backgroundColor: Colors.yellow.withValues(alpha: 0.3),
          ),
        ),
      );
      start = idx + query.length;
      idx = lower.indexOf(qLower, start);
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return spans;
  }
}

class _Section {
  final String name;
  final IconData icon;
  final List<_CategorizedItem> items;
  _Section({
    required this.name,
    required this.icon,
    required this.items,
  });
}
