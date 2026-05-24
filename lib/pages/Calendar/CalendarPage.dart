// ignore_for_file: prefer_const_declarations, library_private_types_in_public_api, file_names, use_key_in_widget_constructors, prefer_const_constructors, avoid_web_libraries_in_flutter, unnecessary_null_comparison, unrelated_type_equality_checks, avoid_print, sized_box_for_whitespace, prefer_interpolation_to_compose_strings, deprecated_member_use, depend_on_referenced_packages, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';
import '../Books/RandomImagePage.dart';

class CalendarPage extends StatefulWidget {
  @override
  _CalendarPageState createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final PageController _pageController = PageController();
  Timer? _timer;
  int _currentIndex = 0;

  List<List<dynamic>> _data = [];
  List<String> imageUrls = [];

  bool hasInternet = true;

  Map<DateTime, List<dynamic>> events = {};
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  late ScrollController _scrollController;
  bool _isScrollingDown = false; // Track scroll direction

  @override
  void initState() {
    super.initState();

    _loadEvents();
    fetchCalendarData();

    _scrollController = ScrollController();

    Future.delayed(Duration(milliseconds: 500), _startAutoSlide);
  }

  void _shareCalendar() {
    final url = 'https://buddhaword.free.nf/calendar';
    String? title = 'ປະຕິທິນທັມ';
    final shareText = '$title\n $url';

    Share.share(shareText, subject: title);
  }

