import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'core/copy.dart';
import 'core/sound.dart';
import 'core/theme.dart';
import 'screens/onboarding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Future.wait([collection.load(), profile.load(), copy.load(), sound.load()]);
  runApp(const TerrakinApp());
}

class TerrakinApp extends StatelessWidget {
  const TerrakinApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Terrakin',
        debugShowCheckedModeBanner: false,
        theme: TK.theme(),
        // Passkey sign-in, starter grant, name + character, then GPS.
        home: const RootGate(),
      );
}
