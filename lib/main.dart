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

enum WeaponType {
  dagger,
  sword,
  axe;

  String get name => toString().split('.').last.toUpperCase();

  double get range {
    switch (this) {
      case WeaponType.dagger:
        return 60;
      case WeaponType.sword:
        return 100;
      case WeaponType.axe:
        return 130;
    }
  }

  double get speed {
    switch (this) {
      case WeaponType.dagger:
        return 0.2;
      case WeaponType.sword:
        return 0.5;
      case WeaponType.axe:
        return 1.0;
    }
  }

  double get damage {
    switch (this) {
      case WeaponType.dagger:
        return 10;
      case WeaponType.sword:
        return 20;
      case WeaponType.axe:
        return 45;
    }
  }

  Vector2 get size {
    switch (this) {
      case WeaponType.dagger:
        return Vector2(30, 8);
      case WeaponType.sword:
        return Vector2(60, 10);
      case WeaponType.axe:
        return Vector2(80, 20);
    }
  }

  Paint get paint {
    switch (this) {
      case WeaponType.dagger:
        return BasicPalette.gray.paint();
      case WeaponType.sword:
        return BasicPalette.brown.paint();
      case WeaponType.axe:
        return BasicPalette.darkRed.paint();
    }
  }
}

class VanguardGame extends FlameGame with HasCollisionDetection {
  late final Player player;
  late final JoystickComponent joystick;
  late final HudButtonComponent skillButton;
  late final HudButtonComponent attackButton; // Manual Attack
  late final HudButtonComponent autoToggleBtn; // Auto Toggle
  late final TextComponent autoToggleText;
  late final TextComponent distanceText;
  late final TextComponent xpLevelText;
  late final XpBarComponent xpBar;
  late final PlayerHealthBar playerHealthBar;

  // Spawning State
  final Random _random = Random();
  double _spawnTimer = 0;