  void _startAutoSlide() {
    _timer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (_pageController.hasClients &&
          _pageController.position.hasPixels &&
          _pageController.position.viewportDimension > 0) {
        _currentIndex = (_currentIndex + 1) % imageUrls.length;
        _pageController.animateToPage(
          _currentIndex,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancel the timer when the widget is disposed

    _pageController.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  // Function to scroll down the page progressively when the button is pressed.
// Toggle scroll direction and update the FAB icon
  void _toggleScrollDirection() {
    setState(() {
      _isScrollingDown = !_isScrollingDown;
    });

    // Call the scroll function based on the direction
    _scroll();
  }

  // Function to scroll the page based on direction
  void _scroll() {
    double scrollAmount = 250.0; // Amount to scroll

    // Scroll down or up based on the current direction
    if (_isScrollingDown) {
      _scrollController.animateTo(
        _scrollController.position.pixels + scrollAmount,
        duration: Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      _scrollController.animateTo(
        _scrollController.position.pixels - scrollAmount,
        duration: Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
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

  Future<void> fetchCalendarData() async {
    final storage = await getFromSharedPreferences('slideLocalData');

    bool hasInternet =
        !(await Connectivity().checkConnectivity()).contains(ConnectivityResult.none);

    try {
      if (hasInternet) {
        final response = await http.get(Uri.parse(
            'https://sheets.googleapis.com/v4/spreadsheets/1mKtgmZ_Is4e6P3P5lvOwIplqx7VQ3amicgienGN9zwA/values/calendar!1:1000000?key=AIzaSyDFjIl-SEHUsgK0sjMm7x0awpf8tTEPQjs'));

        if (response.statusCode == 200) {
          final Map<String, dynamic> jsonResponse = json.decode(response.body);
          final List<dynamic> sheetValues =
              jsonResponse['values'] as List<dynamic>;

          final List<List<dynamic>> values = sheetValues
              .skip(1)
              .map((row) => List<dynamic>.from(row))
              .toList();

          setState(() {
            _data = values
                .cast<List<dynamic>>()
                .reversed
                .toList(); // Reverse the list;
          });

          // Store data once
          final encodedData = json.encode(_data);
          saveToSharedPreferences('slideLocalData', encodedData);

          // Calculate and load events
          setState(() {
            events = _calculateEvents(_data);

            imageUrls = _data
                .map((row) => row[0] as String)
                .where((url) => url.isNotEmpty)
                .toList();

            // Automatically select the latest event date or today if available
            DateTime latestEventDay = _latestEventDay(DateTime.now())!;
            _selectedDay = latestEventDay;
            _focusedDay =
                latestEventDay; // Update focused day to the latest event
          });

          print("Loaded events: $events");
        } else {
          if (kDebugMode) {
            print('Failed to load data: ${response.statusCode}');
          }
        }
      } else {
        await _loadCachedData(storage);
      }
    } catch (e) {
      await _loadCachedData(storage);
    }
  }

  /// Updated function to calculate events from _data
  Map<DateTime, List<dynamic>> _calculateEvents(List<List<dynamic>> data) {
    Map<DateTime, List<dynamic>> eventMap = {};

    if (data.isEmpty) {
      print("No data to process.");
      return eventMap;
    }

    for (var event in data) {
      try {
        // Skip events with invalid or missing dates
        if (event.length < 3 || event[2] == null || event[2].isEmpty) {
          print("Skipping event with invalid date or missing fields: $event");
          continue;
        }

        // Parse start date with format 'dd/MM/yyyy'
        DateTime startDate = DateFormat('dd/MM/yyyy').parse(event[2]);

        // If end date is invalid or empty, assume it's a one-day event
        DateTime endDate = (event.length > 3 && event[3].isNotEmpty)
            ? DateFormat('dd/MM/yyyy').parse(event[3])
            : startDate;

        for (DateTime date = startDate;
            date.isBefore(endDate.add(Duration(days: 1)));
            date = date.add(Duration(days: 1))) {
          final dateKey = DateTime(date.year, date.month, date.day);

          if (eventMap.containsKey(dateKey)) {
            eventMap[dateKey]?.add(event);
          } else {
            eventMap[dateKey] = [event];
          }
        }
      } catch (e) {
        print("Error processing event $event: $e");
      }
    }

    return eventMap;
  }

  // Update _loadCachedData to calculate events once data is loaded from cache
  Future<void> _loadCachedData(String?storage) async {
    final cachedData = storage;

    if (cachedData != null && cachedData.isNotEmpty) {
      final List<dynamic> cachedValues = json.decode(cachedData);
      setState(() {
        _data = cachedValues.cast<List<dynamic>>();
      });

      // Load events after setting cached data
      setState(() {
        events = _calculateEvents(_data);
      });
    } else {
      final cachedDataLocal = await getFromSharedPreferences('slideLocalData');
      if (cachedDataLocal != null) {
        final List<dynamic> cachedValues = json.decode(cachedDataLocal);
        setState(() {
          _data = cachedValues.cast<List<dynamic>>();
        });

        // Load events after setting stored data
        setState(() {
          events = _calculateEvents(_data);
        });
      }
    }
  }

  void _loadEvents() {
    Map<DateTime, List<dynamic>> eventMap = {};
    if (_data.isEmpty) {
      print("No data available for events");
      return;
    }

    for (var event in _data.skip(1)) {
      try {
        // Parse start and end dates
        DateTime startDate = DateFormat('dd/MM/yyyy').parse(event[2]);
        DateTime endDate = event[3].isEmpty
            ? startDate // If endDate is empty, assume it's a one-day event
            : DateFormat('dd/MM/yyyy').parse(event[3]);

        print("Processing event: ${event[1]} from $startDate to $endDate");

        // Iterate through the range of dates from start to end
        for (var date = startDate;
            date.isBefore(endDate.add(Duration(days: 1)));
            date = date.add(Duration(days: 1))) {
          if (eventMap.containsKey(date)) {
            eventMap[date]?.add(event);
          } else {
            eventMap[date] = [event];
          }
        }
      } catch (e) {
        print('Error parsing event dates: $e');
      }
    }

    // Assign the loaded events to the 'events' member variable, and update the UI.
    setState(() {
      events = eventMap;
    });
  }

  List<dynamic> _getEventsForDay(DateTime day) {
    // Match events using the year's month/day (ignoring the time portion).
    final dateWithoutTime = DateTime(day.year, day.month, day.day);

    if (events.containsKey(dateWithoutTime)) {
      return events[dateWithoutTime] ?? [];
    } else {
      return [];
    }
  }

  DateTime? _latestEventDay(DateTime now) {
    DateTime? latest = DateTime.now(); // Fallback to current day

    // Go through the events and find the closest past or future event
    for (DateTime date in events.keys) {
      if (latest == null ||
          date.isAfter(latest) && date.isBefore(now.add(Duration(days: 1)))) {
        latest = date;
      }
    }

    // Return the latest event date; if no events, fallback to current
    return now;
  }

  // Function to Render Event Details which include handling phone numbers

  Widget _renderEventDetails(String details) {
    // Regular expression to detect phone numbers (basic pattern)
    final phonePattern = RegExp(
      r'(\+?\d{1,4}[\s-]?)?(\(?\d{1,3}\)?[\s-]?)?[\d\s-]{8,15}\d', // Updated to match 8-15 digits
    );

    // Search for phone numbers in the event details
    final phoneNumbers = phonePattern
        .allMatches(details)
        .map((match) => match.group(0))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show the full details text
        Text(details),

        SizedBox(height: 5),

        if (phoneNumbers.isNotEmpty) Text('ເບີໂທ:'),

        // If phone numbers are found, list them and add copy/WhatsApp functionality
        if (phoneNumbers.isNotEmpty)
          ...phoneNumbers.map(
            (phoneNumber) {
              // Clean the phone number (remove non-numeric characters except '+')
              String cleanPhoneNumber =
                  phoneNumber!.replaceAll(RegExp(r'[^\d+]'), '');

              // Check if the phone number has at least 8 digits
              if (cleanPhoneNumber.length >= 8) {
                // Replace '020' at the start of the phone number with '+85620'
                if (cleanPhoneNumber.startsWith('020')) {
                  cleanPhoneNumber =
                      cleanPhoneNumber.replaceFirst('020', '+85620');
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(cleanPhoneNumber),

                    // Copy to clipboard icon
                    IconButton(
                      icon: Icon(Icons.copy),
                      onPressed: () {
                        // Copy the phone number to the clipboard
                        Clipboard.setData(
                            ClipboardData(text: cleanPhoneNumber));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content:
                              Text('$cleanPhoneNumber copied to clipboard'),
                        ));
                      },
                    ),

                    // WhatsApp icon
                    IconButton(
                      icon: Icon(Icons.phone),
                      onPressed: () async {
                        final whatsappUrl = 'https://wa.me/$cleanPhoneNumber';
                        if (await canLaunch(whatsappUrl)) {
                          await launch(whatsappUrl);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Could not open WhatsApp for $cleanPhoneNumber'),
                          ));
                        }
                      },
                    ),
                  ],
                );
              } else {
                return Container(); // Do not show anything if the number is too short
              }
            },
          ),
      ],
    );
  }

// Helper function to check if the event is before or ongoing from the current date
  bool isBeforeEndDate(String startDateStr, String endDateStr) {
    DateTime currentDate = DateTime.now();
    DateFormat dateFormat = DateFormat('dd/MM/yyyy');

    try {
      DateTime endDate =
          dateFormat.parse(endDateStr.isNotEmpty ? endDateStr : startDateStr);

      // Show the image if current date is before or on the end date
      return currentDate.isBefore(endDate
          .add(Duration(days: 1))); // Extend end date by 1 day for inclusivity

    } catch (e) {
      print('Error parsing date: $e');
      return false; // If there's an error parsing, consider it inactive/expired.
    }
  }

//  filter both _data and imageUrls to only include the ones where the event is active based on start and end dates.
  List<String> getActiveImages(List<List<dynamic>> data, List<String> images) {
    List<String> activeImages = [];

    // Ensure that data and image URLs are aligned
    if (data.length != images.length) {
      print('Data length and image URLs length mismatch');
      return activeImages; // return empty if there is a mismatch
    }

    // Iterate over both data and imageUrls and filter based on active status
    for (int i = 0; i < data.length; i++) {
      final event = data[i];

      // Get start and end dates from event data
      String startDateStr =
          event[2]; // Adjust index based on actual event structure
      String endDateStr =
          event[3]; // Adjust index based on actual event structure

      // Check if the event is still relevant (i.e., not expired based on end date)
      if (isBeforeEndDate(startDateStr, endDateStr)) {
        activeImages.add(images[
            i]); // Include the image if the event is valid (future or current)
      }
    }

    return activeImages;
  }

