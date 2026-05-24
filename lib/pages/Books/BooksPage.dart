// ignore_for_file: prefer_const_constructors, library_private_types_in_public_api, file_names, prefer_const_constructors_in_immutables, unnecessary_null_comparison, avoid_web_libraries_in_flutter, unrelated_type_equality_checks, use_build_context_synchronously, deprecated_member_use, depend_on_referenced_packages

import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'RandomImagePage.dart';

class BooksPage extends StatefulWidget {
  BooksPage({super.key});

  @override
  _BooksPageState createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage> {
  final TextEditingController _searchController = TextEditingController();

  List<List<dynamic>> _data = [];
  List<List<dynamic>> _filteredData = [];
  String _searchTerm = '';
  String _selectedCategory = ''; // Define _selectedCategory

  bool hasInternet = true;

  @override
  void initState() {
    super.initState();

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await Future.delayed(Duration(seconds: 1));

      if (hasInternet) {
        await fetchDataFromAPI(_searchTerm);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Initialization error: $e');
      }
    }
  }

  Future<void> saveToSharedPreferences(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value.toString());
    } catch (e) {
      if (kDebugMode) {
        print('Error saving to SharedPreferences: $e');
      }
    }
  }

  Future<String?> getFromSharedPreferences(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting from SharedPreferences: $e');
      }
    }
    return null;
  }

  Future<void> fetchDataFromAPI(String searchTerm) async {
    bool hasInternet =
        !(await Connectivity().checkConnectivity()).contains(ConnectivityResult.none);

    try {
      if (hasInternet) {
        final response = await http.get(Uri.parse(
            'https://sheets.googleapis.com/v4/spreadsheets/1mKtgmZ_Is4e6P3P5lvOwIplqx7VQ3amicgienGN9zwA/values/books!1:1000000?key=AIzaSyDFjIl-SEHUsgK0sjMm7x0awpf8tTEPQjs'));

        if (response.statusCode == 200) {
          final Map<String, dynamic> jsonResponse = json.decode(response.body);
          final List<dynamic> sheetValues =
              jsonResponse['values'] as List<dynamic>;

          final List<List<dynamic>> values = sheetValues
              .skip(1)
              .map((row) => List<dynamic>.from(row))
              .toList();

          _data = values;

          // Storing data
          await saveToSharedPreferences('booksLocalData', json.encode(_data));
        } else {
          if (kDebugMode) {
            print('Failed to load data: ${response.statusCode}');
          }
        }
      }
    } catch (e) {
      if (!hasInternet) {
        final cachedDataLocal =
            await getFromSharedPreferences('booksLocalData');
        if (cachedDataLocal != null && cachedDataLocal.isNotEmpty) {
          final List<dynamic> cachedValues = json.decode(cachedDataLocal);
          _data = cachedValues.cast<List<dynamic>>();
          updateData(searchTerm, _selectedCategory);
          return; // Return here to avoid further execution
        }
      } else {
        final cachedDataLocal =
            await getFromSharedPreferences('booksLocalData');
        if (cachedDataLocal != null && cachedDataLocal.isNotEmpty) {
          final List<dynamic> cachedValues = json.decode(cachedDataLocal);
          _data = cachedValues.cast<List<dynamic>>();

          // Update data with cached values
          updateData(searchTerm, _selectedCategory);
        }
      }
    }

    // Update data after fetching or loading from cache
    updateData(searchTerm, _selectedCategory);
  }

  Future<void> fetchData(String searchTerm) async {
    String? cachedDataLocal = await getFromSharedPreferences('booksLocalData');
    if (cachedDataLocal != null && cachedDataLocal.isNotEmpty) {
      final List<dynamic> cachedValues = json.decode(cachedDataLocal);
      _data = cachedValues.cast<List<dynamic>>();
      // Call updateData without _selectedCategory
      updateData(searchTerm, _selectedCategory);
    }
  }

  Future<void> fetchDataOffline(String searchTerm) async {
    bool hasInternet =
        !(await Connectivity().checkConnectivity()).contains(ConnectivityResult.none);

    final cachedDataLocal = await getFromSharedPreferences('booksLocalData');

    if (cachedDataLocal != null && cachedDataLocal.isNotEmpty) {
      final List<dynamic> cachedValues = json.decode(cachedDataLocal);
      _data = cachedValues.cast<List<dynamic>>();
      updateData(searchTerm, _selectedCategory);
    } else {
      if (kDebugMode) {
        print('No cached data available');
      }
    }

    try {
      if (!hasInternet) {
        // Check local storage for cached data

        if (cachedDataLocal != null && cachedDataLocal.isNotEmpty) {
          final List<dynamic> cachedValues = json.decode(cachedDataLocal);
          setState(() {
            _data = cachedValues.cast<List<dynamic>>();
          });

          updateData(searchTerm, _selectedCategory);
          return;
        }
      }
    } catch (e) {
      if (!hasInternet) {
        final cachedDataLocal =
            await getFromSharedPreferences('booksLocalData');
        if (cachedDataLocal != null && cachedDataLocal.isNotEmpty) {
          final List<dynamic> cachedValues = json.decode(cachedDataLocal);
          _data = cachedValues.cast<List<dynamic>>();
          updateData(searchTerm, _selectedCategory);

          return; // Return here to avoid further execution
        }
      } else {
        final cachedDataLocal =
            await getFromSharedPreferences('booksLocalData');
        if (cachedDataLocal != null && cachedDataLocal.isNotEmpty) {
          final List<dynamic> cachedValues = json.decode(cachedDataLocal);
          _data = cachedValues.cast<List<dynamic>>();

          // Update data with cached values
          updateData(searchTerm, _selectedCategory);
        }
      }
    }

    if (hasInternet) {
      final cachedDataLocal = await getFromSharedPreferences('booksLocalData');
      if (cachedDataLocal != null && cachedDataLocal.isNotEmpty) {
        final List<dynamic> cachedValues = json.decode(cachedDataLocal);
        _data = cachedValues.cast<List<dynamic>>();
        updateData(searchTerm, _selectedCategory);

        return; // Return here to avoid further execution
      }
    }

    // Update data after fetching or loading from cache
    updateData(searchTerm, _selectedCategory);
  }

  void updateData(String searchTerm, String selectedCategory) {
    List<List<dynamic>> filteredData = _data
        .where((row) {
          return row.any((cell) =>
              cell.toString().toLowerCase().contains(searchTerm.toLowerCase()));
        })
        .where((row) => row.isNotEmpty && row[0] != '0')
        .where((row) =>
            selectedCategory.isEmpty ||
            row.length > 2 && row[2] == selectedCategory)
        .toList();

    filteredData = filteredData;

    setState(() {
      _filteredData = filteredData;
    });
  }

  void _shareAllBooksLink() {
    const url = 'https://buddhaword.free.nf/book';

    String? title = 'ປື້ມ & ເເຜນຜັງ';

    final shareText = '$title\n $url';

    Share.share(shareText, subject: title);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_open, color: Colors.white),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: Text(
          'ປື້ມ & ເເຜນຜັງ',
          style: TextStyle(fontSize: 16, letterSpacing: 0.5),
        ),
        actions: [
          IconButton(
            icon: _data.isEmpty
                ? const SizedBox(
                    width: 20.0, // Custom width
                    height: 20.0, // Custom height
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white), // Change color here
                      strokeWidth: 2.0, // Optional: change the stroke width
                    ),
                  )
                : const Icon(Icons.update_outlined),
            onPressed: () async {
              await fetchDataFromAPI(_searchTerm);

              if (_data.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Data has been successfully updated'),
                    duration: Duration(seconds: 2),
                    backgroundColor:
                        Colors.green, // Set the background color to green
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 5),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _shareAllBooksLink,
          ),
          const SizedBox(width: 15),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      themeProvider.toggleTheme(!themeProvider.isDarkMode);
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          themeProvider.isDarkMode ? "☀️" : "🌙",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 15),
        ],
      ),
      drawer: const custom_nav.NavigationDrawer(),
      body: _data.isEmpty
          ? RandomImagePage()
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context)
                        .size
                        .width), // Constrain width of the row
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _searchController,
                        style:
                            const TextStyle(fontSize: 17.0, letterSpacing: 0.5),
                        decoration: InputDecoration(
                          hintText: 'ຄົ້ນຫາ...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      _searchTerm = '';
                                      fetchData(_searchTerm);
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchTerm = value;
                            fetchData(_searchTerm);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory.isNotEmpty
                            ? _selectedCategory
                            : null,
                        decoration: InputDecoration(
                          hintText: 'ໝວດ',
                          suffixIcon: _selectedCategory.isNotEmpty
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _selectedCategory, // Display selected category value
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                            letterSpacing: 0.5),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        setState(() {
                                          _selectedCategory = '';
                                          if (_searchTerm.isEmpty) {
                                            updateData(
                                                _searchTerm, _selectedCategory);
                                          } else {
                                            fetchData(_searchTerm);
                                          }
                                        });
                                      },
                                    ),
                                  ],
                                )
                              : null,
                        ),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedCategory = newValue ?? '';
                            if (_searchTerm.isEmpty) {
                              updateData(_searchTerm, _selectedCategory);
                            } else {
                              fetchData(_searchTerm);
                            }
                          });
                        },
                        items: _data.isEmpty
                            ? null
                            : _data
                                .map((row) =>
                                    row.length > 2 ? row[2].toString() : '')
                                .toSet()
                                .toList()
                                .map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Adjust the grid layout based on screen width
                    int crossAxisCount;
                    double childAspectRatio;

                    if (constraints.maxWidth >= 1200) {
                      // Desktop layout
                      crossAxisCount = 6;
                      childAspectRatio = 0.7;
                    } else if (constraints.maxWidth >= 800) {
                      // Tablet layout
                      crossAxisCount = 4;
                      childAspectRatio = 0.7;
                    } else {
                      // Mobile layout with 3 items per row
                      crossAxisCount = 3;
                      childAspectRatio = 0.65;
                    }

                    return _filteredData.isEmpty
                        ? RandomImagePage()
                        : Container(
                            width: double.infinity, // Full width
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage(
                                    'assets/wooden_background.jpg'), // Your wooden background image
                                fit: BoxFit.cover,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: GridView.builder(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: childAspectRatio,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: _filteredData.length,
                                itemBuilder: (context, index) {
                                  final book = _filteredData[index];
                                  final title = book.isNotEmpty
                                      ? book[1]
                                      : 'Unknown Title';
                                  final coverImageUrl = book.length > 1
                                      ? book[5]
                                        : 'assets/default_image_old.jpg';

                                  final linkOpen = book.length > 1
                                      ? book[4]
                                      : 'https://drive.google.com/drive/u/0/folders/1z6vIdR-fzXxxhCM-rjqq8F7ZHLNlP5E3';

                                  return GestureDetector(
                                    onTap: () async {
                                      if (await canLaunch(linkOpen)) {
                                        await launch(linkOpen);
                                      } else {
                                        throw 'Could not launch $linkOpen';
                                      }
                                    },
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.2),
                                                  spreadRadius: 2,
                                                  blurRadius: 6,
                                                  offset: Offset(0, 3),
                                                ),
                                              ],
                                              borderRadius:
                                                  BorderRadius.circular(8.0),
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                                width: 1.0,
                                              ),
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8.0),
                                              child: Image.network(
                                                coverImageUrl,
                                                fit: BoxFit.cover,
                                                loadingBuilder:
                                                    (BuildContext context,
                                                        Widget child,
                                                        ImageChunkEvent?
                                                            loadingProgress) {
                                                  if (loadingProgress == null) {
                                                    return child;
                                                  } else {
                                                    return Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                        value: loadingProgress
                                                                    .expectedTotalBytes !=
                                                                null
                                                            ? loadingProgress
                                                                    .cumulativeBytesLoaded /
                                                                (loadingProgress
                                                                        .expectedTotalBytes ??
                                                                    1)
                                                            : null,
                                                      ),
                                                    );
                                                  }
                                                },
                                                errorBuilder: (BuildContext
                                                        context,
                                                    Object exception,
                                                    StackTrace? stackTrace) {
                                                  return Image.asset(
                                                          'assets/default_image_old.jpg',
                                                        ); // A local placeholder image
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: 5),
                                        Text(
                                          title,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors
                                                .white, // Changed to white to stand out more
                                            shadows: [
                                              Shadow(
                                                offset: Offset(1.5, 1.5),
                                                blurRadius: 3.0,
                                                color: Colors.black.withOpacity(
                                                    0.5), // Dark shadow to enhance readability
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                  },
                ),
              ),
            ]),
    );
  }
}
