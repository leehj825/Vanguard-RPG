import 'dart:math';

import 'package:flame/collisions.dart';
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
  late final TextComponent xpLevelText;
  late final XpBarComponent xpBar;

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

    // 3. Setup HUD (Joystick, Skill Button, Distance Tracker, XP)
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

    // Distance Tracker Text (Top Left)
    distanceText = TextComponent(
      text: 'Distance: 0m',
      position: Vector2(20, 40),
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

    // XP Level Text (Below Distance)
    xpLevelText = TextComponent(
      text: 'Lvl 1',
      position: Vector2(20, 70),
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.yellow,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(offset: Offset(2, 2), color: Colors.black, blurRadius: 2),
          ],
        ),
      ),
    );

    // XP Bar (Top Centerish)
    xpBar = XpBarComponent(player: player);

    // Add HUD elements to the viewport so they stay static on screen
    camera.viewport.add(joystick);
    camera.viewport.add(skillButton);
    camera.viewport.add(distanceText);
    camera.viewport.add(xpLevelText);
    camera.viewport.add(xpBar);

    // 5. Setup Camera
    // Set initial position
    camera.viewfinder.anchor = Anchor.center;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // 1. Camera Logic
    // Follow Player X, Lock Y at 0.
    camera.viewfinder.position = Vector2(player.position.x, 0);

    // 2. Update HUD
    distanceText.text = 'Distance: ${(player.position.x / 10).toInt()}m';
    xpLevelText.text = 'Lvl ${player.level}';

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
    final viewportWidth = camera.viewport.size.x;
    final spawnX = player.position.x + viewportWidth / 2 + 100;

    // Random Y between "floor bounds".
    final spawnY = -150 + _random.nextDouble() * 300;

    final spawnPos = Vector2(spawnX, spawnY);

    if (_random.nextDouble() < 0.7) {
      // 70% Chance Enemy
      // Calculate Difficulty Scaling
      double difficultyScale = 1.0 + (player.level * 0.2);
      world.add(Enemy(position: spawnPos, hpScale: difficultyScale));
    } else {
      // 30% Chance Rock
      world.add(Rock(position: spawnPos));
    }
  }
}

class Weapon extends RectangleComponent with CollisionCallbacks {
  final Set<PositionComponent> currentlyColliding = {};

  Weapon({
    required Vector2 size,
    required Paint paint,
    required Vector2 position,
    required Anchor anchor,
    double angle = 0,
  }) : super(
          size: size,
          paint: paint,
          position: position,
          anchor: anchor,
          angle: angle,
        );

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox());
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    currentlyColliding.add(other);
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    super.onCollisionEnd(other);
    currentlyColliding.remove(other);
  }
}

