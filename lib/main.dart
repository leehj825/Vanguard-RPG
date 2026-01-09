import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/palette.dart';
import 'package:flame_svg/flame_svg.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(
    GameWidget(
      game: VanguardGame(),
      overlayBuilderMap: {
        'GameOver': (BuildContext context, VanguardGame game) {
          return Center(
            child: Container(
              color: Colors.black.withOpacity(0.8),
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'GAME OVER',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          blurRadius: 4,
                          color: Colors.black,
                          offset: Offset(2, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    ),
                    onPressed: () {
                      game.resetGame();
                      game.overlays.remove('GameOver');
                    },
                    child: const Text(
                      'Restart',
                      style: TextStyle(fontSize: 24),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      },
    ),
  );
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

  void resetGame() {
    player.reset();

    // Remove all spawned entities
    // Iterate over a copy to avoid concurrent modification during removal
    for (final child in world.children.toList()) {
      if (child is Enemy || child is Rock || child is DamageText || child is LevelUpText) {
        child.removeFromParent();
      }
    }

    _spawnTimer = 0;
    resumeEngine();
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
    for (final child in world.children.toList()) {
      if (child is Enemy || child is Rock) {
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
      double difficultyScale = 1.0 + (player.level * 0.2); // Start at 1.0, +20% per level (simplified)
      // Base HP 40 * (1 + level * 0.1) according to requirements.
      // Requirement says: "Enemy Max HP: 40 (Scales with level)."
      // Requirement says: "New enemies spawn with higher Max HP based on the Player's Level."
      // Let's stick to the simpler formula logic or explicit if needed.
      // Re-reading requirements: "Enemy Max HP: 40 (Scales with level)."
      // I'll implement exactly that.
      world.add(Enemy(position: spawnPos, levelScale: player.level));
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
  static final Vector2 playerSize = Vector2(35, 56); // 70% of 50x80

  // Stats
  int level = 1;
  double currentXp = 0;
  double targetXp = 100;
  double stickDamage = 20;

  double maxHp = 100;
  double hp = 100;

  // Visuals
  final Paint _normalPaint = BasicPalette.white.paint();
  final Paint _damagePaint = BasicPalette.red.paint();
  final Paint _brownPaint = BasicPalette.brown.paint();

  // Child Components
  late final Weapon stickWeapon;
  late final CircleComponent skillEffect;

  // State
  double _attackTimer = 0;
  double _damageCooldown = 0;
  double _hitCooldown = 0;

  double _skillTimer = 0;
  bool _isSkillActive = false;
  final Set<Enemy> _skillHitTargets = {};

  bool get isAttacking => stickWeapon.opacity > 0;

  Player({required Vector2 position})
      : super(
          position: position,
          size: playerSize,
          anchor: Anchor.bottomCenter,
        );

  @override
  Future<void> onLoad() async {
    paint = _normalPaint;

    // Weapon (The Stick) - Size kept as requested (60x10)
    stickWeapon = Weapon(
      size: Vector2(60, 10),
      paint: _brownPaint,
      anchor: Anchor.centerLeft,
      position: Vector2(size.x / 2, size.y / 2),
      angle: -pi / 4,
    );
    stickWeapon.opacity = 0;
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

  void reset() {
    hp = 100;
    maxHp = 100;
    level = 1;
    currentXp = 0;
    targetXp = 100;
    stickDamage = 20;
    position = Vector2(0, 0);
    scale.x = 1;
    paint = _normalPaint;
    _hitCooldown = 0;
    _damageCooldown = 0;
    stickWeapon.opacity = 0;
    skillEffect.opacity = 0;
    _isSkillActive = false;
  }

  void gainXp(double amount) {
    currentXp += amount;
    while (currentXp >= targetXp) {
      currentXp -= targetXp;
      level++;
      targetXp *= 1.5;
      stickDamage += 10;
      maxHp += 20; // Increase max HP on level up
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
    if (_hitCooldown > 0) return;

    hp -= amount;
    _hitCooldown = 0.2;
    paint = _damagePaint;

    if (hp <= 0) {
      hp = 0;
      gameRef.pauseEngine();
      gameRef.overlays.add('GameOver');
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
      if (_hitCooldown <= 0) paint = _normalPaint;
    }

    // Weapon Logic
    _handleWeaponLogic(dt);

    // Skill Logic
    if (_isSkillActive) {
      _updateSkill(dt);
    }
  }

  void _handleWeaponLogic(double dt) {
    bool enemyInDetectionRange = false;
    for (final child in gameRef.world.children) {
      if (child is Enemy) {
        if (position.distanceTo(child.position) < 100) {
          enemyInDetectionRange = true;
          break;
        }
      }
    }

    if (enemyInDetectionRange) {
      stickWeapon.opacity = 1;
      _attackTimer += dt * 10;
      stickWeapon.angle = sin(_attackTimer) * 0.5;
    } else {
      stickWeapon.opacity = 0;
      _attackTimer = 0;
    }

    if (isAttacking && _damageCooldown <= 0) {
      bool hitSomeone = false;
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
        _damageCooldown = 0.5;
      }
    }
  }

  void _updateSkill(double dt) {
    _skillTimer -= dt;
    skillEffect.angle += dt * 10;
    for (final child in gameRef.world.children.toList()) {
      if (child is Enemy) {
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
  static final Vector2 enemySize = Vector2(35, 56); // 70% of 50x80

  final Paint _normalPaint = BasicPalette.purple.paint();
  final Paint _damagePaint = BasicPalette.red.paint();
  final Paint _weaponPaint = BasicPalette.red.paint();

  // Health
  double maxHp = 40;
  double hp = 40;
  double speed = 100;
  double attackRange = 70;
  double damage = 5;

  double _damageTimer = 0;
  double _attackCooldown = 0;
  double _swingTimer = 0;
  double _hitCooldown = 0;

  late final Weapon weaponVisual;

  bool get isAttacking => weaponVisual.opacity > 0;

  Enemy({required Vector2 position, int levelScale = 1})
      : super(
          position: position,
          size: enemySize,
          anchor: Anchor.bottomCenter,
        ) {
     paint = _normalPaint;
     // Scaling: 40 * (1 + level * 0.1) as per memory, but user prompt says "Scales with level"
     // Prompt: "Enemy Max HP: 40 (Scales with level)."
     maxHp = 40.0 * (1.0 + (levelScale * 0.1));
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
    _hitCooldown = 0.2;
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

    if (_damageTimer > 0) {
      _damageTimer -= dt;
      if (_damageTimer <= 0) paint = _normalPaint;
    }
    if (_hitCooldown > 0) _hitCooldown -= dt;

    // AI
    final player = gameRef.player;
    // Simple check if player is alive (though engine pauses on game over)
    if (player.hp <= 0) return;

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

    if (_attackCooldown <= 0) {
      if (weaponVisual.toAbsoluteRect().overlaps(player.toAbsoluteRect())) {
         player.takeDamage(damage);
         _attackCooldown = 1.0;
      }
    }
  }
}

class Rock extends CircleComponent {
  Rock({required Vector2 position})
      : super(
          radius: 30,
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
    size: Vector2(35, 5), // Adjusted to fit new width (was 50)
  );

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _barBackPaint);
    final enemy = ancestor;
    double hpPercent = 0;
    if (enemy.maxHp > 0) hpPercent = enemy.hp / enemy.maxHp;
    if (hpPercent < 0) hpPercent = 0;

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
    position: Vector2(20, 120),
    size: Vector2(200, 20),
  );

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _barBackPaint);
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
    position: Vector2(20, 100),
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
