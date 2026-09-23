import 'package:flutter/material.dart';

/// The app mark (same artwork as the launcher icon; see tool/logo).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Index',
      image: true,
      child: Image.asset('assets/logo/logo.png', width: size, height: size, filterQuality: FilterQuality.medium),
    );
  }
}
