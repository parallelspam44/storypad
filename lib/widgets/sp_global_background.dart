import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:storypad/providers/device_preferences_provider.dart';

class SpGlobalBackground extends StatelessWidget {
  final Widget child;

  const SpGlobalBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<DevicePreferencesProvider>().preferences;

    return Container(
      decoration: BoxDecoration(
        image: prefs.backgroundImagePath != null
            ? DecorationImage(
                image: AssetImage(prefs.backgroundImagePath!),
                fit: BoxFit.cover,
              )
            : null,
        color: prefs.colorSeed ?? Theme.of(context).scaffoldBackgroundColor,
      ),
      child: child,
    );
  }
}