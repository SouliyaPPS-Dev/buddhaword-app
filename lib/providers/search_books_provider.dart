import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  String get coverFullUrl => coverUrl.startsWith('http')
      ? coverUrl
      : '$_baseUrl$coverUrl';
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

class SearchBooksProvider with ChangeNotifier {
  List<BookSummary> _books = [];
  bool _isLoading = false;
  String? _error;

  List<BookSummary> get books => _books;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<bool> _hasInternet() async {
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }

  Future<List<BookSummary>> fetchBooks({bool forceRefresh = false}) async {
    if (_books.isNotEmpty && !forceRefresh) return _books;

    _isLoading = true;
    _error = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('searchBooks_list');

    if (!await _hasInternet()) {
      if (cached != null && cached.isNotEmpty) {
        _books = (json.decode(cached) as List)
            .map((e) => BookSummary.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      _isLoading = false;
      notifyListeners();
      return _books;
    }

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
      } else {
        _error = 'Failed to load books: ${response.statusCode}';
      }
    } catch (e) {
      _error = 'Error fetching books: $e';
      if (cached != null && cached.isNotEmpty) {
        _books = (json.decode(cached) as List)
            .map((e) => BookSummary.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }

    _isLoading = false;
    notifyListeners();
    return _books;
  }

  Future<BookDetail?> fetchBookDetail(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'searchBooks_detail_$slug';
    final cached = prefs.getString(cacheKey);

    if (!await _hasInternet()) {
      if (cached != null && cached.isNotEmpty) {
        return BookDetail.fromJson(json.decode(cached) as Map<String, dynamic>);
      }
      return null;
    }

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
      if (cached != null && cached.isNotEmpty) {
        return BookDetail.fromJson(json.decode(cached) as Map<String, dynamic>);
      }
    }
    return null;
  }

  Future<PageNavResult?> fetchPage(String slug, int pageNum, {String? highlight}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'searchBooks_page_${slug}_$pageNum';
    final cached = prefs.getString(cacheKey);

    if (!await _hasInternet()) {
      if (cached != null && cached.isNotEmpty) {
        return PageNavResult.fromJson(json.decode(cached) as Map<String, dynamic>);
      }
      return null;
    }

    try {
      String url = '$_baseUrl/api/search-books/page-nav?book=$slug&n=$pageNum';
      if (highlight != null && highlight.isNotEmpty) {
        url += '&q=${Uri.encodeComponent(highlight)}';
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final result = PageNavResult.fromJson(data);
        await prefs.setString(cacheKey, json.encode(data));
        return result;
      }
    } catch (e) {
      if (cached != null && cached.isNotEmpty) {
        return PageNavResult.fromJson(json.decode(cached) as Map<String, dynamic>);
      }
    }
    return null;
  }

  Future<List<SearchResult>> searchInBook(String slug, String query) async {
    if (!await _hasInternet()) return [];

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
    return [];
  }
}
