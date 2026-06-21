import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

const String _baseUrl = 'https://buddhaword-web.hf.space';

class BookSummary {
  final String slug;
  final String title;
  final int year;
  final int totalPages;
  final String type;
  final String coverUrl;

  BookSummary({
    required this.slug,
    required this.title,
    required this.year,
    required this.totalPages,
    required this.type,
    required this.coverUrl,
  });

  factory BookSummary.fromJson(Map<String, dynamic> json) {
    return BookSummary(
      slug: json['slug'] ?? '',
      title: json['title'] ?? '',
      year: json['year'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
      type: json['type'] ?? '',
      coverUrl: json['coverUrl'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'title': title,
    'year': year,
    'totalPages': totalPages,
    'type': type,
    'coverUrl': coverUrl,
  };

  String get coverFullUrl {
    if (coverUrl.startsWith('http')) return coverUrl;
    if (coverUrl.startsWith('assets/')) return coverUrl;
    return '$_baseUrl$coverUrl';
  }
}

class PageContent {
  final int number;
  final String text;

  PageContent({required this.number, required this.text});

  factory PageContent.fromJson(Map<String, dynamic> json) {
    return PageContent(
      number: json['number'] ?? 0,
      text: json['text'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'number': number,
    'text': text,
  };
}

class BookDetail {
  final String slug;
  final String title;
  final int year;
  final int totalPages;
  final String type;
  final String coverUrl;
  final String preview;

  BookDetail({
    required this.slug,
    required this.title,
    required this.year,
    required this.totalPages,
    required this.type,
    required this.coverUrl,
    required this.preview,
  });

  factory BookDetail.fromJson(Map<String, dynamic> json) {
    return BookDetail(
      slug: json['slug'] ?? '',
      title: json['title'] ?? '',
      year: json['year'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
      type: json['type'] ?? '',
      coverUrl: json['coverUrl'] ?? '',
      preview: json['preview'] ?? '',
    );
  }
}

class PageNavResult {
  final String bookSlug;
  final String bookTitle;
  final int totalPages;
  final PageContent page;
  final List<String> highlightWords;
  final int? prevPage;
  final int? nextPage;

  PageNavResult({
    required this.bookSlug,
    required this.bookTitle,
    required this.totalPages,
    required this.page,
    required this.highlightWords,
    this.prevPage,
    this.nextPage,
  });

  factory PageNavResult.fromJson(Map<String, dynamic> json) {
    final book = json['book'] as Map<String, dynamic>? ?? {};
    final pageJson = json['page'] as Map<String, dynamic>? ?? {};
    return PageNavResult(
      bookSlug: book['slug'] ?? '',
      bookTitle: book['title'] ?? '',
      totalPages: book['totalPages'] ?? 0,
      page: PageContent.fromJson(pageJson),
      highlightWords: (json['highlightWords'] as List?)?.cast<String>() ?? [],
      prevPage: json['prevPage'],
      nextPage: json['nextPage'],
    );
  }
}

class SearchResult {
  final int page;
  final String snippet;
  final int matches;

  SearchResult({
    required this.page,
    required this.snippet,
    required this.matches,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      page: json['page'] ?? 0,
      snippet: json['snippet'] ?? '',
      matches: json['matches'] ?? 0,
    );
  }
}

class GlobalSearchResult {
  final String slug;
  final String bookTitle;
  final String bookType;
  final int page;
  final String snippet;
  final int matches;

  GlobalSearchResult({
    required this.slug,
    required this.bookTitle,
    required this.bookType,
    required this.page,
    required this.snippet,
    required this.matches,
  });

  factory GlobalSearchResult.fromJson(Map<String, dynamic> json) {
    return GlobalSearchResult(
      slug: json['slug'] ?? '',
      bookTitle: json['bookTitle'] ?? '',
      bookType: json['bookType'] ?? '',
      page: json['page'] ?? 0,
      snippet: json['snippet'] ?? '',
      matches: json['matches'] ?? 0,
    );
  }
}

class SearchBooksProvider with ChangeNotifier {
  List<BookSummary> _books = [];
  bool _isLoading = false;
  String? _error;
  final Map<String, int> _slugToIndex = {};

  List<BookSummary> get books => _books;
  bool get isLoading => _isLoading;
  String? get error => _error;

  String _assetDir(String slug) {
    final idx = _slugToIndex[slug];
    if (idx != null) return 'assets/search_books/$idx';
    return 'assets/search_books/$slug';
  }

  Future<String> _getBookTitle(String slug) async {
    final match = _books.where((b) => b.slug == slug);
    if (match.isNotEmpty) return match.first.title;
    final manifestBooks = await _loadManifestBooks();
    final m = manifestBooks.where((b) => b.slug == slug);
    if (m.isNotEmpty) return m.first.title;
    return slug;
  }

  Future<List<BookSummary>> _loadManifestBooks() async {
    try {
      final manifestJson = await rootBundle.loadString(
        'assets/search_books/books.json',
      );
      final list = json.decode(manifestJson) as List;
      final results = <BookSummary>[];
      _slugToIndex.clear();
      for (int i = 0; i < list.length; i++) {
        final e = list[i];
        final slug = e['slug'] as String? ?? '';
        _slugToIndex[slug] = i;
        final dir = _assetDir(slug);
        String coverUrl = '$dir/cover.png';
        try {
          await rootBundle.load(coverUrl);
        } catch (_) {
          coverUrl = '$dir/cover.jpg';
        }
        results.add(BookSummary(
          slug: slug,
          title: e['title'] as String? ?? slug,
          year: 0,
          totalPages: e['totalPages'] as int? ?? 0,
          type: e['type'] as String? ?? '',
          coverUrl: coverUrl,
        ));
      }
      return results;
    } catch (e) {
      if (kDebugMode) print('Error loading manifest: $e');
    }
    return [];
  }

  Future<bool> _hasInternet() async {
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }

  Future<List<BookSummary>> fetchBooks({bool forceRefresh = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('searchBooks_list');

    if (await _hasInternet()) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/api/search-books/list'),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          _books = (data['books'] as List)
              .map((e) => BookSummary.fromJson(e as Map<String, dynamic>))
              .toList();
          await prefs.setString('searchBooks_list', json.encode(_books.map((e) => e.toJson()).toList()));
          await _ensureSlugIndex();
          _isLoading = false;
          _error = null;
          notifyListeners();
          return _books;
        }
      } catch (e) {
        if (kDebugMode) print('Error fetching books: $e');
      }
    }

    if (_books.isNotEmpty && !forceRefresh) {
      _isLoading = false;
      notifyListeners();
      return _books;
    }

    if (cached != null && cached.isNotEmpty) {
      _books = (json.decode(cached) as List)
          .map((e) => BookSummary.fromJson(e as Map<String, dynamic>))
          .toList();
      await _ensureSlugIndex();
      _isLoading = false;
      notifyListeners();
      return _books;
    }

    final manifestBooks = await _loadManifestBooks();
    if (manifestBooks.isNotEmpty) {
      _books = manifestBooks;
    } else {
      _error = 'ບໍ່ສາມາດໂຫຼດຂໍ້ມູນໄດ້ (ບໍ່ມີອິນເຕີເນັດ)';
    }

    _isLoading = false;
    notifyListeners();
    return _books;
  }

  Future<void> _ensureSlugIndex() async {
    if (_slugToIndex.isNotEmpty) return;
    try {
      final manifestJson = await rootBundle.loadString(
        'assets/search_books/books.json',
      );
      final list = json.decode(manifestJson) as List;
      for (int i = 0; i < list.length; i++) {
        _slugToIndex[list[i]['slug']] = i;
      }
    } catch (_) {}
  }

  Future<BookDetail?> fetchBookDetail(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'searchBooks_detail_$slug';
    final cached = prefs.getString(cacheKey);

    if (await _hasInternet()) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/api/search-books/details?slug=$slug'),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final detail = BookDetail.fromJson(data['book'] as Map<String, dynamic>);
          await prefs.setString(cacheKey, json.encode(data['book']));
          return detail;
        }
      } catch (e) {
        if (kDebugMode) print('Error fetching book detail: $e');
      }
    }

    if (cached != null && cached.isNotEmpty) {
      return BookDetail.fromJson(json.decode(cached) as Map<String, dynamic>);
    }

    try {
      final dir = _assetDir(slug);
      final bookJson = await rootBundle.loadString(
        '$dir/book.json',
      );
      final data = json.decode(bookJson) as Map<String, dynamic>;
      String coverUrl = '$dir/cover.png';
      try {
        await rootBundle.load(coverUrl);
      } catch (_) {
        coverUrl = '$dir/cover.jpg';
      }
      return BookDetail(
        slug: slug,
        title: data['title'] ?? '',
        year: data['year'] ?? 0,
        totalPages: data['totalPages'] ?? 0,
        type: data['type'] ?? '',
        coverUrl: coverUrl,
        preview: '',
      );
    } catch (e) {
      if (kDebugMode) print('Error loading book asset for $slug: $e');
    }
    return null;
  }

  Future<PageNavResult?> fetchPage(String slug, int pageNum, {String? highlight}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'searchBooks_page_${slug}_$pageNum';
    final cached = prefs.getString(cacheKey);

    if (await _hasInternet()) {
      try {
        final url = '$_baseUrl/api/search-books/page-nav?book=$slug&n=$pageNum';
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final result = PageNavResult.fromJson(data);
          await prefs.setString(cacheKey, json.encode(data));
          return result;
        }
      } catch (e) {
        if (kDebugMode) print('Error fetching page: $e');
      }
    }

    if (cached != null && cached.isNotEmpty) {
      return PageNavResult.fromJson(json.decode(cached) as Map<String, dynamic>);
    }

    try {
      final dir = _assetDir(slug);
      final pagesJson = await rootBundle.loadString(
        '$dir/pages.json',
      );
      final pages = json.decode(pagesJson) as List;
      final pageEntry = pages.firstWhere(
        (p) => p['page'] == pageNum,
        orElse: () => <String, dynamic>{},
      );
      if (pageEntry.isEmpty) return null;

      final totalPages = pages.length;
      final title = await _getBookTitle(slug);
      return PageNavResult(
        bookSlug: slug,
        bookTitle: title,
        totalPages: totalPages,
        page: PageContent(
          number: pageNum,
          text: pageEntry['text'] ?? '',
        ),
        highlightWords: highlight != null && highlight.isNotEmpty
            ? [highlight]
            : [],
        prevPage: pageNum > 1 ? pageNum - 1 : null,
        nextPage: pageNum < totalPages ? pageNum + 1 : null,
      );
    } catch (e) {
      if (kDebugMode) print('Error loading page asset for $slug: $e');
    }
    return null;
  }

