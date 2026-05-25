// ignore_for_file: library_private_types_in_public_api, file_names, prefer_const_constructors, unnecessary_null_comparison, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/sutra_provider.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import 'BookReadingScreenPage.dart';
import 'DetailPage.dart';

class CategoryListPage extends StatefulWidget {
  final List<List<dynamic>>? data;
  final String selectedCategory;
  final String searchTerm;

  const CategoryListPage({
    super.key,
    this.data,
    required this.selectedCategory,
    required this.searchTerm,
  });

  @override
  _CategoryListPageState createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> {
  late List<List<dynamic>> _filteredData;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final data =
        widget.data ?? Provider.of<SutraProvider>(context, listen: false).data;
    _filteredData = _filterData(widget.searchTerm, data);
    _searchController.text = widget.searchTerm;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<List<dynamic>> _filterData(String searchTerm, List<List<dynamic>> data) {
    return data
        .where(
          (row) =>
              row.length > 4 &&
              row[4] == widget.selectedCategory &&
              row.any(
                (cell) => cell.toString().toLowerCase().contains(
                  searchTerm.toLowerCase(),
                ),
              ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    TextSpan highlightSearchTerm(
      BuildContext context,
      String text,
      String searchTerm,
    ) {
      final theme = Theme.of(context);
      final textColor =
          theme.textTheme.bodyLarge?.color; // Dynamically get the color

      if (searchTerm.isEmpty) {
        return TextSpan(
          text: text,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        );
      }

      final RegExp regex = RegExp(searchTerm, caseSensitive: false);
      final List<TextSpan> spans = [];
      int lastIndex = 0;

      regex.allMatches(text).forEach((match) {
        final String beforeMatch = text.substring(lastIndex, match.start);
        final String matchedText = text.substring(match.start, match.end);

        spans.add(
          TextSpan(
            text: beforeMatch,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        );

        spans.add(
          TextSpan(
            text: matchedText,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: Colors.black, // Keep highlight color for visibility
              backgroundColor: Color(0xFFFFD700),
            ),
          ),
        );

        lastIndex = match.end;
      });

      spans.add(
        TextSpan(
          text: text.substring(lastIndex),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: textColor, // Dynamically get theme color
          ),
        ),
      );

      return TextSpan(children: spans);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown,
        title: Text(
          widget.selectedCategory,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu_open, color: Colors.white),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          ),
          const SizedBox(width: 15),
          // Add a switch to toggle dark mode
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(2.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 17.0, letterSpacing: 0.5),
              decoration: InputDecoration(
                hintText: 'ຄົ້ນຫາພຣະສູດ...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            final data =
                                widget.data ??
                                Provider.of<SutraProvider>(
                                  context,
                                  listen: false,
                                ).data;
                            _filteredData = _filterData('', data);
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  final data =
                      widget.data ??
                      Provider.of<SutraProvider>(context, listen: false).data;
                  _filteredData = _filterData(value, data);
                });
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredData.length,
              itemBuilder: (context, index) {
                final rowData = _filteredData[index];
                final title = rowData.length > 1 ? rowData[1].toString() : '';

                return Card(
                  elevation: 8,
                  margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15.0),
                  ),
                  shadowColor: Color.fromARGB(255, 91, 50, 35).withOpacity(0.9),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15.0),
                    ),
                    child: ListTile(
                      title: Consumer<ThemeProvider>(
                        builder: (context, themeProvider, child) {
                          return RichText(
                            text: highlightSearchTerm(
                              context,
                              title,
                              _searchController.text,
                            ),
                          );
                        },
                      ),
                      onTap: () {
                        // Navigate to detail page or perform other actions
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DetailPage(
                              items: _filteredData
                                  .map(
                                    (e) => {
                                      'id': e.isNotEmpty ? e[0] : '',
                                      'title': e.length > 1 ? e[1] : '',
                                      'details': e.length > 3 ? e[3] : '',
                                      'category': e.length > 4 ? e[4] : '',
                                      'audio': e.length > 5 ? e[5] : '/',
                                    },
                                  )
                                  .toList(),
                              initialIndex: index,
                              searchTerm: _searchController.text,
                              onFavoriteChanged: () => setState(() {}),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _filteredData.isNotEmpty
          ? FloatingActionButton(
              onPressed: () {
                // Implement your action here, e.g., navigate to book reading screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BookReadingScreenPage(
                      filteredData: _filteredData,
                      onFavoriteChanged: () => setState(() {}),
                    ),
                  ),
                );
              },
              tooltip: 'ອ່ານປຶ້ມ',
              backgroundColor: Colors.brown,
              child: const Icon(
                Icons.auto_stories_outlined,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}
