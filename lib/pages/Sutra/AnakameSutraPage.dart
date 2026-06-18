// ignore_for_file: file_names, library_private_types_in_public_api, prefer_const_constructors, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../themes/ThemeProvider.dart';
import '../../layouts/NavigationDrawer.dart' as custom_nav;
import 'AnakameSutraContentPage.dart';

class AnakameSutraItem {
  final String title;
  final String url;
  AnakameSutraItem({required this.title, required this.url});
}

class _Category {
  final String name;
  final String url;
  final IconData icon;
  final String subtitle;
  const _Category(this.name, this.url, this.icon, this.subtitle);
}

const List<_Category> _categories = [
  _Category(
    'Sutta',
    'http://anakame.com/page/1_Sutas/main/1_Sutta.htm',
    Icons.menu_book,
    '1. Suttas collection',
  ),
  _Category(
    'Sutta Set',
    'http://anakame.com/page/4_Suta_Set/Main/Main_Set01.htm',
    Icons.library_books,
    '4. Sutta Sets',
  ),
  _Category(
    'Short Sutta',
    'http://anakame.com/page/4_Short_Sutta.htm',
    Icons.auto_stories,
    '4. Short Suttas',
  ),
  _Category(
    'Person',
    'http://anakame.com/page/7_person.htm',
    Icons.person,
    '7. Persons',
  ),
  _Category(
    'Misc',
    'http://anakame.com/page/8_Misc.htm',
    Icons.category,
    '8. Miscellaneous',
  ),
];

class AnakameSutraPage extends StatefulWidget {
  const AnakameSutraPage({super.key});

  @override
  _AnakameSutraPageState createState() => _AnakameSutraPageState();
}

class _AnakameSutraPageState extends State<AnakameSutraPage> {
  void _openCategory(_Category cat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnakameSutraContentPage(
          title: cat.name,
          contentUrl: cat.url,
          tagListing: true,
        ),
      ),
    );
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
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu_open, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ],
      ),
      drawer: const custom_nav.NavigationDrawer(),
      body: _buildCategoryGrid(),
    );
  }

  Widget _buildCategoryGrid() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final cat = _categories[index];
        return GestureDetector(
          onTap: () => _openCategory(cat),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.grey[700]! : Colors.brown.shade200,
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.brown.withValues(alpha: 0.1),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(cat.icon, size: 36, color: Colors.brown),
                  const SizedBox(height: 10),
                  Text(
                    cat.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey[100] : Colors.grey[800],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cat.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
