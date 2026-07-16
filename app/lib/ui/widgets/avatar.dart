/// PhotoAvatar — a circular avatar that shows the stored photo when present,
/// otherwise falls back to the person's initials on a gradient (or an icon when
/// there's no name). Used for the mother and each child, at any size.
library;

import 'dart:io';
import 'package:flutter/material.dart';
import '../theme.dart';

class PhotoAvatar extends StatelessWidget {
  final String? photoPath;
  final String name;
  final double size;
  final Gradient gradient;
  final IconData fallbackIcon;
  final List<BoxShadow>? shadow;

  const PhotoAvatar({
    super.key,
    required this.photoPath,
    required this.name,
    this.size = 40,
    this.gradient = Palette.violetPink,
    this.fallbackIcon = Icons.person,
    this.shadow,
  });

  bool get _hasPhoto {
    final p = photoPath;
    return p != null && p.isNotEmpty && File(p).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPhoto) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: shadow,
          image: DecorationImage(image: FileImage(File(photoPath!)), fit: BoxFit.cover),
        ),
      );
    }
    final initials = _initials(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(gradient: gradient, shape: BoxShape.circle, boxShadow: shadow),
      alignment: Alignment.center,
      child: initials.isEmpty
          ? Icon(fallbackIcon, color: Colors.white, size: size * 0.46)
          : Text(initials,
              style: TextStyle(color: Colors.white, fontSize: size * 0.38, fontWeight: FontWeight.w700)),
    );
  }

  static String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}
