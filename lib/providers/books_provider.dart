import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class BooksProvider with ChangeNotifier {
  List<List<dynamic>> _data = [];
  bool _isLoading = false;

  List<List<dynamic>> get data => _data;
  bool get isLoading => _isLoading;

  Future<void> fetchData() async {
    _isLoading = true;
    notifyListeners();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? cachedData = prefs.getString('booksLocalData');

    final results = await Connectivity().checkConnectivity();
    bool hasInternet = !results.contains(ConnectivityResult.none);

    if (!hasInternet) {
      if (cachedData != null && cachedData.isNotEmpty) {
        _data = (json.decode(cachedData) as List).cast<List<dynamic>>();
      }
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/1mKtgmZ_Is4e6P3P5lvOwIplqx7VQ3amicgienGN9zwA/values/books!1:1000000?key=AIzaSyDFjIl-SEHUsgK0sjMm7x0awpf8tTEPQjs',
        ),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final List<dynamic> sheetValues =
            jsonResponse['values'] as List<dynamic>;

        final List<List<dynamic>> values = sheetValues
            .skip(1)
            .map((row) => List<dynamic>.from(row))
            .toList();

        _data = values;
        prefs.setString('booksLocalData', json.encode(_data));
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching books data: $e');
      }
      if (cachedData != null && cachedData.isNotEmpty) {
        _data = (json.decode(cachedData) as List).cast<List<dynamic>>();
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  List<dynamic>? getBookById(String id) {
    try {
      return _data.firstWhere(
        (row) => row.isNotEmpty && row[0].toString() == id,
      );
    } catch (e) {
      return null;
    }
  }
}
