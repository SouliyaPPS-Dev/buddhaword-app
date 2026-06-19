import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../themes/ThemeProvider.dart';
import 'etipitaka_content_page.dart';
import '../../layouts/NavigationDrawer.dart' as custom_nav;

class EtipitakaItem {
  final int volume;
  final int page;
  final String items;
  final String title;
  final String excerpt;

  EtipitakaItem({
    required this.volume,
    required this.page,
    required this.items,
    required this.title,
    required this.excerpt,
  });
}

class EtipitakaSearchPage extends StatefulWidget {
  const EtipitakaSearchPage({super.key});

  @override
  EtipitakaSearchPageState createState() => EtipitakaSearchPageState();
}

class EtipitakaSearchPageState extends State<EtipitakaSearchPage> {
  static const String _apiBase = 'https://buddhaword-web.hf.space';

  static const _allCodes = [
    _CategoryInfo('thai', 'ไทย (ฉบับหลวง)', Icons.menu_book),
    _CategoryInfo('pali', 'บาลี (สยามรัฐ)', Icons.menu_book),
    _CategoryInfo('thaimm', 'ไทย (มหามกุฏฯ)', Icons.language),
    _CategoryInfo('thaimc', 'ไทย (มหาจุฬาฯ)', Icons.language),
    _CategoryInfo('thaipb', 'พุทธวจน-หมวดธรรม', Icons.language),
    _CategoryInfo('thaibt', 'ชุดจากพระโอษฐ์ 5 เล่ม', Icons.language),
    _CategoryInfo('english', 'English', Icons.language),
    _CategoryInfo('burma', 'Burma', Icons.language),
    _CategoryInfo('myan', 'Myanmar', Icons.language),
    _CategoryInfo('sri', 'Sri Lanka', Icons.language),
    _CategoryInfo('siam', 'Siam', Icons.language),
    _CategoryInfo('chinese', 'Chinese', Icons.language),
    _CategoryInfo('tibetan', 'Tibetan', Icons.language),
    _CategoryInfo('korean', 'Korean', Icons.language),
    _CategoryInfo('vietnamese', 'Vietnamese', Icons.language),
    _CategoryInfo('japanese', 'Japanese', Icons.language),
    _CategoryInfo('roman', 'Roman', Icons.language),
  ];

  static const _excludedCodes = {
    'thaiwn', 'thaict', 'romanct', 'palimc', 'thaims', 'thaivn', 'palinew',
  };

  late final List<_CategoryInfo> _categories = _allCodes
      .where((c) => !_excludedCodes.contains(c.code))
      .toList();

  List<EtipitakaItem> _allResults = [];
  bool _isSearching = false;
  String? _error;
  String _selectedCode = 'thai';
  String _query = '';
  int _searchRunId = 0;