  @override
  Future<void> onLoad() async {
    // 1. Create the Player
    player = Player(position: Vector2(0, 0));
    world.add(player);

    // 2. Setup HUD
    // Joystick
    final knobPaint = BasicPalette.blue.withAlpha(200).paint();
    final backgroundPaint = BasicPalette.blue.withAlpha(100).paint();
    joystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: knobPaint),
      background: CircleComponent(radius: 50, paint: backgroundPaint),
      margin: const EdgeInsets.only(left: 40, bottom: 40),
    );

    // Skill Button (Small Red)
    skillButton = HudButtonComponent(
      button: CircleComponent(
        radius: 30, // 60px size
        paint: BasicPalette.red.withAlpha(200).paint(),
      ),
      margin: const EdgeInsets.only(right: 140, bottom: 40),
      onPressed: () {
        player.triggerSkill();
      },
    );

    // Manual Attack Button (Large Orange)
    attackButton = HudButtonComponent(
      button: CircleComponent(
        radius: 40, // 80px size
        paint: BasicPalette.orange.withAlpha(200).paint(),
      ),
      margin: const EdgeInsets.only(right: 40, bottom: 30),
      onPressed: () {
        player.startAttack();
      },
    );

    // Auto Toggle Button (Top Right)
    autoToggleText = TextComponent(
      text: 'AUTO: ON',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.green,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(blurRadius: 2, color: Colors.black, offset: Offset(1,1))],
        ),
      ),
      anchor: Anchor.center,
    );

    autoToggleBtn = HudButtonComponent(
      button: RectangleComponent(
        size: Vector2(120, 40),
        paint: BasicPalette.black.withAlpha(150).paint(),
        children: [
            autoToggleText..position = Vector2(60, 20),
        ]
      ),
      margin: const EdgeInsets.only(right: 20, top: 20),
      onPressed: () {
        player.toggleAutoAttack();
        _updateAutoText();
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

    // XP Level Text
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

    // XP Bar
    xpBar = XpBarComponent(player: player);

    // Player Health Bar
    playerHealthBar = PlayerHealthBar(player: player);

    // Add HUD elements
    camera.viewport.add(joystick);
    camera.viewport.add(skillButton);
    camera.viewport.add(attackButton);
    camera.viewport.add(autoToggleBtn);
    camera.viewport.add(distanceText);
    camera.viewport.add(xpLevelText);
    camera.viewport.add(xpBar);
    camera.viewport.add(playerHealthBar);

    // Setup Camera
    camera.viewfinder.anchor = Anchor.center;
  }

  void _updateAutoText() {
    if (player.autoAttackEnabled) {
      autoToggleText.text = "AUTO: ON";
      autoToggleText.textRenderer = TextPaint(
        style: const TextStyle(
          color: Colors.green,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(blurRadius: 2, color: Colors.black, offset: Offset(1, 1))],
        ),
      );
    } else {
      autoToggleText.text = "AUTO: OFF";
      autoToggleText.textRenderer = TextPaint(
        style: const TextStyle(
          color: Colors.red,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(blurRadius: 2, color: Colors.black, offset: Offset(1, 1))],
        ),
      );
    }
  }

  void resetGame() {
    player.reset();
    _updateAutoText();

    // Remove all spawned entities
    for (final child in world.children.toList()) {
      if (child is Enemy || child is Rock || child is DamageText || child is LevelUpText || child is LootBox) {
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
    camera.viewfinder.position = Vector2(player.position.x, 0);

    // 2. Update HUD
    distanceText.text = 'Distance: ${(player.position.x / 10).toInt()}m';
    xpLevelText.text = 'Lvl ${player.level}';

    // 3. Spawning
    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _spawnEntity();
      _spawnTimer = 1.5 + _random.nextDouble() * 0.5;
    }

    // 4. Cleanup
    for (final child in world.children.toList()) {
      if (child is Enemy || child is Rock || child is LootBox) {
        if ((child as PositionComponent).position.x < player.position.x - 1000) {
          child.removeFromParent();
        }
      }
    }
  }

  void _spawnEntity() {
    final viewportWidth = camera.viewport.size.x;
    final spawnX = player.position.x + viewportWidth / 2 + 100;
    final spawnY = -150 + _random.nextDouble() * 300;
    final spawnPos = Vector2(spawnX, spawnY);

    if (_random.nextDouble() < 0.7) {
      world.add(Enemy(position: spawnPos, levelScale: player.level));
    } else {
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
  static final Vector2 playerSize = Vector2(35, 56);

  // Stats
  int level = 1;
  double currentXp = 0;
  double targetXp = 100;

  // Weapon Stats
  WeaponType equippedWeapon = WeaponType.sword;
  double baseDamage = 0; // Damage comes from weapon + level bonus

  double maxHp = 100;
  double hp = 100;
  bool autoAttackEnabled = true;

  // Visuals
  final Paint _normalPaint = BasicPalette.white.paint();
  final Paint _damagePaint = BasicPalette.red.paint();

  // Child Components
  late final Weapon stickWeapon;
  late final CircleComponent skillEffect;

  // State
  double _attackAnimTimer = 0;
  bool _isAttacking = false;
  double _damageCooldown = 0;
  double _hitCooldown = 0;

  double _skillTimer = 0;
  bool _isSkillActive = false;
  final Set<Enemy> _skillHitTargets = {};
  final Set<Enemy> _swingHitTargets = {}; // Track who we hit this swing

  Player({required Vector2 position})
      : super(
          position: position,
          size: playerSize,
          anchor: Anchor.bottomCenter,
        );

  @override
  Future<void> onLoad() async {
    paint = _normalPaint;

    // Initial Weapon
    stickWeapon = Weapon(
      size: equippedWeapon.size,
      paint: equippedWeapon.paint,
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
    baseDamage = 0;
    equipWeapon(WeaponType.sword);
    autoAttackEnabled = true;

    position = Vector2(0, 0);
    scale.x = 1;
    paint = _normalPaint;
    _hitCooldown = 0;
    _damageCooldown = 0;
    _isAttacking = false;
    stickWeapon.opacity = 0;
    skillEffect.opacity = 0;
    _isSkillActive = false;
  }

  void toggleAutoAttack() {
    autoAttackEnabled = !autoAttackEnabled;
  }

  void equipWeapon(WeaponType type) {
    equippedWeapon = type;
    stickWeapon.size = type.size;
    stickWeapon.paint = type.paint;
    gameRef.world.add(
        LevelUpText(
          position: position.clone()..y -= 60,
          text: "Equipped ${type.name}!",
          color: Colors.white,
        )
    );
  }

  void gainXp(double amount) {
    currentXp += amount;
    while (currentXp >= targetXp) {
      currentXp -= targetXp;
      level++;
      targetXp *= 1.5;
      maxHp += 20;
      hp = maxHp;
      gameRef.world.add(
        LevelUpText(
          position: position.clone()..y -= 80,
          text: "LEVEL UP!",
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

  void startAttack() {
    if (_isAttacking) return;
    _isAttacking = true;
    _attackAnimTimer = 0;
    stickWeapon.opacity = 1;
    _swingHitTargets.clear(); // Reset hit targets for this new swing
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

    // Auto Attack Logic
    if (autoAttackEnabled && !_isAttacking && _damageCooldown <= 0) {
      bool enemyInRange = false;
      for (final child in gameRef.world.children) {
        if (child is Enemy) {
          if (position.distanceTo(child.position) < equippedWeapon.range) {
            enemyInRange = true;
            break;
          }
        }
      }
      if (enemyInRange) {
        startAttack();
      }
    }

    // Weapon Animation & Hit Logic
    if (_isAttacking) {
        _handleWeaponAnimation(dt);
    }

    // Skill Logic
    if (_isSkillActive) {
      _updateSkill(dt);
    }

    // Check for Loot Pickup
    // Use toList to safely remove components during iteration
    for (final child in gameRef.world.children.toList()) {
      if (child is LootBox) {
        if (toAbsoluteRect().overlaps(child.toAbsoluteRect())) {
          child.pickup(this);
        }
      }
    }
  }

  void _handleWeaponAnimation(double dt) {
    _attackAnimTimer += dt;

    // Simple Swing
    // 0 to speed
    double progress = _attackAnimTimer / equippedWeapon.speed;
    if (progress > 1.0) {
      _isAttacking = false;
      stickWeapon.opacity = 0;
      // Set cooldown based on weapon speed
      _damageCooldown = equippedWeapon.speed * 0.5; // Small recovery
      return;
    }

    // Animate angle: Sweep from -pi/4 to +pi/4
    stickWeapon.angle = -pi / 4 + (pi / 2 * sin(progress * pi));

    // Hit Logic
    // Only deal damage once per swing per enemy
    for (final child in gameRef.world.children.toList()) {
      if (child is Enemy) {
        if (stickWeapon.toAbsoluteRect().overlaps(child.toAbsoluteRect())) {
           if (!_swingHitTargets.contains(child) && child.canTakeDamage) {
             double totalDmg = equippedWeapon.damage + ((level - 1) * 5.0);
             child.takeDamage(totalDmg);
             _swingHitTargets.add(child);
           }
        }
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
  static final Vector2 enemySize = Vector2(35, 56);

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
  bool get canTakeDamage => _hitCooldown <= 0;

  Enemy({required Vector2 position, int levelScale = 1})
      : super(
          position: position,
          size: enemySize,
          anchor: Anchor.bottomCenter,
        ) {
     paint = _normalPaint;
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
    _hitCooldown = 0.5; // Enemy i-frame to prevent instant melt
    takeDamageEffect();

    gameRef.world.add(
      DamageText(
        amount.toInt().toString(),
        position - Vector2(0, size.y),
      )
    );

    if (hp <= 0) {
      _dropLoot();
      removeFromParent();
      gameRef.player.gainXp(35);
    }
  }

  void _dropLoot() {
    final rng = Random();
    if (rng.nextDouble() < 0.25) { // 25% chance
      gameRef.world.add(LootBox(position: position.clone()));
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
    if (player.hp <= 0) return;

    final dist = position.distanceTo(player.position);

    if (player.position.x < position.x) {
      scale.x = -1;
    } else {
      scale.x = 1;
    }

    if (dist > attackRange) {
      final dir = (player.position - position).normalized();
      position.add(dir * speed * dt);
      weaponVisual.opacity = 0;
      _swingTimer = 0;
    } else {
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

class LootBox extends RectangleComponent {
  LootBox({required Vector2 position}) : super(
    position: position,
    size: Vector2(30, 30),
    anchor: Anchor.center,
    paint: Paint()..color = const Color(0xFFFFD700), // Gold
  );

  @override
  void update(double dt) {
    super.update(dt);
    priority = position.y.toInt() - 1; // Behind characters
  }

  void pickup(Player player) {
    // Random Weapon
    final type = WeaponType.values[Random().nextInt(WeaponType.values.length)];
    player.equipWeapon(type);
    removeFromParent();
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
    size: Vector2(35, 5),
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
  LevelUpText({required Vector2 position, String text = "LEVEL UP!", Color color = Colors.yellow})
      : super(
          text: text,
          position: position,
          textRenderer: TextPaint(
            style: TextStyle(
              color: color,
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