class Player extends RectangleComponent
    with HasGameRef<VanguardGame>, CollisionCallbacks {
  static const double speed = 200;
  static const double skillRange = 150;

  // Stats
  int level = 1;
  double currentXp = 0;
  double targetXp = 100;
  double stickDamage = 10;

  double maxHp = 100;
  double hp = 100;

  // Visuals
  final Paint _normalPaint = BasicPalette.white.paint();
  final Paint _brownPaint = BasicPalette.brown.paint();

  // Child Components
  late final Weapon weapon;
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

    // Add Hitbox for receiving damage
    add(RectangleHitbox());

    // Weapon (The Stick)
    // Anchored at the "hand" or center-right of the player
    weapon = Weapon(
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

  void gainXp(double amount) {
    currentXp += amount;
    // Level Up Loop (in case massive XP gain)
    while (currentXp >= targetXp) {
      currentXp -= targetXp;
      level++;
      targetXp *= 1.5;
      stickDamage += 10;
      maxHp += 20; // Increase max HP on level up
      hp = maxHp;  // Heal on level up

      // Visual Feedback
      gameRef.world.add(
        LevelUpText(
          position: position.clone()..y -= 80, // Above head
        )
      );
    }
  }

  void triggerSkill() {
    if (_isSkillActive) return; // Cooldown or currently active check could be here
    _isSkillActive = true;
    _skillTimer = 1.0; // 1 second duration
    skillEffect.opacity = 1;
    _skillHitTargets.clear(); // Reset hit targets for new skill activation
  }

  void takeDamage(double amount) {
    hp -= amount;
    if (hp < 0) hp = 0;

    // Optional: Add visual feedback for player damage
    // For now, console log or similar, as no Player Health Bar was requested visually,
    // but the mechanics are implemented.
    if (hp == 0) {
      // Game Over logic could go here.
      // For endless runner, maybe just respawn or reset level.
      // For now, just heal back to full to loop endless.
      hp = maxHp;
    }
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

    // Weapon Logic (Attack & Damage)
    _handleWeaponLogic(dt);

    // Skill Logic
    if (_isSkillActive) {
      _updateSkill(dt);
    }
  }

  void _handleWeaponLogic(double dt) {
    // 1. Determine if we should attack (auto-attack based on range still needed to trigger animation?)
    // The prompt says "Remove the old 'distance-based' damage logic."
    // But we still need to know when to swing the weapon.
    // Let's assume auto-attack swings if ANY enemy is in a "detection range"
    // OR just use the previous "range" check to trigger the animation,
    // BUT damage is ONLY dealt via collision.

    bool enemyInDetectionRange = false;
    // Check purely for animation triggering
    for (final child in gameRef.world.children) {
      if (child is Enemy) {
        if (position.distanceTo(child.position) < 100) {
          enemyInDetectionRange = true;
          break;
        }
      }
    }

    // 2. Animate Weapon
    if (enemyInDetectionRange) {
      weapon.opacity = 1;
      _attackTimer += dt * 10;
      weapon.angle = sin(_attackTimer) * 0.5;
    } else {
      weapon.opacity = 0;
      _attackTimer = 0;
    }

    // 3. Collision Damage Logic
    if (_damageCooldown > 0) {
      _damageCooldown -= dt;
    }

    // Only deal damage if weapon is visible (attacking) AND cooldown is ready
    if (weapon.opacity > 0 && _damageCooldown <= 0) {
      bool dealtDamage = false;
      for (final other in weapon.currentlyColliding) {
        if (other is Enemy) {
           other.takeDamage(stickDamage);
           dealtDamage = true;
        }
      }

      if (dealtDamage) {
        _damageCooldown = 0.5; // 0.5s between hits
      }
    }
  }

  void _updateSkill(double dt) {
    _skillTimer -= dt;

    // Rotate the effect
    skillEffect.angle += dt * 10; // Fast rotation

    // Check for damage (Skill still uses distance/radius check as requested "Skills apply instant damage... once per activation")
    // Note: User prompt focused on "Precise Weapon Hitboxes", not changing Skill logic.
    // So we keep the existing skill logic but ensure it uses the copy of children list.
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

class Enemy extends RectangleComponent with HasGameRef<VanguardGame>, CollisionCallbacks {
  final Paint _normalPaint = BasicPalette.purple.paint();
  final Paint _damagePaint = BasicPalette.red.paint();
  final Paint _weaponPaint = BasicPalette.red.paint(); // Red stick for enemy

  // Health
  double maxHp = 100;
  double hp = 100;
  double speed = 100;
  double attackRange = 70;

  double _damageTimer = 0;
  double _attackCooldown = 0;
  double _swingTimer = 0;

  late final Weapon weapon;

  Enemy({required Vector2 position, double hpScale = 1.0})
      : super(
          position: position,
          size: Vector2(50, 80),
          anchor: Anchor.bottomCenter,
        ) {
     paint = _normalPaint;
     maxHp = 100 * hpScale;
     hp = maxHp;
  }

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox());
    add(HealthBarComponent());

    // Enemy Weapon
    weapon = Weapon(
      size: Vector2(60, 10),
      paint: _weaponPaint,
      anchor: Anchor.centerLeft,
      position: Vector2(size.x / 2, size.y / 2),
      angle: -pi / 4,
    );
    weapon.opacity = 0; // Hidden until attacking
    add(weapon);
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
      // Grant XP to player
      gameRef.player.gainXp(35);
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

    // AI Behavior
    final player = gameRef.player;
    final dist = position.distanceTo(player.position);

    // Face the player
    if (player.position.x < position.x) {
      scale.x = -1; // Face Left (original is right-facing?)
      // If scale.x is -1, the weapon (child) also flips, which is good.
    } else {
      scale.x = 1; // Face Right
    }

    if (dist > attackRange) {
      // Chase
      final dir = (player.position - position).normalized();
      position.add(dir * speed * dt);

      // Stop attacking while moving
      weapon.opacity = 0;
      _swingTimer = 0;
    } else {
      // Stop and Attack
      _performAttack(dt);
    }
  }

  void _performAttack(double dt) {
    // Attack Animation
    weapon.opacity = 1;
    _swingTimer += dt * 10;
    weapon.angle = sin(_swingTimer) * 0.5;

    // Cooldown Logic
    if (_attackCooldown > 0) {
      _attackCooldown -= dt;
    }

    // Damage Logic (Hitbox based)
    if (_attackCooldown <= 0) {
      bool hitPlayer = false;
      for (final other in weapon.currentlyColliding) {
        if (other is Player) {
           other.takeDamage(10); // Fixed damage for enemy for now
           hitPlayer = true;
        }
      }

      if (hitPlayer) {
        _attackCooldown = 1.0; // Enemy attacks once per second
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
    position: Vector2(0, -10), // 10 pixels above head
    size: Vector2(50, 5),
  );

  @override
  void render(Canvas canvas) {
    // Background
    canvas.drawRect(size.toRect(), _barBackPaint);

    // Foreground
    final enemy = ancestor;
    // Safety check for div by zero if maxHp is somehow 0 (unlikely)
    double hpPercent = 0;
    if (enemy.maxHp > 0) {
      hpPercent = enemy.hp / enemy.maxHp;
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x * hpPercent, size.y),
      _barForePaint
    );
  }
}

class XpBarComponent extends PositionComponent {
  final Player player;
  final Paint _barBackPaint = BasicPalette.gray.paint();
  final Paint _barForePaint = BasicPalette.yellow.paint();

  XpBarComponent({required this.player}) : super(
    position: Vector2(20, 100), // Below Level Text
    size: Vector2(200, 15),
  );

  @override
  void render(Canvas canvas) {
    // Background
    canvas.drawRect(size.toRect(), _barBackPaint);

    // Foreground
    double xpPercent = 0;
    if (player.targetXp > 0) {
      xpPercent = player.currentXp / player.targetXp;
    }
    // Clamp
    if (xpPercent > 1) xpPercent = 1;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x * xpPercent, size.y),
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

    // Remove after 1s.
    add(
      RemoveEffect(delay: 1.0),
    );
  }
}

class LevelUpText extends TextComponent {
  LevelUpText({required Vector2 position})
      : super(
          text: "LEVEL UP!",
          position: position,
          textRenderer: TextPaint(
            style: const TextStyle(
              color: Colors.yellow,
              fontSize: 32, // Larger
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
    // Move Up Effect (Slower, higher)
    add(
      MoveEffect.by(
        Vector2(0, -80),
        LinearEffectController(2.0),
      ),
    );

    // Remove after 2s.
    add(
      RemoveEffect(delay: 2.0),
    );
  }
}
