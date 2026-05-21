// ignore_for_file: deprecated_member_use, use_key_in_widget_constructors, file_names, prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../layouts/NavigationDrawer.dart' as custom_nav;
import '../../themes/ThemeProvider.dart';

class ContactInfoPage extends StatelessWidget {
  const ContactInfoPage({Key? key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/buddha_nature_logo.png', height: 44),
            const SizedBox(width: 10),
            const Text(
              'ຂໍ້​ມູນ​ຕິດ​ຕໍ່',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () {
            context.go('/');
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
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center, // Changed alignment
            children: [
              const SizedBox(height: 10),
              Center(
                child: Image.asset('assets/buddha_nature_logo.png', width: 220),
              ),
              const SizedBox(height: 20),
              Center(
                child: const Text(
                  'ແອັບນີ້ແມ່ນແອັບຄຳສອນພຸດທະ, ສ້າງຂື້ນເພື່ອເຜີຍແຜ່ໃຫ້ພວກເຮົາທັງຫຼາຍໄດ້ສຶກສາ ແລະ ປະຕິບັດຕາມ, ດັ່ງທີ່ພຣະຕະຖາຄົດກ່າວວ່າ "ທຳມະຍິ່ງເປີດເຜີຍຍິ່ງຮຸ່ງເຮືອງ" ເມື່ອໄດ້ສຶກສາ ແລະ ປະຕິບັດຕາມ ຈົນເຫັນທຳມະຊາດຕາມຄວາມເປັນຈິງ ກໍຈະຫຼຸດພົ້ນຈາກຄວາມທຸກທັງປວງ. "ທຳກໍດີ ວິໄນກໍດີ ທີ່ເຮົາສະແດງແລ້ວ ບັນຍັດໄວ້ດີແລ້ວ ທຳ ແລະ ວິໄນນັ້ນ ຈະເປັນສາດສະດາແທນຕໍ່ໄປ"',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20, // Adjusted font size
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Facebook pages as clickable logos
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl('https://web.facebook.com/watdanpra');
                    },
                    child: Image.asset(
                      'assets/buddha_nature_logo.png',
                      fit: BoxFit.cover,
                      width: 80,
                      height: 80,
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://web.facebook.com/dhammakonnon',
                      );
                    },
                    child: Image.asset(
                      'assets/dhammakonnon.png',
                      fit: BoxFit.cover,
                      width: 80,
                      height: 80,
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://www.facebook.com/Sumittosumittabounsong',
                      );
                    },
                    child: Image.asset(
                      'assets/ຮຸ່ງເເສງເເຫ່ງທັມ.png',
                      fit: BoxFit.cover,
                      width: 80,
                      height: 80,
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://web.facebook.com/watpavimokkhavanaram.la',
                      );
                    },
                    child: Image.asset(
                      'assets/tathakod_logo.png',
                      fit: BoxFit.cover,
                      width: 80,
                      height: 80,
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://www.facebook.com/dhammalife.laos',
                      );
                    },
                    child: Image.asset(
                      'assets/ພຸທທະວົງສ໌.png',
                      fit: BoxFit.cover,
                      width: 80,
                      height: 80,
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://www.facebook.com/profile.php?id=100091798479187',
                      );
                    },
                    child: Image.asset(
                      'assets/ວິນັຍສຸຄົຕ.png',
                      fit: BoxFit.cover,
                      width: 80,
                      height: 80,
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://www.facebook.com/phouhuck.phousamnieng.7',
                      );
                    },
                    child: Image.asset(
                      'assets/ວັດບ້ານນາຈິກ.png',
                      fit: BoxFit.cover,
                      width: 80,
                      height: 80,
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://web.facebook.com/profile.php?id=100077638042542',
                      );
                    },
                    child: Image.asset(
                      'assets/buddha_nature_logo_old.png',
                      fit: BoxFit.cover,
                      width: 80,
                      height: 80,
                    ),
                  ),
                  // Add more logos here if needed
                ],
              ),
              const SizedBox(height: 30),
              const Text(
                'ຕິດ​ຕໍ່',
                style: TextStyle(
                  fontSize: 24, // Increased font size
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.phone, color: Colors.brown),
                    onPressed: () async {
                      await launchWhatsApp('+8562056118850');
                    },
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                        const ClipboardData(text: '+8562056118850'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Phone number copied to clipboard'),
                        ),
                      );
                    },
                    child: const Text(
                      '+8562056118850',
                      style: TextStyle(fontSize: 20, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.phone, color: Colors.brown),
                    onPressed: () async {
                      await launchWhatsApp('+8562078287509');
                    },
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                        const ClipboardData(text: '+8562078287509'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Phone number copied to clipboard'),
                        ),
                      );
                    },
                    child: const Text(
                      '+8562078287509',
                      style: TextStyle(fontSize: 20, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.phone, color: Colors.brown),
                    onPressed: () async {
                      await launchWhatsApp('+8562077801610');
                    },
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                        const ClipboardData(text: '+8562077801610'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Phone number copied to clipboard'),
                        ),
                      );
                    },
                    child: const Text(
                      '+8562077801610',
                      style: TextStyle(fontSize: 20, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
              // const SizedBox(height: 10),
              // Row(
              //   mainAxisAlignment: MainAxisAlignment.center,
              //   children: [
              //     IconButton(
              //       icon: const Icon(Icons.email, color: Colors.brown),
              //       onPressed: () async {
              //         await launchEmail('souliyappsdev@gmail.com');
              //       },
              //     ),
              //     const SizedBox(width: 10),
              //     GestureDetector(
              //       onTap: () {
              //         Clipboard.setData(
              //             const ClipboardData(text: 'souliyappsdev@gmail.com'));
              //         ScaffoldMessenger.of(context).showSnackBar(
              //           const SnackBar(
              //             content: Text('Email copied to clipboard'),
              //           ),
              //         );
              //       },
              //       child: const Text(
              //         'souliyappsdev@gmail.com',
              //         style: TextStyle(fontSize: 20, letterSpacing: 0.5),
              //       ),
              //     ),
              //   ],
              // ),
              // const SizedBox(height: 10),
              // Row(
              //   mainAxisAlignment: MainAxisAlignment.center,
              //   children: [
              //     IconButton(
              //       icon: const Icon(Icons.email, color: Colors.brown),
              //       onPressed: () async {
              //         await launchEmail('Katiya921@gmail.com');
              //       },
              //     ),
              //     const SizedBox(width: 10),
              //     GestureDetector(
              //       onTap: () {
              //         Clipboard.setData(
              //           const ClipboardData(text: 'Katiya921@gmail.com'),
              //         );
              //         ScaffoldMessenger.of(context).showSnackBar(
              //           const SnackBar(
              //             content: Text('Email copied to clipboard'),
              //           ),
              //         );
              //       },
              //       child: const Text(
              //         'Katiya921@gmail.com',
              //         style: TextStyle(fontSize: 20, letterSpacing: 0.5),
              //       ),
              //     ),
              //   ],
              // ),
              const SizedBox(height: 20),
              const Text(
                'Follow Us',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl('https://web.facebook.com/watdanpra');
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.facebook, color: Colors.blue),
                        SizedBox(width: 10),
                        Text(
                          'ວັດປ່າດານພຣະ',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.blue,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://web.facebook.com/dhammakonnon',
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.facebook, color: Colors.blue),
                        SizedBox(width: 10),
                        Text(
                          'ທັມມະກ່ອນນອນ',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.blue,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://www.facebook.com/Sumittosumittabounsong',
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.facebook, color: Colors.blue),
                        SizedBox(width: 10),
                        Text(
                          'ຮຸ່ງເເສງເເຫ່ງທັມ',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.blue,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://web.facebook.com/watpavimokkhavanaram.la',
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.facebook, color: Colors.blue),
                        SizedBox(width: 10),
                        Text(
                          'ຕະຖາຄົຕພາສິຕ',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.blue,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://www.facebook.com/dhammalife.laos',
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.facebook, color: Colors.blue),
                        SizedBox(width: 10),
                        Text(
                          'ພຸທທະວົງສ໌',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.blue,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://www.facebook.com/profile.php?id=100091798479187',
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.facebook, color: Colors.blue),
                        SizedBox(width: 10),
                        Text(
                          'ວິນັຍສຸຄົຕ',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.blue,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://www.facebook.com/phouhuck.phousamnieng.7',
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.facebook, color: Colors.blue),
                        SizedBox(width: 10),
                        Text(
                          'ວັດບ້ານນາຈິກ',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.blue,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      await launchWebUrl(
                        'https://www.facebook.com/profile.php?id=100077638042542',
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.facebook, color: Colors.blue),
                        SizedBox(width: 10),
                        Text(
                          'ຄຳສອນພຣະພຸດທະເຈົ້າ',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.blue,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> launchWebUrl(String url) async {
  if (await canLaunch(url)) {
    await launch(url, forceSafariVC: false, forceWebView: false);
  } else {
    throw 'Could not launch $url';
  }
}

Future<void> launchWhatsApp(String phoneNumber) async {
  String url = "https://wa.me/$phoneNumber";
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw 'Could not launch $url';
  }
}

Future<void> launchEmail(String email) async {
  final Uri emailLaunchUri = Uri(scheme: 'mailto', path: email);
  if (await canLaunch(emailLaunchUri.toString())) {
    await launch(emailLaunchUri.toString());
  } else {
    throw 'Could not launch email';
  }
}
