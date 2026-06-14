import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import '../../providers/search_books_provider.dart';
import 'SearchBooksReaderPage.dart';

class SearchBooksListPage extends StatefulWidget {
  const SearchBooksListPage({super.key});

  @override
  State<SearchBooksListPage> createState() => _SearchBooksListPageState();
}

class _SearchBooksListPageState extends State<SearchBooksListPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SearchBooksProvider>().fetchBooks();
    });
    _searchController.addListener(() {
      setState(() => _searchTerm = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
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
          style: TextStyle(fontSize: 16, letterSpacing: 0.5, color: Colors.white),
        ),
        actions: [
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return GestureDetector(
                onTap: () => themeProvider.toggleTheme(!themeProvider.isDarkMode),
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

          return Column(
            children: [
              Padding(
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[800]
                        : Colors.grey[100],
                  ),
                ),
              ),
              if (_searchTerm.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'ພົບ ${books.length} ລາຍການ',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: books.isEmpty
                    ? Center(
                        child: Text(
                          _searchTerm.isNotEmpty
                              ? 'ບໍ່ພົບປຶ້ມທີ່ກົງກັບ "$_searchTerm"'
                              : 'ບໍ່ມີປຶ້ມ',
                          style: const TextStyle(fontSize: 16),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          int crossAxisCount;
                          double childAspectRatio;

                          if (constraints.maxWidth >= 1200) {
                            crossAxisCount = 6;
                            childAspectRatio = 0.7;
                          } else if (constraints.maxWidth >= 800) {
                            crossAxisCount = 4;
                            childAspectRatio = 0.7;
                          } else {
                            crossAxisCount = 3;
                            childAspectRatio = 0.65;
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: GridView.builder(
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                childAspectRatio: childAspectRatio,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: books.length,
                              itemBuilder: (context, index) {
                                final book = books[index];
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
                                    children: [
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.2),
                                                spreadRadius: 2,
                                                blurRadius: 6,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                            borderRadius: BorderRadius.circular(8.0),
                                            border: Border.all(
                                              color: Colors.grey.shade300,
                                              width: 1.0,
                                            ),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8.0),
                                            child: CachedNetworkImage(
                                              imageUrl: book.coverFullUrl,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) => const Center(
                                                child: CircularProgressIndicator(),
                                              ),
                                              errorWidget: (context, url, error) =>
                                                  Image.asset('assets/default_image_old.jpg'),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      _highlightedText(
                                        book.title,
                                        _searchTerm,
                                        Theme.of(context).brightness == Brightness.dark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                      Text(
                                        '${book.totalPages} ໜ້າ',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _highlightedText(String text, String query, Color defaultColor) {
    if (query.isEmpty || !text.toLowerCase().contains(query.toLowerCase())) {
      return Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: defaultColor,
        ),
      );
    }

    final regex = RegExp(RegExp.escape(query), caseSensitive: false);
    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black,
          backgroundColor: Color(0xFFFFD700),
        ),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: defaultColor,
        ),
        children: spans,
      ),
    );
  }
}