  Map<int, List<EtipitakaItem>> _groupedResults = {};

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _selectCategory(_CategoryInfo cat) {
    _searchController.clear();
    setState(() {
      _selectedCode = cat.code;
      _query = '';
      _allResults = [];
      _groupedResults = {};
      _error = null;
    });
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _allResults = [];
      _groupedResults = {};
      _query = '';
      _error = null;
      _searchRunId++;
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

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    final runId = ++_searchRunId;
    setState(() {
      _isSearching = true;
      _error = null;
      _query = query;
      _allResults = [];
      _groupedResults = {};
    });

    try {
      final uri = Uri.parse('$_apiBase/api/etipitaka/search')
          .replace(queryParameters: {
        'code': _selectedCode,
        'q': query,
      });
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        if (mounted && runId == _searchRunId) {
          setState(() {
            _error = 'Server error: ${response.statusCode}';
            _isSearching = false;
          });
        }
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final rawResults = json['results'] as List<dynamic>? ?? [];

      if (mounted && runId == _searchRunId) {
        final items = rawResults.map((r) {
          final map = r as Map<String, dynamic>;
          return EtipitakaItem(
            volume: map['volume'] as int,
            page: map['page'] as int,
            items: map['items'] as String? ?? '',
            title: map['title'] as String? ?? _buildTitle(map['volume'] as int, map['page'] as int),
            excerpt: map['excerpt'] as String? ?? '',
          );
        }).toList();

        final grouped = <int, List<EtipitakaItem>>{};
        for (final item in items) {
          grouped.putIfAbsent(item.volume, () => []).add(item);
        }
        setState(() {
          _allResults = items;
          _groupedResults = grouped;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted && runId == _searchRunId) {
        setState(() {
          _error = 'Error: $e';
          _isSearching = false;
        });
      }
    }
  }

  String _buildTitle(int volume, int page) {
    return 'ເຫຼັ້ມທີ່ $volume ຫນ້າ $page';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown,
        title: Text(
          'E-Tipitaka',
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
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_query.isNotEmpty) {
      return _buildResultsView(isDark);
    }
    return _buildCategoryGrid(isDark);
  }

  Widget _buildCategoryGrid(bool isDark) {
    final crossAxisCount = MediaQuery.of(context).size.width < 600 ? 2 : 3;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (_) => true,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 500),
                        () {
                          if (_searchController.text.trim().isNotEmpty) _search();
                        },
                      );
                    },
                    onSubmitted: (_) => _search(),
                  style: TextStyle(
                    color: isDark ? Colors.grey[100] : Colors.grey[900],
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search E-Tipitaka...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: isDark ? Colors.brown[200] : Colors.brown,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: isDark ? Colors.brown[200] : Colors.brown,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _allResults = [];
                                _query = '';
                                _error = null;
                              });
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
            const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedCode,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: isDark ? Colors.grey[700] : Colors.brown.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 0,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[100] : Colors.grey[900],
                  ),
                  items: _categories.map((e) {
                    return DropdownMenuItem(
                      value: e.code,
                      child: Text(e.label),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedCode = val);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.3,
            ),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final cat = _categories[index];
              return _CategoryCard(
                category: cat,
                isDark: isDark,
                isSelected: _selectedCode == cat.code,
                onTap: () => _selectCategory(cat),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultsView(bool isDark) {
    final sortedVolumes = _groupedResults.keys.toList()..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (_) => true,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 500),
                        () {
                          if (_searchController.text.trim().isNotEmpty) _search();
                        },
                      );
                    },
                    onSubmitted: (_) => _search(),
                    style: TextStyle(
                      color: isDark ? Colors.grey[100] : Colors.grey[900],
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search E-Tipitaka...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: isDark ? Colors.brown[200] : Colors.brown,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear,
                                color: isDark ? Colors.brown[200] : Colors.brown,
                              ),
                              onPressed: _clearSearch,
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
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  icon: const Icon(Icons.home, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.brown,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _clearSearch,
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: TextStyle(color: Colors.red)),
          ),
        if (_isSearching)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_allResults.isEmpty && !_isSearching)
          const Expanded(child: Center(child: Text('No results found')))
        else
          Expanded(
            child: ListView.builder(
              itemCount: sortedVolumes.length + _allResults.length,
              itemBuilder: (context, index) {
                int offset = 0;
                for (final vol in sortedVolumes) {
                  final entries = _groupedResults[vol]!;
                  if (index == offset) {
                    return _buildVolumeHeader(vol, entries.length, isDark);
                  }
                  offset++;
                  final itemIndex = index - offset;
                  if (itemIndex < entries.length) {
                    return _buildGroupedEntry(entries[itemIndex], isDark);
                  }
                  offset += entries.length;
                }
                return const SizedBox.shrink();
              },
            ),
          ),
      ],
    );
  }

  Widget _buildVolumeHeader(int volume, int count, bool isDark) {
    return Container(
      color: isDark ? Colors.grey[800] : Colors.brown.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.menu_book, size: 18, color: Colors.brown),
          const SizedBox(width: 8),
          Text(
            'เล่มที่ $volume  ($count รายการ)',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.brown[200] : Colors.brown[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedEntry(EtipitakaItem item, bool isDark) {
    return ListTile(
      title: Text(
        'หน้า ${item.page}',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: isDark ? Colors.grey[100] : Colors.grey[900],
        ),
      ),
      subtitle: item.excerpt.isNotEmpty
          ? RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
                children: _highlightText(
                  item.excerpt.length > 100
                      ? '${item.excerpt.substring(0, 100)}...'
                      : item.excerpt,
                  _query,
                ),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Icon(Icons.chevron_right, color: Colors.brown),
      onTap: () {
        final resultIndex = _allResults.indexOf(item);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EtipitakaContentPage(
              title: item.title,
              code: _selectedCode,
              volume: item.volume,
              page: item.page,
              results: _allResults,
              resultIndex: resultIndex >= 0 ? resultIndex : 0,
              searchQuery: _query,
            ),
          ),
        );
      },
    );
  }
}

class _CategoryInfo {
  final String code;
  final String label;
  final IconData icon;

  const _CategoryInfo(this.code, this.label, this.icon);
}

class _CategoryCard extends StatelessWidget {
  final _CategoryInfo category;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 6 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(
                color: isDark ? Colors.brown[200]! : Colors.brown,
                width: 2.5,
              )
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(category.icon, size: 36, color: Colors.brown),
              const SizedBox(height: 8),
              Text(
                category.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.grey[100] : Colors.grey[900],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
