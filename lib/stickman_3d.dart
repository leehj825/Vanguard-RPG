import 'dart:ui';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:stickman_3d/stickman_3d.dart';

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
        // FIXED: Handle 'clips' as both List (new format) and Map (legacy format)
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

  // FIXED: Added vx, vy parameters to support procedural animation calculation
  void update(double dt, [double vx = 0, double vy = 0]) {
    _controller.update(dt, vx, vy);
  }

  void render(Canvas canvas, Vector2 position, double height) {
    final painter = StickmanPainter(
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
    painter.paint(canvas, Size(100, height));
    canvas.restore();
  }
}
