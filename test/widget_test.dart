// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lao_tipitaka/main.dart';
import 'package:lao_tipitaka/providers/books_provider.dart';
import 'package:lao_tipitaka/providers/calendar_provider.dart';
import 'package:lao_tipitaka/providers/sutra_provider.dart';
import 'package:lao_tipitaka/providers/video_provider.dart';
import 'package:lao_tipitaka/providers/search_books_provider.dart';
import 'package:lao_tipitaka/themes/ThemeProvider.dart';

void main() {
  testWidgets('App loads without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => SutraProvider()),
          ChangeNotifierProvider(create: (_) => VideoProvider()),
          ChangeNotifierProvider(create: (_) => CalendarProvider()),
          ChangeNotifierProvider(create: (_) => BooksProvider()),
          ChangeNotifierProvider(create: (_) => SearchBooksProvider()),
        ],
        child: const MyApp(),
      ),
    );

    // Initial pump for SplashScreen
    await tester.pump();
    
    // SplashScreen has a 2-second delay
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Verify that we are on the home page (MyHomePage)
    // MyHomePage title is an Image with asset 'assets/buddha_nature_logo.png'
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('Small screen layout test', (WidgetTester tester) async {
    // Set a very small screen size to trigger overflows
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => SutraProvider()),
          ChangeNotifierProvider(create: (_) => VideoProvider()),
          ChangeNotifierProvider(create: (_) => CalendarProvider()),
          ChangeNotifierProvider(create: (_) => BooksProvider()),
          ChangeNotifierProvider(create: (_) => SearchBooksProvider()),
        ],
        child: const MyApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // If there's an overflow, it will be caught by the test framework
  });
}
