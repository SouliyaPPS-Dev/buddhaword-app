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
        child: _buildLoadingImage(context),
      ),
    );
  }
}

Widget _buildLoadingImage(BuildContext context) {
  final screenSize = MediaQuery.of(context).size;
  double screenWidth = screenSize.width;
  double screenHeight = screenSize.height;

  bool isDesktop = screenWidth >= 1024;

  String imagePath;
  if (isDesktop) {
    imagePath = 'assets/ເຫັນທຳ/loading_desktop_tablet.jpg';
  } else {
    imagePath = 'assets/ເຫັນທຳ/loading_mobile.jpg';
  }

  return SizedBox(
    width: screenWidth,
    height: screenHeight,
    child: Image.asset(
      imagePath,
      fit: BoxFit.cover,
    ),
  );
}

class LoadingImage extends StatelessWidget {
  const LoadingImage({super.key});

  @override
  Widget build(BuildContext context) {
    return _buildLoadingImage(context);
  }
}
