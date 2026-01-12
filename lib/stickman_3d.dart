import 'dart:ui';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show Colors, Paint, PaintingStyle, StrokeCap, Size, Offset, CustomPainter, Color;
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:stickman_3d/stickman_3d.dart';
// Needed to access StickmanNode/StickmanSkeleton if they are exported.
// The package exports them.

// Re-export the package so things like WeaponType are available
export 'package:stickman_3d/stickman_3d.dart';

/// A wrapper around StickmanController to adapt it to the Vanguard Game API.
class StickmanAnimator {
  final StickmanController _controller;
  Color color;
  // Store clips with lowercase keys for case-insensitive lookup
  Map<String, StickmanClip> clips = {};

  StickmanAnimator._(this._controller, this.color);

  /// Async factory to load the animator from an asset path (e.g. .sap file)
  static Future<StickmanAnimator> load(String path) async {
    final controller = StickmanController();
    final animator = StickmanAnimator._(controller, const Color(0xFFFFFFFF));

    try {
      final jsonString = await rootBundle.loadString(path);
      final dynamic json = jsonDecode(jsonString);

      if (json is Map<String, dynamic>) {
        if (json.containsKey('clips')) {
           final dynamic clipsData = json['clips'];

           if (clipsData is List) {
             for (var clip in clipsData) {
               if (clip is Map<String, dynamic> && clip.containsKey('name')) {
                 // Store name as lowercase for easier lookup
                 animator.clips[clip['name'].toString().toLowerCase()] = StickmanClip.fromJson(clip);
               }
             }
           } else if (clipsData is Map<String, dynamic>) {
              for (var key in clipsData.keys) {
                 animator.clips[key.toLowerCase()] = StickmanClip.fromJson(clipsData[key]);
              }
           }
        } else {
           // Try parsing root keys as clip names (fallback)
           json.forEach((key, value) {
              if (key == 'gridz') return;
              if (value is Map<String, dynamic> && value.containsKey('keyframes')) {
                  animator.clips[key.toLowerCase()] = StickmanClip.fromJson(value);
              }
           });
        }
      }
    } catch (e) {
      print("Warning: Failed to load stickman assets from $path: $e");
    }

    return animator;
  }

  void setWeapon(String name) {
    try {
      final type = WeaponType.values.firstWhere(
        (e) => e.toString().split('.').last.toLowerCase() == name.toLowerCase(),
        orElse: () => WeaponType.none
      );
      _controller.weaponType = type;
    } catch (e) {
      _controller.weaponType = WeaponType.none;
    }
  }

  set scale(double value) => _controller.scale = value;

  void play(String name) {
    // Normalize name to lowercase
    final key = name.toLowerCase();

    if (clips.containsKey(key)) {
      if (_controller.activeClip != clips[key]) {
        _controller.activeClip = clips[key];
        _controller.isPlaying = true;
        _controller.setMode(EditorMode.animate);
      }
    } else {
      // Fallback for procedural animations if clip is missing (e.g. 'idle')
      if (key == 'run' || key == 'idle') {
        _controller.setMode(EditorMode.pose);
      }
    }
  }

  bool isPlaying(String name) {
    final key = name.toLowerCase();
    // Check if clip exists and is active.
    // Note: StickmanController logic might not auto-clear activeClip when done if looping is false,
    // but typically isPlaying becomes false?
    // We assume isPlaying is true only while animating.
    return clips.containsKey(key) && _controller.activeClip == clips[key] && _controller.isPlaying;
  }

  void update(double dt, [double vx = 0, double vy = 0]) {
    _controller.update(dt, vx, vy);
  }

  void render(Canvas canvas, v.Vector2 position, double height, double facingDirection) {
    // USE CUSTOM PAINTER TO DISABLE GRID
    final painter = _NoGridStickmanPainter(
      controller: _controller,
      color: color,
      cameraView: CameraView.side,
      viewZoom: 1.0,
      viewPan: Offset.zero,
      cameraHeightOffset: 0,
      viewRotationX: 0,
      viewRotationY: 0,
    );

    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.scale(facingDirection, 1.0);
    // Use Width 0 to ensure centering at the translated position for correct flipping
    painter.paint(canvas, Size(0, height));
    canvas.restore();
  }
}

// Custom Painter that duplicates logic but omits grid
class _NoGridStickmanPainter extends CustomPainter {
  final StickmanController controller;
  final Color color;
  final CameraView cameraView;
  final double viewRotationX;
  final double viewRotationY;
  final double viewZoom;
  final Offset viewPan;
  final double cameraHeightOffset;

  _NoGridStickmanPainter({
    required this.controller,
    this.color = Colors.white,
    this.cameraView = CameraView.free,
    this.viewRotationX = 0.0,
    this.viewRotationY = 0.0,
    this.viewZoom = 1.0,
    this.viewPan = Offset.zero,
    this.cameraHeightOffset = 0.0,
  });

  static Offset project(
      v.Vector3 point,
      Size size,
      CameraView view,
      double rotX,
      double rotY,
      double zoom,
      Offset pan,
      double heightOffset)
  {
    double x = 0;
    double y = 0;

    switch (view) {
      case CameraView.front:
        x = point.x;
        y = point.y;
        break;
      case CameraView.side:
        x = point.z;
        y = point.y;
        break;
      case CameraView.top:
        x = point.x;
        y = point.z;
        break;
      case CameraView.free:
        double x1 = point.x * cos(rotY) - point.z * sin(rotY);
        double z1 = point.x * sin(rotY) + point.z * cos(rotY);
        double y1 = point.y;
        double y2 = y1 * cos(rotX) - z1 * sin(rotX);
        double z2 = y1 * sin(rotX) + z1 * cos(rotX);
        double x2 = x1;
        x = x2;
        y = y2;
        break;
    }

    double sx = x * zoom;
    double sy = y * zoom;
    sy += heightOffset;
    double cx = size.width / 2;
    double cy = size.height / 2;
    return Offset(cx + pan.dx + sx, cy + pan.dy + sy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final skel = controller.skeleton;
    final strokeWidth = skel.strokeWidth * viewZoom * controller.scale;
    final headRadius = skel.headRadius * viewZoom * controller.scale;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()..color = color ..style = PaintingStyle.fill;

    // SKIP DRAW GRID

    Offset toScreen(v.Vector3 vec) => project(
      vec * controller.scale,
      size,
      cameraView,
      viewRotationX,
      viewRotationY,
      viewZoom,
      viewPan,
      cameraHeightOffset
    );

    void drawNode(StickmanNode node) {
      final start = toScreen(node.position);

      if (node.id == 'head') {
        canvas.drawCircle(start, headRadius, fillPaint);
      }

      for (var child in node.children) {
         final end = toScreen(child.position);
         canvas.drawLine(start, end, paint);
         drawNode(child);
      }
    }

    drawNode(skel.root);
  }

  @override
  bool shouldRepaint(covariant _NoGridStickmanPainter oldDelegate) {
    return true;
  }
}
