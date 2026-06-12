// ignore_for_file: file_names, library_private_types_in_public_api, prefer_const_constructors, deprecated_member_use
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../themes/ThemeProvider.dart';
import 'AnakameSutraContentPage.dart';

class AnakameSutraItem {
  final String number;
  final String title;
  final String url;

  AnakameSutraItem({
    required this.number,
    required this.title,
    required this.url,
  });
}

class AnakameSutraPage extends StatefulWidget {
  const AnakameSutraPage({super.key});

  @override
  _AnakameSutraPageState createState() => _AnakameSutraPageState();
}

class _AnakameSutraPageState extends State<AnakameSutraPage> {
  static const String _baseUrl = 'http://anakame.com/page/1_Sutas/main';
  static const String _listingUrl = '$_baseUrl/1_Sutta_number.htm';

  List<AnakameSutraItem> _items = [];
  List<AnakameSutraItem> _filteredItems = [];
  bool _isLoading = true;
  String? _error;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchListing();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchListing() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http.get(Uri.parse(_listingUrl));
      if (response.statusCode == 200) {
        String decoded = utf8.decode(response.bodyBytes);
        if (decoded.startsWith('\uFEFF')) decoded = decoded.substring(1);
        final items = _parseListing(decoded);
        if (mounted) {
          setState(() {
            _items = items;
            _filteredItems = items;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load (${response.statusCode})';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<AnakameSutraItem> _parseListing(String html) {
    final results = <AnakameSutraItem>[];
    final trRegex = RegExp(r'<tr>.*?</tr>', dotAll: true);
    for (final tr in trRegex.allMatches(html)) {
      final trHtml = tr.group(0)!;
      if (!trHtml.contains('href')) continue;
      final tdRegex = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);
      final tds = tdRegex.allMatches(trHtml).map((m) => m.group(1)!).toList();
      if (tds.length < 2) continue;
      final numText = tds[0].replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (numText.isEmpty) continue;
      final linkRegex = RegExp(r'<a\s+href="([^"]+)"[^>]*>([^<]+)</a>', dotAll: true);
      final linkMatch = linkRegex.firstMatch(tds[1]);
      if (linkMatch == null) continue;
      final href = linkMatch.group(1)!.trim();
      final title = linkMatch.group(2)!
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isNotEmpty) {
        results.add(AnakameSutraItem(number: numText, title: title, url: href));
      }
    }
    return results;
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredItems = _items;
      } else {
        _filteredItems = _items.where((item) =>
          item.title.toLowerCase().contains(query.toLowerCase())
        ).toList();
      }
    });
  }

  String _resolveUrl(String href) {
    if (href.startsWith('http')) return href;
    final uri = Uri.parse(_listingUrl);
    return uri.resolve(href).toString();
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
        ],
      ),
      body: _buildBody(),
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
              onPressed: _fetchListing,
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
        if (_filteredItems.isEmpty)
          Expanded(
            child: Center(child: Text('No items found')),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: _filteredItems.length,
              separatorBuilder: (context, index) => Divider(height: 1),
              itemBuilder: (context, index) {
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
                        TextSpan(text: '${item.number}. '),
                        ..._highlightText(item.title, _searchQuery),
                      ],
                    ),
                  ),
                  trailing: Icon(Icons.chevron_right, color: Colors.brown),
                  onTap: () {
                    final idx = _filteredItems.indexOf(item);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AnakameSutraContentPage(
                          title: item.title,
                          contentUrl: _resolveUrl(item.url),
                          items: _filteredItems,
                          itemIndex: idx >= 0 ? idx : 0,
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
