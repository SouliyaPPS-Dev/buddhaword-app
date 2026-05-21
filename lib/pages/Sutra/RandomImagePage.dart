// ignore_for_file: file_names, prefer_const_constructors, library_private_types_in_public_api, use_build_context_synchronously

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class RandomImagePage extends StatefulWidget {
  // Generate a random key for each instance to ensure it rebuilds
  final Key randomKey = ValueKey(Random().nextInt(10000));

  RandomImagePage({super.key});

  @override
  _RandomImagePageState createState() => _RandomImagePageState();
}

class _RandomImagePageState extends State<RandomImagePage> {
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (results.contains(ConnectivityResult.none)) {
        // No internet connection, navigate to MyHomePage
        context.go('/');
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            double screenWidth = constraints.maxWidth;
            double screenHeight = constraints.maxHeight;

            // Determine if the device is a desktop
            bool isDesktop =
                screenWidth >= 1024; // Adjust this breakpoint as needed

            // Lists of image paths for each device type
            List<String> desktopImages = [
              'assets/ເຫັນທຳ/loading_desktop_tablet.jpg',
            ];

            List<String> tabletImages = ['assets/ເຫັນທຳ/loading_mobile.jpg'];

            List<String> mobileImages = ['assets/ເຫັນທຳ/loading_mobile.jpg'];

            // Select the list of images based on the screen size
            List<String> selectedImages;
            if (isDesktop) {
              selectedImages = desktopImages;
            } else if (screenWidth >= 600 || screenHeight <= 1366) {
              selectedImages = tabletImages;
            } else {
              selectedImages = mobileImages;
            }

            // Choose a random image from the selected list
            String imagePath =
                selectedImages[Random().nextInt(selectedImages.length)];

            // Set image size to match screen dimensions
            double imageWidth = screenWidth;
            double imageHeight = screenHeight;

            return Stack(
              children: [
                Image.asset(
                  imagePath,
                  width: imageWidth,
                  height: imageHeight,
                  fit: BoxFit
                      .cover, // Ensures the image covers the entire screen
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
