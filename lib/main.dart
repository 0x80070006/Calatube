import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/playlist_service.dart';
import 'screens/main_shell.dart';

// Palette Calatube
const kPrimary   = Color(0xFF7B3FE4);
const kSecondary = Color(0xFF3DBDE8);
const kAccent    = Color(0xFFE84393);
const kBg        = Color(0xFF0D0B1A);
const kBgCard    = Color(0xFF16122A);
const kBgSurface = Color(0xFF1E1935);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const CalatubeApp());
}

class CalatubeApp extends StatelessWidget {
  const CalatubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlaylistService()..init()),
      ],
      child: MaterialApp(
        title: 'Calatube',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBg,
          colorScheme: const ColorScheme.dark(
            primary: kPrimary,
            secondary: kSecondary,
            surface: kBgCard,
          ),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        home: const MainShell(),
      ),
    );
  }
}
