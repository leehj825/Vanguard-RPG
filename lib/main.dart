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
        player.triggerSkill();
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
  static const double skillRange = 150;

  // Visuals
  final Paint _normalPaint = BasicPalette.white.paint();
  final Paint _attackPaint = BasicPalette.red.paint();

  // Child Components
  late final RectangleComponent weapon;
  late final CircleComponent skillEffect;

  // State
  double _attackTimer = 0;
  double _skillTimer = 0;
  bool _isSkillActive = false;

  Player({required Vector2 position})
      : super(
          position: position,
          size: Vector2(50, 80),
          anchor: Anchor.bottomCenter,
        );

  @override
  Future<void> onLoad() async {
    paint = _normalPaint;

    // Weapon (The Stick)
    // Anchored at the "hand" or center-right of the player
    weapon = RectangleComponent(
      size: Vector2(60, 10),
      paint: BasicPalette.brown.paint(),
      anchor: Anchor.centerLeft,
      position: Vector2(size.x / 2, size.y / 2),
      angle: -pi / 4, // Initial angle up
    );
    weapon.opacity = 0; // Hidden by default
    add(weapon);

    // Skill Effect (Swirl Wind)
    skillEffect = CircleComponent(
      radius: skillRange,
      paint: BasicPalette.cyan.withAlpha(100).paint(),
      anchor: Anchor.center,
      position: Vector2(size.x / 2, size.y / 2),
    );
    skillEffect.opacity = 0; // Hidden by default
    add(skillEffect);
  }

  void triggerSkill() {
    if (_isSkillActive) return; // Cooldown or currently active check could be here
    _isSkillActive = true;
    _skillTimer = 1.0; // 1 second duration
    skillEffect.opacity = 1;
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

      // Facing Logic
      if (movement.x > 0 && scale.x < 0) {
        scale.x = 1; // Face Right
      } else if (movement.x < 0 && scale.x > 0) {
        scale.x = -1; // Face Left
      }
    }

    // Depth System (Z-Ordering)
    priority = position.y.toInt();

    // Auto-Attack Logic
    _checkAutoAttack(dt);

    // Skill Logic
    if (_isSkillActive) {
      _updateSkill(dt);
    }
  }

  void _checkAutoAttack(double dt) {
    bool enemyInRange = false;

    // Check for enemies
    for (final child in gameRef.world.children) {
      if (child is Enemy) {
        final distance = position.distanceTo(child.position);
        if (distance < weaponRange) {
          enemyInRange = true;
          break;
        }
      }
    }

    // Update state
    if (enemyInRange) {
      paint = _attackPaint;
      weapon.opacity = 1;

      // Animate weapon: Sine wave swinging
      _attackTimer += dt * 10; // Speed of swing
      // Swing between -pi/4 (up) and 0 (front) roughly, or just wiggle
      // Let's make it swing from -45 deg to +45 deg relative to front
      weapon.angle = sin(_attackTimer) * 0.5;
    } else {
      paint = _normalPaint;
      weapon.opacity = 0;
      _attackTimer = 0; // Reset
    }
  }

  void _updateSkill(double dt) {
    _skillTimer -= dt;

    // Rotate the effect
    skillEffect.angle += dt * 10; // Fast rotation

    // Check for damage
    for (final child in gameRef.world.children) {
      if (child is Enemy) {
        final distance = position.distanceTo(child.position);
        // Note: skillEffect radius is `skillRange`, so diameter is 2*skillRange.
        // But `radius` in CircleComponent constructor is the radius.
        // Distance check:
        if (distance < skillRange + 25) { // +25 is rough radius of enemy
             child.takeDamageEffect();
        }
      }
    }

    if (_skillTimer <= 0) {
      _isSkillActive = false;
      skillEffect.opacity = 0;
    }
  }
}

class Enemy extends RectangleComponent {
  final Paint _normalPaint = BasicPalette.purple.paint();
  final Paint _damagePaint = BasicPalette.red.paint();

  double _damageTimer = 0;

  Enemy({required Vector2 position})
      : super(
          position: position,
          size: Vector2(50, 80),
          anchor: Anchor.bottomCenter,
        ) {
     paint = _normalPaint;
  }

  void takeDamageEffect() {
    paint = _damagePaint;
    _damageTimer = 0.5; // Red for 0.5 seconds
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Depth System
    priority = position.y.toInt();

    // Handle damage effect timer
    if (_damageTimer > 0) {
      _damageTimer -= dt;
      if (_damageTimer <= 0) {
        paint = _normalPaint;
      }
    }
  }
}
