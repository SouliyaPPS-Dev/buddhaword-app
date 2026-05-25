import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SutraProvider with ChangeNotifier {
  List<List<dynamic>> _data = [];
  List<String> _categories = [];
  bool _isLoading = false;

  List<List<dynamic>> get data => _data;
  List<String> get categories => _categories;
  bool get isLoading => _isLoading;

  Future<void> fetchData({String searchTerm = ''}) async {
    _isLoading = true;
    Future.microtask(() => notifyListeners());

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? cachedData = prefs.getString('cachedData');

    final results = await Connectivity().checkConnectivity();
    bool hasInternet = !results.contains(ConnectivityResult.none);

    if (!hasInternet) {
      if (cachedData != null && cachedData.isNotEmpty) {
        final List<dynamic> cachedList = json.decode(cachedData);
        _data = cachedList
            .cast<List<dynamic>>()
            .where((row) => row.isNotEmpty && row[0].toString() != '0')
            .toList();
        _updateCategories();
      }
      _isLoading = false;
      Future.microtask(() => notifyListeners());
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/1mKtgmZ_Is4e6P3P5lvOwIplqx7VQ3amicgienGN9zwA/values/Sheet1!1:1000000?key=AIzaSyDFjIl-SEHUsgK0sjMm7x0awpf8tTEPQjs',
        ),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final List<dynamic> sheetValues =
            jsonResponse['values'] as List<dynamic>;

        final List<List<dynamic>> values = sheetValues
            .skip(1)
            .map((row) => List<dynamic>.from(row))
            .where((row) => row.isNotEmpty && row[0].toString() != '0')
            .toList();

        _data = values;
        prefs.setString('cachedData', json.encode(_data));
        _updateCategories();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching data: $e');
      }
      if (cachedData != null && cachedData.isNotEmpty) {
        _data = (json.decode(cachedData) as List).cast<List<dynamic>>();
        _updateCategories();
      }
    }

    _isLoading = false;
    Future.microtask(() => notifyListeners());
  }

  void _updateCategories() {
    _categories = _data
        .map((row) => row.length > 4 ? row[4].toString() : '')
        .toSet()
        .where((c) => c.isNotEmpty)
        .toList();
  }

  List<dynamic>? getSutraById(String id) {
    try {
      return _data.firstWhere(
        (row) => row.isNotEmpty && row[0].toString() == id,
      );
    } catch (e) {
      return null;
    }
  }
}
