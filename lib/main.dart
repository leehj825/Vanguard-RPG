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
  late final PlayerHealthBar playerHealthBar;

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

    // 3. Setup HUD (Joystick, Skill Button, Distance Tracker, XP, Health)
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

    // XP Bar (Below Level Text)
    xpBar = XpBarComponent(player: player);

    // Player Health Bar (Top Center/Right or below XP)
    playerHealthBar = PlayerHealthBar(player: player);

    // Add HUD elements to the viewport so they stay static on screen
    camera.viewport.add(joystick);
    camera.viewport.add(skillButton);
    camera.viewport.add(distanceText);
    camera.viewport.add(xpLevelText);
    camera.viewport.add(xpBar);
    camera.viewport.add(playerHealthBar);

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

class Weapon extends RectangleComponent {
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
}

class Player extends RectangleComponent with HasGameRef<VanguardGame> {
  static const double speed = 200;
  static const double skillRange = 150;

  // Stats
  int level = 1;
  double currentXp = 0;
  double targetXp = 100;
  double stickDamage = 20; // Updated Start Damage

  double maxHp = 100;
  double hp = 100;

  // Visuals
  final Paint _normalPaint = BasicPalette.white.paint();
  final Paint _damagePaint = BasicPalette.red.paint();
  final Paint _brownPaint = BasicPalette.brown.paint();

  // Child Components
  late final Weapon stickWeapon; // Renamed as requested
  late final CircleComponent skillEffect;

  // State
  double _attackTimer = 0;
  double _damageCooldown = 0; // Timer for dealing damage (hit rate)
  double _hitCooldown = 0; // Invulnerability timer

  double _skillTimer = 0;
  bool _isSkillActive = false;
  final Set<Enemy> _skillHitTargets = {};

  bool get isAttacking => stickWeapon.opacity > 0;

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
    stickWeapon = Weapon(
      size: Vector2(60, 10),
      paint: _brownPaint,
      anchor: Anchor.centerLeft,
      position: Vector2(size.x / 2, size.y / 2),
      angle: -pi / 4, // Initial angle up
    );
    stickWeapon.opacity = 0; // Hidden by default
    add(stickWeapon);

