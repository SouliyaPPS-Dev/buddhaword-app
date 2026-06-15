import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import '../../providers/search_books_provider.dart';
import 'search_books_reader_page.dart';

class SearchBooksListPage extends StatefulWidget {
  const SearchBooksListPage({super.key});

  @override
  State<SearchBooksListPage> createState() => _SearchBooksListPageState();
}

class _SearchBooksListPageState extends State<SearchBooksListPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchTerm = '';
  List<GlobalSearchResult> _globalResults = [];
  bool _isSearching = false;
  Timer? _debounce;
  StreamSubscription? _connectivitySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SearchBooksProvider>().fetchBooks();
    });
    _searchController.addListener(_onSearchChanged);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none) && mounted) {
        context.read<SearchBooksProvider>().fetchBooks(forceRefresh: true);
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    setState(() => _searchTerm = _searchController.text);
    if (_searchTerm.trim().length >= 2) {
      _debounce = Timer(const Duration(milliseconds: 350), _doGlobalSearch);
    } else {
      setState(() {
        _globalResults = [];
        _isSearching = false;
      });
    }
  }

  Future<void> _doGlobalSearch() async {
    final q = _searchTerm.trim();
    if (q.length < 2) return;
    setState(() => _isSearching = true);
    final provider = context.read<SearchBooksProvider>();
    final results = await provider.searchAll(q);
    if (mounted && _searchTerm.trim() == q) {
      setState(() {
        _globalResults = results;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_open, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text(
          'ຄົ້ນຫາປຶ້ມ',
          style: TextStyle(
            fontSize: 16,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
        actions: [
          Consumer<SearchBooksProvider>(
            builder: (context, provider, child) {
              return provider.isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      tooltip: 'ອັບເດດຂໍ້ມູນ',
                      onPressed: () {
                        context.read<SearchBooksProvider>().fetchBooks(
                          forceRefresh: true,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('ກຳລັງອັບເດດຂໍ້ມູນ...'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    );
            },
          ),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return GestureDetector(
                onTap: () =>
                    themeProvider.toggleTheme(!themeProvider.isDarkMode),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    themeProvider.isDarkMode ? "☀️" : "🌙",
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      drawer: const custom_nav.NavigationDrawer(),
      body: Consumer<SearchBooksProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.books.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final books = provider.books.where((b) {
            if (_searchTerm.isEmpty) return true;
            return b.title.toLowerCase().contains(_searchTerm.toLowerCase());
          }).toList();

          final showSearchResults = _searchTerm.trim().length >= 2;
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Stack(
            children: [
              Positioned.fill(
                top: 0,
                child: Padding(
                  padding: const EdgeInsets.only(top: 100),
                  child: showSearchResults
                      ? _buildSearchResultsList(isDark)
                      : _buildBookGrid(books, isDark),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSearchBar(isDark),
                    if (showSearchResults) _buildSearchResultsHeader(isDark),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: 'ພິມຊື່ປຶ້ມເພື່ອຄົ້ນຫາ...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchTerm.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _searchFocus.unfocus();
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
        ),
      ),
    );
  }

  Widget _buildSearchResultsHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            _isSearching
                ? 'ກຳລັງຊອກຫາ...'
                : 'ພົບ ${_globalResults.length} ຜົນການຄົ້ນຫາ',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsList(bool isDark) {
    if (_isSearching && _globalResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_globalResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'ບໍ່ພົບຂໍ້ມູນສຳລັບ "$_searchTerm"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final localQ = _searchTerm;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _globalResults.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final r = _globalResults[index];
        final typeColor = r.bookType == 'pdf'
            ? const Color(0xFF1E88E5)
            : const Color(0xFF43A047);

        return Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SearchBooksReaderPage(
                    slug: r.slug,
                    title: r.bookTitle,
                    totalPages: 0,
                    highlightQuery: localQ,
                    initialPage: r.page,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.brown,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'ໜ້າ ${r.page}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${r.matches} ຄັ້ງ',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[400] : Colors.grey[500],
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            r.bookTitle,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: typeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _highlightedSnippet(r.snippet, localQ, isDark),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_forward,
                          size: 14,
                          color: Colors.brown,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'ເບິ່ງລາຍລະອຽດ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.brown,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _highlightedSnippet(String text, String query, bool isDark) {
    if (query.isEmpty) {
      return Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: isDark ? Colors.grey[300] : Colors.grey[700],
        ),
      );
    }

    final escaped = RegExp.escape(query);
    final regex = RegExp('($escaped)', caseSensitive: false);
    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.yellowAccent : Colors.brown.shade800,
            backgroundColor: isDark
                ? Colors.brown.withValues(alpha: 0.3)
                : const Color(0xFFFFD700),
          ),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: isDark ? Colors.grey[300] : Colors.grey[700],
        ),
        children: spans,
      ),
    );
  }

  Widget _buildBookGrid(List<BookSummary> books, bool isDark) {
    if (books.isEmpty) {
      return Center(
        child: Text(
          _searchTerm.isNotEmpty
              ? 'ບໍ່ພົບປຶ້ມທີ່ກົງກັບ "$_searchTerm"'
              : 'ບໍ່ມີປຶ້ມ',
          style: const TextStyle(fontSize: 16),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        double cardHeight;
        double maxCrossAxisExtent;

        if (constraints.maxWidth >= 1200) {
          maxCrossAxisExtent = 200;
          cardHeight = 305;
        } else if (constraints.maxWidth >= 800) {
          maxCrossAxisExtent = 185;
          cardHeight = 255;
        } else {
          maxCrossAxisExtent = 165;
          cardHeight = 205;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GridView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            clipBehavior: Clip.none,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxCrossAxisExtent,
              mainAxisExtent: cardHeight + 32,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              return _buildBookCard(book, cardHeight, isDark);
            },
          ),
        );
      },
    );
  }

  Widget _buildBookCard(BookSummary book, double cardHeight, bool isDark) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SearchBooksReaderPage(
            slug: book.slug,
            title: book.title,
            totalPages: book.totalPages,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth;
              final standWidth = cardWidth * 1.15;
              final standLeft = -(standWidth - cardWidth) / 2;

              return SizedBox(
                height: cardHeight + 24,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: cardHeight,
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Builder(
                                builder: (context) {
                                  final fallback = Container(
                                    color: Colors.brown.shade700,
                                    child: Center(
                                      child: Text(
                                        book.title.isNotEmpty
                                            ? book.title[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                  if (book.coverUrl.startsWith('assets/')) {
                                    return Image.asset(
                                      book.coverUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => fallback,
                                    );
                                  }
                                  return CachedNetworkImage(
                                    imageUrl: book.coverFullUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      color: Colors.brown.shade700,
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) => fallback,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: cardHeight - 8,
                      left: cardWidth * 0.05,
                      width: cardWidth * 0.9,
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: cardHeight - 2,
                      left: standLeft,
                      width: standWidth,
                      child: _buildBookstandBar(cardHeight),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBookstandBar(double cardHeight) {
    double h;
    if (cardHeight >= 300) {
      h = 14;
    } else if (cardHeight >= 250) {
      h = 11;
    } else {
      h = 9;
    }

    return SizedBox(
      height: h,
      child: Stack(
        children: [
          Container(
            height: h * 0.45,
            decoration: BoxDecoration(
              color: const Color(0xFFB96A44),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
          Positioned(
            top: h * 0.35,
            left: 0,
            right: 0,
            child: Container(
              height: h * 0.3,
              decoration: BoxDecoration(color: const Color(0xFFE0895C)),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: h * 0.35,
              decoration: BoxDecoration(
                color: const Color(0xFFA65D3B),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 4,
            right: 4,
            child: Container(
              height: h * 0.5,
              decoration: BoxDecoration(
                color: const Color(0xFFE0895C).withValues(alpha: 0.3),
              ),
            ),
          ),
          Positioned(
            top: -3,
            left: 2,
            right: 2,
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
