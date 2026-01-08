import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/palette.dart';
import 'package:flame_svg/flame_svg.dart'; // Imported as requested, even if unused for now
import 'package:flutter/material.dart';

void main() {
  runApp(GameWidget(game: VanguardGame()));
}

class VanguardGame extends FlameGame with HasCollisionDetection {
  late final Player player;
  late final JoystickComponent joystick;
  late final HudButtonComponent skillButton;

  @override
  Future<void> onLoad() async {
    // 1. Setup World
    // The default `world` is used. We will add components to it.

    // 2. Create the Player
    player = Player(position: Vector2(0, 0));
    world.add(player);

    // 3. Add Enemies
    world.add(Enemy(position: Vector2(200, 50)));
    world.add(Enemy(position: Vector2(400, -50)));
    world.add(Enemy(position: Vector2(600, 100)));

    // 4. Setup HUD (Joystick and Skill Button)
    // Left Joystick
    final knobPaint = BasicPalette.blue.withAlpha(200).paint();
    final backgroundPaint = BasicPalette.blue.withAlpha(100).paint();
    joystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: knobPaint),
      background: CircleComponent(radius: 50, paint: backgroundPaint),
      margin: const EdgeInsets.only(left: 40, bottom: 40),
    );

    // Right Skill Button
    final buttonSize = 60.0;
    skillButton = HudButtonComponent(
      button: CircleComponent(
        radius: buttonSize / 2,
        paint: BasicPalette.red.withAlpha(200).paint(),
      ),
      margin: const EdgeInsets.only(right: 40, bottom: 40),
      onPressed: () {
        debugPrint("Skill Pressed!");
        // Placeholder for skill logic
      },
    );

    // Add HUD elements to the viewport so they stay static on screen
    camera.viewport.add(joystick);
    camera.viewport.add(skillButton);

    // 5. Setup Camera
    // Set initial position
    camera.viewfinder.anchor = Anchor.center;
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Camera Logic: Follow Player X, Lock Y (e.g., at 0)
    // We update the camera's viewfinder position manually.
    // This clamps the Y axis to 0 while following the player on X.
    camera.viewfinder.position = Vector2(player.position.x, 0);
  }
}

class Player extends RectangleComponent with HasGameRef<VanguardGame> {
  static const double speed = 200;
  static const double weaponRange = 100;

  // Visuals
  final Paint _normalPaint = BasicPalette.white.paint();
  final Paint _attackPaint = BasicPalette.red.paint();

  Player({required Vector2 position})
      : super(
          position: position,
          size: Vector2(50, 80),
          anchor: Anchor.bottomCenter,
        );

  @override
  Future<void> onLoad() async {
    paint = _normalPaint;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Input Handling (Joystick)
    final joystick = gameRef.joystick;
    if (!joystick.delta.isZero()) {
      // Calculate movement vector
      Vector2 movement = joystick.relativeDelta * speed * dt;

      // Move Player
      position.add(movement);
    }

    // Depth System (Z-Ordering)
    // Priority = y.toInt(). ensures characters lower on the screen (higher Y)
    // render in front of characters higher on the screen.
    priority = position.y.toInt();

    // Auto-Attack Logic
    _checkAutoAttack();
  }

  void _checkAutoAttack() {
    bool enemyInRange = false;

    // Iterate through all children in the world to find Enemies.
    // In a production game, use a more efficient query method (e.g. QuadTree)
    for (final child in gameRef.world.children) {
      if (child is Enemy) {
        final distance = position.distanceTo(child.position);
        if (distance < weaponRange) {
          enemyInRange = true;
          break; // Found an enemy in range
        }
      }
    }

    // Update state based on enemy presence
    if (enemyInRange) {
      paint = _attackPaint; // "Attack State"
    } else {
      paint = _normalPaint;
    }
  }
}

class Enemy extends RectangleComponent {
  Enemy({required Vector2 position})
      : super(
          position: position,
          size: Vector2(50, 80),
          anchor: Anchor.bottomCenter,
          paint: BasicPalette.green.paint(),
        );

  @override
  void update(double dt) {
    super.update(dt);

    // Depth System (Z-Ordering)
    // Ensure consistent rendering order with Player
    priority = position.y.toInt();
  }
}