    // Skill Effect
    skillEffect = CircleComponent(
      radius: skillRange,
      paint: BasicPalette.cyan.withAlpha(100).paint(),
      anchor: Anchor.center,
      position: Vector2(size.x / 2, size.y / 2),
    );
    skillEffect.opacity = 0;
    add(skillEffect);
  }

  void gainXp(double amount) {
    currentXp += amount;
    while (currentXp >= targetXp) {
      currentXp -= targetXp;
      level++;
      targetXp *= 1.5;
      stickDamage += 10;
      maxHp += 20;
      hp = maxHp; // Heal on level up
      gameRef.world.add(
        LevelUpText(
          position: position.clone()..y -= 80,
        )
      );
    }
  }

  void triggerSkill() {
    if (_isSkillActive) return;
    _isSkillActive = true;
    _skillTimer = 1.0;
    skillEffect.opacity = 1;
    _skillHitTargets.clear();
  }

  void takeDamage(double amount) {
    if (_hitCooldown > 0) return; // Invulnerable

    hp -= amount;
    _hitCooldown = 0.2; // 0.2s invulnerability

    // Visual Feedback
    paint = _damagePaint;

    if (hp <= 0) {
      hp = 0;
      // Restart or Reset logic could be here
      // For now, infinite life hack for endless running as no death screen requested
      hp = maxHp;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Input Handling
    final joystick = gameRef.joystick;
    if (!joystick.delta.isZero()) {
      Vector2 movement = joystick.relativeDelta * speed * dt;
      position.add(movement);
      if (position.x < 0) position.x = 0;
      if (movement.x > 0 && scale.x < 0) scale.x = 1;
      else if (movement.x < 0 && scale.x > 0) scale.x = -1;
    }

    // Depth System
    priority = position.y.toInt();

    // Timers
    if (_damageCooldown > 0) _damageCooldown -= dt;
    if (_hitCooldown > 0) {
      _hitCooldown -= dt;
      if (_hitCooldown <= 0) paint = _normalPaint; // Restore color
    }

    // Weapon Logic (Animation & Overlap Check)
    _handleWeaponLogic(dt);

    // Skill Logic
    if (_isSkillActive) {
      _updateSkill(dt);
    }
  }

  void _handleWeaponLogic(double dt) {
    // 1. Detection for animation
    bool enemyInDetectionRange = false;
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
      stickWeapon.opacity = 1;
      _attackTimer += dt * 10;
      stickWeapon.angle = sin(_attackTimer) * 0.5;
    } else {
      stickWeapon.opacity = 0;
      _attackTimer = 0;
    }

    // 3. Precise Collision Damage Logic
    // Player deals damage ONLY if `stickWeapon` overlaps `enemy` AND is attacking
    if (isAttacking && _damageCooldown <= 0) {
      bool hitSomeone = false;
      // Iterate enemies
      // Using toList() to avoid concurrent mod issues if enemies die instantly
      for (final child in gameRef.world.children.toList()) {
        if (child is Enemy) {
          // Check overlap between Weapon Rect and Enemy Rect
          if (stickWeapon.toAbsoluteRect().overlaps(child.toAbsoluteRect())) {
             child.takeDamage(stickDamage);
             hitSomeone = true;
          }
        }
      }

      if (hitSomeone) {
        _damageCooldown = 0.5; // Attack rate limit
      }
    }
  }

  void _updateSkill(double dt) {
    _skillTimer -= dt;
    skillEffect.angle += dt * 10;
    for (final child in gameRef.world.children.toList()) {
      if (child is Enemy) {
        // Skill remains distance based for now as per prompt focusing on Weapon Hitboxes
        if (position.distanceTo(child.position) < skillRange + 25) {
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
  final Paint _weaponPaint = BasicPalette.red.paint();

  // Health
  double maxHp = 40; // Reduced from 100
  double hp = 40;
  double speed = 100;
  double attackRange = 70;
  double damage = 5; // Reduced from 10

  double _damageTimer = 0; // Visual flash timer
  double _attackCooldown = 0; // Attack frequency
  double _swingTimer = 0;
  double _hitCooldown = 0; // Invulnerability timer

  late final Weapon weaponVisual; // Renamed as requested

  bool get isAttacking => weaponVisual.opacity > 0;

  Enemy({required Vector2 position, double hpScale = 1.0})
      : super(
          position: position,
          size: Vector2(50, 80),
          anchor: Anchor.bottomCenter,
        ) {
     paint = _normalPaint;
     maxHp = 40 * hpScale; // Base 40 * scale
     hp = maxHp;
  }

  @override
  Future<void> onLoad() async {
    add(HealthBarComponent());

    weaponVisual = Weapon(
      size: Vector2(60, 10),
      paint: _weaponPaint,
      anchor: Anchor.centerLeft,
      position: Vector2(size.x / 2, size.y / 2),
      angle: -pi / 4,
    );
    weaponVisual.opacity = 0;
    add(weaponVisual);
  }

  void takeDamage(double amount) {
    if (_hitCooldown > 0) return;

    hp -= amount;
    _hitCooldown = 0.2; // Invulnerability window

    // Visual Feedback
    takeDamageEffect();

    gameRef.world.add(
      DamageText(
        amount.toInt().toString(),
        position - Vector2(0, size.y),
      )
    );

    if (hp <= 0) {
      removeFromParent();
      gameRef.player.gainXp(35);
    }
  }

  void takeDamageEffect() {
    paint = _damagePaint;
    _damageTimer = 0.5;
  }

  @override
  void update(double dt) {
    super.update(dt);
    priority = position.y.toInt();

    // Timers
    if (_damageTimer > 0) {
      _damageTimer -= dt;
      if (_damageTimer <= 0) paint = _normalPaint;
    }
    if (_hitCooldown > 0) _hitCooldown -= dt;

    // AI
    final player = gameRef.player;
    final dist = position.distanceTo(player.position);

    if (player.position.x < position.x) {
      scale.x = -1;
    } else {
      scale.x = 1;
    }

    if (dist > attackRange) {
      // Chase
      final dir = (player.position - position).normalized();
      position.add(dir * speed * dt);
      weaponVisual.opacity = 0;
      _swingTimer = 0;
    } else {
      // Stop and Attack
      _performAttack(dt, player);
    }
  }

  void _performAttack(double dt, Player player) {
    weaponVisual.opacity = 1;
    _swingTimer += dt * 10;
    weaponVisual.angle = sin(_swingTimer) * 0.5;

    if (_attackCooldown > 0) {
      _attackCooldown -= dt;
    }

    // Damage Check: Enemy Weapon overlaps Player Body
    if (_attackCooldown <= 0) {
      if (weaponVisual.toAbsoluteRect().overlaps(player.toAbsoluteRect())) {
         player.takeDamage(damage);
         _attackCooldown = 1.0; // 1 second between hits
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
    priority = position.y.toInt();
  }
}

class HealthBarComponent extends PositionComponent with HasAncestor<Enemy> {
  final Paint _barBackPaint = BasicPalette.red.paint();
  final Paint _barForePaint = BasicPalette.green.paint();

  HealthBarComponent() : super(
    position: Vector2(0, -10),
    size: Vector2(50, 5),
  );

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _barBackPaint);
    final enemy = ancestor;
    double hpPercent = 0;
    if (enemy.maxHp > 0) hpPercent = enemy.hp / enemy.maxHp;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x * hpPercent, size.y),
      _barForePaint
    );
  }
}

class PlayerHealthBar extends PositionComponent {
  final Player player;
  final Paint _barBackPaint = BasicPalette.gray.paint();
  final Paint _barForePaint = BasicPalette.blue.paint();

  PlayerHealthBar({required this.player}) : super(
    position: Vector2(20, 120), // Below XP Bar
    size: Vector2(200, 20),
  );

  @override
  void render(Canvas canvas) {
    // Draw Background
    canvas.drawRect(size.toRect(), _barBackPaint);

    // Draw Foreground (Health)
    double hpPercent = 0;
    if (player.maxHp > 0) {
      hpPercent = player.hp / player.maxHp;
    }
    if (hpPercent < 0) hpPercent = 0;
    if (hpPercent > 1) hpPercent = 1;

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
    canvas.drawRect(size.toRect(), _barBackPaint);
    double xpPercent = 0;
    if (player.targetXp > 0) xpPercent = player.currentXp / player.targetXp;
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
    add(MoveEffect.by(Vector2(0, -50), LinearEffectController(1.0)));
    add(RemoveEffect(delay: 1.0));
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
              fontSize: 32,
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
    add(MoveEffect.by(Vector2(0, -80), LinearEffectController(2.0)));
    add(RemoveEffect(delay: 2.0));
  }
}
