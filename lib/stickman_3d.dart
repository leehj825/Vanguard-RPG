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
  Map<String, StickmanClip> clips = {};

  StickmanAnimator._(this._controller, this.color);

  /// Async factory to load the animator from an asset path (e.g. .sap file)
  static Future<StickmanAnimator> load(String path) async {
    final controller = StickmanController();
    final animator = StickmanAnimator._(controller, const Color(0xFFFFFFFF));

    try {
      final jsonString = await rootBundle.loadString(path);
      // Attempt to parse the .sap file as a JSON map
      final dynamic json = jsonDecode(jsonString);

      if (json is Map<String, dynamic>) {
        if (json.containsKey('clips')) {
           final clipsMap = json['clips'] as Map<String, dynamic>;
           for (var key in clipsMap.keys) {
              animator.clips[key] = StickmanClip.fromJson(clipsMap[key]);
           }
        } else {
           // Try parsing root keys as clip names
           json.forEach((key, value) {
              if (key == 'gridz') return; // Skip gridz loading
              if (value is Map<String, dynamic>) {
                 try {
                   if (value.containsKey('keyframes')) {
                      animator.clips[key] = StickmanClip.fromJson(value);
                   }
                 } catch (e) {
                   // Not a clip
                 }
              }
           });
        }
      }
    } catch (e) {
      print("Warning: Failed to load stickman assets from $path: $e");
    }

    return animator;
  }

  // Handle WeaponType mismatch by using string matching
  void setWeapon(String name) {
    try {
      // Assuming Stickman3D package has a WeaponType enum
      final type = WeaponType.values.firstWhere(
        (e) => e.toString().split('.').last.toLowerCase() == name.toLowerCase(),
        orElse: () => WeaponType.none
      );
      _controller.weaponType = type;
    } catch (e) {
      _controller.weaponType = WeaponType.none;
    }
  }

  // Expose scale
  set scale(double value) => _controller.scale = value;

  void play(String name) {
    if (clips.containsKey(name)) {
      if (_controller.activeClip != clips[name]) {
        _controller.activeClip = clips[name];
        _controller.isPlaying = true;
        _controller.setMode(EditorMode.animate);
      }
    } else {
      // Fallback for procedural animations
      if (name == 'run' || name == 'idle') {
        _controller.setMode(EditorMode.pose);
      }
    }
  }

  void update(double dt) {
    // Pass 0 velocity as main.dart doesn't provide it in the update(dt) signature.
    // The controller uses velocity for procedural running.
    // Since we are likely using clips or falling back to pose mode, this might result in static procedural poses
    // if a clip isn't playing.
    // Ideally main.dart should pass velocity, but we are adhering to the requested signature.
    _controller.update(dt, 0, 0);
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
    // Draw centered or at feet?
    // Game logic seems to expect bottomCenter. StickmanPainter draws relative to hip usually.
    // We might need to adjust Y.
    painter.paint(canvas, Size(100, height));
    canvas.restore();
  }
}
