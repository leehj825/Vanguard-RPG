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

class Player extends RectangleComponent with HasGameRef<VanguardGame> {
  static const double speed = 200;
  static const double weaponRange = 100;
  static const double skillRange = 150;

  // Stats
  int level = 1;
  double currentXp = 0;
  double targetXp = 100;
  double stickDamage = 10;

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

  void gainXp(double amount) {
    currentXp += amount;
    // Level Up Loop (in case massive XP gain)
    while (currentXp >= targetXp) {
      currentXp -= targetXp;
      level++;
      targetXp *= 1.5;
      stickDamage += 10;

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
             child.takeDamage(stickDamage);
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
