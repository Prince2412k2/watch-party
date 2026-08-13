import 'package:flutter/material.dart';

import 'texture_playground.dart';

/// A second entry point, for tuning the artwork textures.
///
///     flutter run -d linux -t lib/playground/main.dart
///
/// Same project rather than a separate app on purpose: it loads the same
/// bundled sheets and builds the same [WallRelief] and [TexturedArtwork] the
/// stage does, so a number that looks right here looks the same in the app.
/// A standalone project would need its own copy of the assets, and the copy
/// would drift.
void main() {
  runApp(
    MaterialApp(
      title: 'Texture playground',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const TexturePlayground(),
    ),
  );
}
