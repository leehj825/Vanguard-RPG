import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/palette.dart';
import 'package:flame_svg/flame_svg.dart'; // Imported as requested
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
  final Paint _brownPaint = BasicPalette.brown.paint();

  // Child Components
  late final RectangleComponent weapon;
  late final CircleComponent skillEffect;

  // State
  double _attackTimer = 0;
  double _damageCooldown = 0; // Timer for auto-attack damage

  double _skillTimer = 0;
  bool _isSkillActive = false;
  final Set<Enemy> _skillHitTargets = {}; // Track enemies hit by current skill

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
      paint: _brownPaint,
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
    _skillHitTargets.clear(); // Reset hit targets for new skill activation
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
    bool dealtDamage = false;

    // Countdown damage cooldown
    if (_damageCooldown > 0) {
      _damageCooldown -= dt;
    }

    // Iterate through all children in the world to find Enemies.
    // Use toList() to avoid concurrent modification when enemies are removed or added.
    for (final child in gameRef.world.children.toList()) {
      if (child is Enemy) {
        final distance = position.distanceTo(child.position);
        if (distance < weaponRange) {
          enemyInRange = true;

          // Apply Damage if cooldown ready
          if (_damageCooldown <= 0) {
             child.takeDamage(10);
             dealtDamage = true;
          }
        }
      }
    }

    // Reset cooldown if we dealt damage to anyone
    if (dealtDamage) {
      _damageCooldown = 0.5;
    }

    // Update Visual State
    if (enemyInRange) {
      paint = _attackPaint;
      weapon.opacity = 1;

      // Animate weapon: Sine wave swinging
      _attackTimer += dt * 10;
      weapon.angle = sin(_attackTimer) * 0.5;
    } else {
      paint = _normalPaint;
      weapon.opacity = 0;
      _attackTimer = 0;
    }
  }

  void _updateSkill(double dt) {
    _skillTimer -= dt;

    // Rotate the effect
    skillEffect.angle += dt * 10; // Fast rotation

    // Check for damage
    for (final child in gameRef.world.children.toList()) {
      if (child is Enemy) {
        final distance = position.distanceTo(child.position);
        // Collision check for skill (Radius + Enemy size approx)
        if (distance < skillRange + 25) {
           if (!_skillHitTargets.contains(child)) {
             child.takeDamage(50);
             _skillHitTargets.add(child);
           }
        }
      }
    }

    if (_skillTimer <= 0) {
      _isSkillActive = false;
      skillEffect.opacity = 0;
    }
  }
}

class Enemy extends RectangleComponent with HasGameRef<VanguardGame> {
  final Paint _normalPaint = BasicPalette.purple.paint();
  final Paint _damagePaint = BasicPalette.red.paint();

  // Health
  double maxHp = 100;
  double hp = 100;

  double _damageTimer = 0;

  Enemy({required Vector2 position})
      : super(
          position: position,
          size: Vector2(50, 80),
          anchor: Anchor.bottomCenter,
        ) {
     paint = _normalPaint;
  }

  @override
  Future<void> onLoad() async {
    // Add Health Bar as a child component
    add(HealthBarComponent());
  }

  void takeDamage(double amount) {
    hp -= amount;
    if (hp < 0) hp = 0;

    // Show Damage Text
    // Spawn at top of enemy (approx height)
    gameRef.world.add(
      DamageText(
        amount.toInt().toString(),
        position - Vector2(0, size.y), // Position above head
      )
    );

    // Visual Feedback
    takeDamageEffect();

    // Check Death
    if (hp <= 0) {
      removeFromParent();
    }
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

class HealthBarComponent extends PositionComponent with HasAncestor<Enemy> {
  final Paint _barBackPaint = BasicPalette.red.paint();
  final Paint _barForePaint = BasicPalette.green.paint();

  HealthBarComponent() : super(
    position: Vector2(0, -10), // 10 pixels above head (relative to parent top-left if not scaled?)
    // Note: Parent (Enemy) is 50x80. Anchor BottomCenter.
    // Children positions are relative to the top-left of the parent's size box (0,0) to (50,80).
    // So (0, -10) is 10px above the top edge.
    size: Vector2(50, 5),
  );

  @override
  void render(Canvas canvas) {
    // Background
    canvas.drawRect(size.toRect(), _barBackPaint);

    // Foreground
    final enemy = ancestor;
    final hpPercent = enemy.hp / enemy.maxHp;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x * hpPercent, size.y),
      _barForePaint
    );
  }
}

class DamageText extends TextComponent {
  DamageText(String text, Vector2 position)
      : super(
          text: text,
          position: position,
          textRenderer: TextPaint(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(offset: Offset(2, 2), color: Colors.black, blurRadius: 2),
              ],
            ),
          ),
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    // Move Up Effect
    add(
      MoveEffect.by(
        Vector2(0, -50),
        LinearEffectController(1.0),
      ),
    );

    // Fade Out Effect removed to prevent crashes/issues.
    // Just remove after 1s.
    add(
      RemoveEffect(delay: 1.0),
    );
  }
}