  Future<List<GlobalSearchResult>> searchAll(String query) async {
    if (query.trim().isEmpty) return [];
    final q = query.toLowerCase();

    if (await _hasInternet()) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/api/search-books/all?q=${Uri.encodeComponent(query)}'),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          return (data['results'] as List)
              .map((e) => GlobalSearchResult.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (e) {
        if (kDebugMode) print('Error searching all books: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('searchBooks_list');
    Map<String, String> slugToTitle = {};
    if (cached != null && cached.isNotEmpty) {
      final books = json.decode(cached) as List;
      for (final b in books) {
        slugToTitle[b['slug']] = b['title'] ?? b['slug'];
      }
    }

    List<String> slugs = slugToTitle.keys.toList();

    if (slugs.isEmpty) {
      final manifestBooks = await _loadManifestBooks();
      for (final b in manifestBooks) {
        slugToTitle[b.slug] = b.title;
      }
      slugs = slugToTitle.keys.toList();
    }

    await _ensureSlugIndex();

    if (slugs.isEmpty) return [];

    List<GlobalSearchResult> results = [];
    for (final slug in slugs) {
      try {
        final dir = _assetDir(slug);
        final indexJson = await rootBundle.loadString(
          '$dir/index.json',
        );
        final indexEntries = json.decode(indexJson) as List;
        for (final entry in indexEntries) {
          final page = entry['page'] as int;
          final preview = entry['preview'] as String? ?? '';
          if (preview.toLowerCase().contains(q)) {
            int count = 0;
            int start = 0;
            while ((start = preview.toLowerCase().indexOf(q, start)) != -1) {
              count++;
              start += q.length;
            }
            results.add(GlobalSearchResult(
              slug: slug,
              bookTitle: slugToTitle[slug] ?? slug,
              bookType: '',
              page: page,
              snippet: preview,
              matches: count,
            ));
          }
        }
      } catch (e) {
        if (kDebugMode) print('Error loading asset for $slug: $e');
      }
    }
    return results;
  }

  Future<List<SearchResult>> searchInBook(String slug, String query) async {
    if (query.trim().isEmpty) return [];
    final q = query.toLowerCase();

    if (await _hasInternet()) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/api/search-books/search?book=$slug&q=${Uri.encodeComponent(query)}'),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          return (data['results'] as List)
              .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (e) {
        if (kDebugMode) print('Error searching in book: $e');
      }
    }

    try {
      final dir = _assetDir(slug);
      final pagesJson = await rootBundle.loadString(
        '$dir/pages.json',
      );
      final pages = json.decode(pagesJson) as List;
      List<SearchResult> results = [];
      for (final entry in pages) {
        final page = entry['page'] as int;
        final text = entry['text'] as String? ?? '';
        if (text.toLowerCase().contains(q)) {
          int count = 0;
          int start = 0;
          while ((start = text.toLowerCase().indexOf(q, start)) != -1) {
            count++;
            start += q.length;
          }

          final matchIdx = text.toLowerCase().indexOf(q);
          final snippetStart = matchIdx > 100 ? matchIdx - 100 : 0;
          final snippetEnd = snippetStart + 300 < text.length
              ? snippetStart + 300
              : text.length;
          final snippet = text.substring(snippetStart, snippetEnd);

          results.add(SearchResult(
            page: page,
            snippet: snippet,
            matches: count,
          ));
        }
      }
      return results;
    } catch (e) {
      if (kDebugMode) print('Error loading pages for $slug: $e');
    }
    return [];
  }
}