  @override
  Widget build(BuildContext context) {
    final isTabletOrDesktop = MediaQuery.of(context).size.width > 600;
    final isMobile = !isTabletOrDesktop;

    final deviceWidth = MediaQuery.of(context).size.width;
    final deviceHeight = MediaQuery.of(context).size.height;

    // Manage width and height for different screens
    double imageWidth;
    double imageHeight;

    if (deviceWidth < 600) {
      // Mobile
      imageWidth = deviceWidth * 0.9;
      imageHeight = deviceHeight * 0.5;
    } else if (deviceWidth >= 600 && deviceWidth < 1024) {
      // Tablet
      imageWidth = deviceWidth * 0.8;
      imageHeight = deviceHeight * 0.8;
    } else {
      // Desktop
      imageWidth = deviceWidth * 0.6;
      imageHeight = deviceHeight * 0.8;
    }

    // Get the list of images where the event has not ended
    // List<String> activeImageUrls = getActiveImages(_data, imageUrls);

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
          'ປະຕິທິນທັມ',
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _shareCalendar,
          ),
          const SizedBox(width: 20),
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

      // Make the entire page scrollable using SingleChildScrollView
      body: _data.isEmpty
          ? RandomImagePage()
          : SingleChildScrollView(
              controller: _scrollController, // Attach controller
              physics: BouncingScrollPhysics(), // Enable touch gestures
              child: Column(
                children: [
                  // Image Slider
                  // SizedBox(
                  //   height: isTabletOrDesktop ? 400 : 220,
                  //   child: activeImageUrls.isEmpty // No active images
                  //       ? Center(
                  //           child: Text('No upcoming or current events'),
                  //         )
                  //       : PageView.builder(
                  //           controller: _pageController,
                  //           itemCount: activeImageUrls.length,
                  //           itemBuilder: (context, index) {
                  //             return GestureDetector(
                  //               onTap: () {
                  //                 // Open full-screen image viewer when the image is tapped
                  //                 Navigator.of(context).push(
                  //                   MaterialPageRoute(
                  //                     builder: (context) =>
                  //                         FullScreenImagePageView(
                  //                             imageUrls: activeImageUrls),
                  //                   ),
                  //                 );
                  //               },
                  //               child: Image.network(
                  //                 activeImageUrls[index] == ''
                  //                     ? 'assets/wisdom.jpg'
                  //                     : activeImageUrls[index],
                  //                 fit: BoxFit
                  //                     .contain, // To make sure the image fits within the box
                  //                 loadingBuilder: (BuildContext context,
                  //                     Widget child,
                  //                     ImageChunkEvent? loadingProgress) {
                  //                   if (loadingProgress == null) {
                  //                     return child; // Return the image when it's fully loaded
                  //                   } else {
                  //                     // Display a loading spinner while the image is loading
                  //                     return Center(
                  //                       child: CircularProgressIndicator(
                  //                         value: loadingProgress
                  //                                     .expectedTotalBytes !=
                  //                                 null
                  //                             ? loadingProgress
                  //                                     .cumulativeBytesLoaded /
                  //                                 loadingProgress
                  //                                     .expectedTotalBytes!
                  //                             : null, // Indeterminate progress if total bytes are unknown
                  //                       ),
                  //                     );
                  //                   }
                  //                 },
                  //                 errorBuilder: (BuildContext context,
                  //                     Object error, StackTrace? stackTrace) {
                  //                   // Fallback/default image if there is an error loading the network image
                  //                   return Image.asset(
                  //                     'assets/wisdom.jpg', // Path to your local default image
                  //                     fit: BoxFit
                  //                         .contain, // Same fitting for consistency
                  //                   );
                  //                 },
                  //               ),
                  //             );
                  //           },
                  //         ),
                  // ),

                  SizedBox(height: 10),

                  // TableCalendar with Events
                  TableCalendar(
                    focusedDay:
                        _focusedDay, // automatically updated to latest event
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    firstDay: DateTime.utc(2010, 1, 1),
                    lastDay: DateTime.utc(3000, 1, 1),
                    selectedDayPredicate: (day) {
                      return isSameDay(_selectedDay, day);
                    },
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                    },
                    eventLoader:
                        _getEventsForDay, // Correctly load events for the selected day
                    calendarStyle: const CalendarStyle(
                      selectedDecoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      markersMaxCount: 1000000,
                      // Here you can customize the markers' color and shape
                      markerDecoration: BoxDecoration(
                        color: Colors
                            .brown, // Change this to whatever color you want
                        shape: BoxShape
                            .circle, // Change the shape if needed (e.g., BoxShape.rectangle)
                      ),
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                    ),
                  ),

                  SizedBox(height: 10),

                  // Event List Container
                  Container(
                    height: isMobile ? deviceHeight * 0.4 : deviceHeight * 0.7,
                    child: _selectedDay == null ||
                            _getEventsForDay(_selectedDay!).isEmpty
                        ? Center(child: Text('No events for this day'))
                        : ListView.builder(
                            itemCount: _getEventsForDay(_selectedDay!).length,
                            itemBuilder: (context, index) {
                              final event =
                                  _getEventsForDay(_selectedDay!)[index];

                              return LayoutBuilder(
                                builder: (context, constraints) {
                                  // Determine device width
                                  final deviceWidth =
                                      MediaQuery.of(context).size.width;

                                  final bool isTablet =
                                      deviceWidth >= 600 && deviceWidth < 1024;
                                  final bool isDesktop = deviceWidth >= 1024;

                                  return ListTile(
                                    leading:
                                        event[0] != null && event[0].isNotEmpty
                                            ? Image.network(event[0])
                                            : Icon(Icons.event,
                                                size: isDesktop
                                                    ? 60
                                                    : isTablet
                                                        ? 45
                                                        : 30),
                                    title: Text(
                                      event[1], // Event title
                                      style: TextStyle(
                                        fontSize: isDesktop
                                            ? 20
                                            : isTablet
                                                ? 16
                                                : 14, // Adjust font size based on device type
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Display start and end date range
                                        Text(
                                          'Start: ${event[2]} - End: ${event[3]}',
                                          style: TextStyle(
                                            fontSize: isDesktop
                                                ? 16
                                                : isTablet
                                                    ? 14
                                                    : 12,
                                          ),
                                        ),

                                        // Detect phone number in event details and allow copying to clipboard.
                                      ],
                                    ),
                                    onTap: () {
                                      // Popup dialog to show more details including location link
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(event[1]),
                                          content: SingleChildScrollView(
                                            scrollDirection: Axis
                                                .vertical, // Enable vertical scrolling inside
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Display Event Image if it exists
                                                if (event[0] != null &&
                                                    event[0].isNotEmpty)
                                                  Center(
                                                    child: Container(
                                                      constraints:
                                                          BoxConstraints(
                                                        maxWidth: imageWidth,
                                                        maxHeight: imageHeight,
                                                      ),
                                                      child: InteractiveViewer(
                                                        minScale:
                                                            0.5, // Minimum zoom-out scale (reduce size by 50%)
                                                        maxScale:
                                                            4.0, // Maximum zoom-in scale (increase size by 4x)

                                                        child: GestureDetector(
                                                          onTap: () {
                                                            // Open full-screen image viewer when the image is tapped
                                                            Navigator.of(
                                                                    context)
                                                                .push(
                                                              MaterialPageRoute(
                                                                builder: (context) =>
                                                                    FullScreenImageView(
                                                                        imageUrl:
                                                                            event[0]),
                                                              ),
                                                            );
                                                          },
                                                          child: Image.network(
                                                            event[0],
                                                            width: constraints
                                                                .maxWidth,
                                                            fit: BoxFit.contain,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),

                                                // Vertical spacing
                                                SizedBox(height: 10),

                                                // Display Event Description and try to Render Phone Numbers
                                                if (event[4] != null &&
                                                    event[4].isNotEmpty)
                                                  Column(
                                                    children: [
                                                      _renderEventDetails(
                                                          event[4]),
                                                    ],
                                                  )
                                                else
                                                  Text(
                                                    'No additional details available',
                                                    textAlign: TextAlign.left,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                      color: Colors.grey,
                                                    ),
                                                  ),

                                                // Vertical spacing
                                                SizedBox(height: 10),

                                                // Display Location Link if it exists
                                                if (event[6] != '/')
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    children: [
                                                      // Display a clickable static Google Map Image
                                                      Center(
                                                        child: InkWell(
                                                          onTap: () async {
                                                            // Open Google Maps with the event location when the map is clicked using url_lunch
                                                            if (await canLaunch(
                                                                event[6])) {
                                                              await launch(
                                                                  event[6]);
                                                            }
                                                          },
                                                          child: Image.network(
                                                            // google maps image default
                                                            'https://i.ibb.co/HBdGt57/Screenshot-2024-09-14-at-22-23-42.jpg',
                                                            fit: BoxFit.contain,
                                                            width: constraints
                                                                .maxWidth,
                                                            errorBuilder: (context,
                                                                    error,
                                                                    stackTrace) =>
                                                                Text(
                                                              'Map not available. Click the link below for location.',
                                                              style: TextStyle(
                                                                color:
                                                                    Colors.red,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(height: 10),

                                                      // Location description text with a clickable link
                                                      Column(
                                                        children: [
                                                          if (event[6] != '/')
                                                            InkWell(
                                                              onTap: () async {
                                                                if (await canLaunch(
                                                                    event[6])) {
                                                                  await launch(
                                                                      event[6]);
                                                                }
                                                              },
                                                              child: // Location description text with a clickable link
                                                                  InkWell(
                                                                onTap:
                                                                    () async {
                                                                  if (await canLaunch(
                                                                      event[
                                                                          6])) {
                                                                    await launch(
                                                                        event[
                                                                            6]);
                                                                  }
                                                                },
                                                                child: Text(
                                                                  'ສະຖານທີ່ 1: ${event[6]}', // Event Location
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                        .blue,
                                                                    decoration:
                                                                        TextDecoration
                                                                            .underline,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),

                                                          SizedBox(height: 10),

                                                          // Location 2
                                                          if (event[7] != '/')
                                                            InkWell(
                                                              onTap: () async {
                                                                if (await canLaunch(
                                                                    event[7])) {
                                                                  await launch(
                                                                      event[7]);
                                                                }
                                                              },
                                                              child: // Location description text with a clickable link
                                                                  InkWell(
                                                                onTap:
                                                                    () async {
                                                                  if (await canLaunch(
                                                                      event[
                                                                          7])) {
                                                                    await launch(
                                                                        event[
                                                                            7]);
                                                                  }
                                                                },
                                                                child: Text(
                                                                  'ສະຖານທີ່ 2: ${event[7]}', // Event Location
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                        .blue,
                                                                    decoration:
                                                                        TextDecoration
                                                                            .underline,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),

                                                          SizedBox(height: 10),

                                                          // Location 3
                                                          if (event[8] != '/')
                                                            InkWell(
                                                              onTap: () async {
                                                                if (await canLaunch(
                                                                    event[8])) {
                                                                  await launch(
                                                                      event[8]);
                                                                }
                                                              },
                                                              child: // Location description text with a clickable link
                                                                  InkWell(
                                                                onTap:
                                                                    () async {
                                                                  if (await canLaunch(
                                                                      event[
                                                                          8])) {
                                                                    await launch(
                                                                        event[
                                                                            8]);
                                                                  }
                                                                },
                                                                child: Text(
                                                                  'ສະຖານທີ່ 3: ${event[8]}', // Event Location
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                        .blue,
                                                                    decoration:
                                                                        TextDecoration
                                                                            .underline,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),

                                                          SizedBox(height: 10),

                                                          // Location 4
                                                          if (event[9] != '/')
                                                            InkWell(
                                                              onTap: () async {
                                                                if (await canLaunch(
                                                                    event[9])) {
                                                                  await launch(
                                                                      event[9]);
                                                                }
                                                              },
                                                              child: // Location description text with a clickable link
                                                                  InkWell(
                                                                onTap:
                                                                    () async {
                                                                  if (await canLaunch(
                                                                      event[
                                                                          9])) {
                                                                    await launch(
                                                                        event[
                                                                            9]);
                                                                  }
                                                                },
                                                                child: Text(
                                                                  'ສະຖານທີ່ 4: ${event[9]}', // Event Location
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                        .blue,
                                                                    decoration:
                                                                        TextDecoration
                                                                            .underline,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),

                                                          SizedBox(height: 10),

                                                          // Social Page
                                                          if (event[5] != '/')
                                                            InkWell(
                                                              onTap: () async {
                                                                if (await canLaunch(
                                                                    event[5])) {
                                                                  await launch(
                                                                      event[5]);
                                                                }
                                                              },
                                                              child: // Location description text with a clickable link
                                                                  InkWell(
                                                                onTap:
                                                                    () async {
                                                                  if (await canLaunch(
                                                                      event[
                                                                          5])) {
                                                                    await launch(
                                                                        event[
                                                                            5]);
                                                                  }
                                                                },
                                                                child: Text(
                                                                  'Social Page: ${event[5]}', // Event Location
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                        .blue,
                                                                    decoration:
                                                                        TextDecoration
                                                                            .underline,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                          ),
                                          actions: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment
                                                  .spaceBetween, // Justify between
                                              children: [
                                                // Close Button
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: Text('Close'),
                                                ),

                                                // Share Icon Button
                                                IconButton(
                                                  icon: Icon(Icons.share),
                                                  onPressed: () {
                                                    // Action to share both image and text content if the image exists
                                                    if (event[0] != null &&
                                                        event[0].isNotEmpty) {
                                                      // Share image and description when event[0] is available
                                                      final url = 'https://buddhaword.free.nf/calendar';
                                                      Share.share(
                                                        '${event[1]}\n\n Poster: ${event[0]}\n\n ລາຍລະອຽດ: ${event[4]}\n\n' +
                                                            (event[6] != '/'
                                                                ? 'ສະຖານທີ່ 1: ${event[6]}\n\n'
                                                                : '') +
                                                            (event[7] != '/'
                                                                ? 'ສະຖານທີ່ 2: ${event[7]}\n\n'
                                                                : '') +
                                                            (event[8] != '/'
                                                                ? 'ສະຖານທີ່ 3: ${event[8]}\n\n'
                                                                : '') +
                                                            (event[9] != '/'
                                                                ? 'ສະຖານທີ່ 4: ${event[9]}\n\n'
                                                                : '') +
                                                            (event[5] != '/'
                                                                ? 'Social Page: ${event[5]}\n\n'
                                                                : '') +
                                                            '\nເບິ່ງຕາຕະລາງທັງໝົດ: $url',
                                                      );
                                                    } else {
                                                      // Share only the text description when no image is available
                                                      Share.share(
                                                        'Check out this event:\n\nDescription: ${event[4].isNotEmpty ? event[4] : 'No details available.'}',
                                                        subject:
                                                            'Event Details',
                                                      );
                                                    }
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
      // Floating action button to scroll down by tapping
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleScrollDirection, // Change scroll direction on press
        backgroundColor: Colors.transparent,
        child: Icon(
          _isScrollingDown ? Icons.arrow_upward : Icons.arrow_downward,
          color: Colors.white,
        ),
      ),
    );
  }
}

class FullScreenImagePageView extends StatefulWidget {
  final List<String> imageUrls; // List of image URLs

  const FullScreenImagePageView({required this.imageUrls, super.key});

  @override
  _FullScreenImagePageViewState createState() =>
      _FullScreenImagePageViewState();
}

class _FullScreenImagePageViewState extends State<FullScreenImagePageView> {
  final TransformationController _transformationController =
      TransformationController();
  static const double _minScale = 0.5;
  static const double _maxScale = 4.0;
  static const double _doubleTapZoomScale = 2.0;

  @override
  void initState() {
    super.initState();
    // Set initial transformation scale to 1.0
    _transformationController.value = Matrix4.identity();
  }

  void _handleDoubleTap() {
    setState(() {
      final currentScale = _transformationController.value.getMaxScaleOnAxis();
      if (currentScale > 1.0) {
        _transformationController.value = Matrix4.identity();
      } else {
        _transformationController.value = Matrix4.identity()
          ..scale(_doubleTapZoomScale);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PageView.builder(
        itemCount: widget.imageUrls.length,
        itemBuilder: (context, index) {
          final imageUrl = widget.imageUrls[index];

          return GestureDetector(
            onDoubleTap: _handleDoubleTap,
            child: Center(
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: _minScale,
                maxScale: _maxScale,
                child: Image.network(
                  imageUrl.isEmpty ? 'assets/wisdom.jpg' : imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (BuildContext context, Widget child,
                      ImageChunkEvent? loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    } else {
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    }
                  },
                  errorBuilder: (BuildContext context, Object error,
                      StackTrace? stackTrace) {
                    return Image.asset(
                      'assets/wisdom.jpg',
                      fit: BoxFit.contain,
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class FullScreenImageView extends StatefulWidget {
  final String imageUrl;

  const FullScreenImageView({required this.imageUrl, super.key});

  @override
  _FullScreenImageViewState createState() => _FullScreenImageViewState();
}

class _FullScreenImageViewState extends State<FullScreenImageView> {
  final TransformationController _transformationController =
      TransformationController();
  static const double _minScale = 0.5;
  static const double _maxScale = 4.0;
  static const double _doubleTapZoomScale = 2.0;

  @override
  void initState() {
    super.initState();
    // Set initial transformation scale to 1.0
    _transformationController.value = Matrix4.identity();
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.0) {
      _transformationController.value = Matrix4.identity();
    } else {
      _transformationController.value = Matrix4.identity()
        ..scale(_doubleTapZoomScale);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: GestureDetector(
        onDoubleTap: _handleDoubleTap,
        child: Center(
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: _minScale,
            maxScale: _maxScale,
            child: Image.network(
              widget.imageUrl.isEmpty ? 'assets/wisdom.jpg' : widget.imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (BuildContext context, Widget child,
                  ImageChunkEvent? loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                } else {
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                }
              },
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stackTrace) {
                return Image.asset(
                  'assets/wisdom.jpg',
                  fit: BoxFit.contain,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
