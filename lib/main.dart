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
  late final TextComponent distanceText;

  // Spawning State
  final Random _random = Random();
  double _spawnTimer = 0;

  @override
  Future<void> onLoad() async {
    // 1. Setup World
    // The default `world` is used. We will add components to it.

    // 2. Create the Player
    player = Player(position: Vector2(0, 0));
    world.add(player);

    // 3. Setup HUD (Joystick, Skill Button, Distance Tracker)
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

    // Distance Tracker Text
    distanceText = TextComponent(
      text: 'Distance: 0m',
      position: Vector2(20, 40), // Top-left margin
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(offset: Offset(2, 2), color: Colors.black, blurRadius: 2),
          ],
        ),
      ),
    );

    // Add HUD elements to the viewport so they stay static on screen
    camera.viewport.add(joystick);
    camera.viewport.add(skillButton);
    camera.viewport.add(distanceText);

    // 5. Setup Camera
    // Set initial position
    camera.viewfinder.anchor = Anchor.center;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // 1. Camera Logic
    // Follow Player X, Lock Y at 0.
    // Clamp so camera doesn't show negative world space (left of start) if desired,
    // but typically strictly following player X is fine for endless scroller.
    // Ensure player doesn't move left of 0 is handled in Player class.
    camera.viewfinder.position = Vector2(player.position.x, 0);

    // 2. Update HUD
    distanceText.text = 'Distance: ${(player.position.x / 10).toInt()}m';

    // 3. Endless Spawning System
    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _spawnEntity();
      // Reset timer to random interval between 1.5s and 2.0s
      _spawnTimer = 1.5 + _random.nextDouble() * 0.5;
    }

    // 4. Garbage Collection (Cleanup)
    // Remove entities that are far behind the player
    // Iterate over a copy to safely remove
    for (final child in world.children.toList()) {
      // Check if it's an Enemy or Rock (spawned entities)
      if (child is Enemy || child is Rock) {
        // If > 1000 pixels behind player
        if ((child as PositionComponent).position.x < player.position.x - 1000) {
          child.removeFromParent();
        }
      }
    }
  }

  void _spawnEntity() {
    // Determine spawn position
    // Spawn off-screen to the right.
    // Camera shows window around player.position.x.
    // Viewport size is not always available in onLoad but is in update.
    final viewportWidth = camera.viewport.size.x;
    final spawnX = player.position.x + viewportWidth / 2 + 100;

    // Random Y between "floor bounds".
    // Let's assume a playable area of -150 to 150 based on previous entity positions.
    final spawnY = -150 + _random.nextDouble() * 300;

    final spawnPos = Vector2(spawnX, spawnY);

    if (_random.nextDouble() < 0.7) {
      // 70% Chance Enemy
      world.add(Enemy(position: spawnPos));
    } else {
      // 30% Chance Rock
      world.add(Rock(position: spawnPos));
    }
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

      // Boundary Check (Left Wall at 0)
      if (position.x < 0) {
        position.x = 0;
      }

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

class Rock extends CircleComponent {
  Rock({required Vector2 position})
      : super(
          radius: 30, // 60px diameter
          position: position,
          anchor: Anchor.center,
          paint: BasicPalette.gray.paint(),
        );

  @override
  void update(double dt) {
    super.update(dt);
    // Depth System
    priority = position.y.toInt();
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
