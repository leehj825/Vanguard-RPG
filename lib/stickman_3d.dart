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
        // Option A: The file is a single Clip
        // Option B: The file is a collection of clips
        // Option C: The file is a full Project export

        // Let's assume a simple key-value map of clips for this game
        if (json.containsKey('clips')) {
           final clipsMap = json['clips'] as Map<String, dynamic>;
           for (var key in clipsMap.keys) {
              animator.clips[key] = StickmanClip.fromJson(clipsMap[key]);
           }
        } else {
           // Try parsing root keys as clip names
           json.forEach((key, value) {
              if (value is Map<String, dynamic>) {
                 try {
                   // Verify if it looks like a clip
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
      // If loading fails or file doesn't exist (mock), just proceed with procedural controller
      print("Warning: Failed to load stickman assets from $path: $e");
    }

    return animator;
  }

  set weaponType(WeaponType type) => _controller.weaponType = type;

  // Expose scale if needed
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
    // The library requires velocity for procedural animation.
    // Since this update method doesn't receive velocity, we assume 0 or
    // rely on 'play("run")' having triggered a clip.
    // If we are in procedural mode (EditorMode.pose) and running, we might miss leg movement
    // if we pass 0,0.
    // However, without changing the call signature in main.dart, this is the best we can do.
    // Note: If 'play' switched to 'animate' mode, velocity is ignored anyway.
    _controller.update(dt, 0, 0);
  }

  void render(Canvas canvas, Vector2 position, double height) {
    // StickmanPainter requires a controller
    final painter = StickmanPainter(
      controller: _controller,
      color: color,
      // Default view parameters
      cameraView: CameraView.side,
      viewZoom: 1.0,
      viewPan: Offset.zero,
      cameraHeightOffset: 0,
      viewRotationX: 0,
      viewRotationY: 0,
    );

    canvas.save();
    canvas.translate(position.x, position.y);

    // The painter paints based on the skeleton's absolute coordinates.
    // We assume the skeleton is centered at (0,0) relative to the hip/root.
    // The provided height is likely the entity height for scaling?
    // StickmanPainter doesn't take 'height' constraint, it draws the skeleton as is.
    // Scaling is handled by _controller.scale.

    painter.paint(canvas, Size(100, height));

    canvas.restore();
  }
}
