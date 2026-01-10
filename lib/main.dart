import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/palette.dart';
import 'package:flame/text.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';
import 'dart:math';

void main() {
  runApp(const GameWidget.controlled(gameFactory: VanguardGame.new));
}

// ================= ENUMS =================
enum WeaponType { dagger, sword, axe }

extension WeaponTypeExtension on WeaponType {
  String get name => toString().split('.').last.toUpperCase();
}

// ================= GAME ENGINE =================
class VanguardGame extends FlameGame with HasCollisionDetection, TapCallbacks {
  late Player player;
  late final JoystickComponent joystick;

  // HUD Elements
  late InventoryDisplay inventoryDisplay;
  late TextComponent autoText;
  late TextComponent distanceText;
  late TextComponent xpLevelText;
  late TextComponent bossWarningText;

  // Systems
  double _spawnTimer = 0;
  double _distanceTraveled = 0;
  double _nextBossDistance = 1000;
  bool _bossActive = false;
  double _time = 0; // Game time accumulator

  final Random _rnd = Random();
  bool isGameOver = false;

  double currentTime() => _time;

  @override
  Future<void> onLoad() async {
    // Camera Setup
    camera.viewfinder.anchor = Anchor.center;

    // --- HUD SETUP ---
    final knobPaint = BasicPalette.white.withAlpha(200).paint();
    final backgroundPaint = BasicPalette.white.withAlpha(50).paint();

    // 1. Controls (Joystick)
    joystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: knobPaint),
      background: CircleComponent(radius: 50, paint: backgroundPaint),
      margin: const EdgeInsets.only(left: 40, bottom: 40),
    );

    // 2. Buttons
    final attackButton = HudButtonComponent(
      button: CircleComponent(radius: 35, paint: BasicPalette.red.withAlpha(200).paint()),
      margin: const EdgeInsets.only(right: 40, bottom: 20),
      onPressed: () => player.startAttack(),
      children: [TextComponent(text: "ATK", position: Vector2(22, 25), anchor: Anchor.center, textRenderer: TextPaint(style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)))]
    );

    final skillButton = HudButtonComponent(
      button: CircleComponent(radius: 25, paint: BasicPalette.cyan.withAlpha(200).paint()),
      margin: const EdgeInsets.only(right: 40, bottom: 100),
      onPressed: () => player.activateSkill(),
      children: [TextComponent(text: "SWIRL", position: Vector2(25, 25), anchor: Anchor.center, textRenderer: TextPaint(style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)))]
    );

    final autoButton = HudButtonComponent(
      button: RectangleComponent(size: Vector2(100, 40), paint: BasicPalette.black.withAlpha(150).paint()),
      margin: const EdgeInsets.only(right: 20, top: 20),
      onPressed: toggleAuto,
    );
    autoText = TextComponent(text: "AUTO: ON", position: Vector2(50, 20), anchor: Anchor.center, textRenderer: TextPaint(style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)));
    autoButton.button!.add(autoText);

    // 3. Inventory & Stats
    inventoryDisplay = InventoryDisplay();
    // Position will be set in onGameResize to ensure centering

    distanceText = TextComponent(text: 'Distance: 0m', position: Vector2(20, 20), textRenderer: TextPaint(style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)));
    xpLevelText = TextComponent(text: 'Lvl 1', position: Vector2(20, 45), textRenderer: TextPaint(style: const TextStyle(color: Colors.yellow, fontSize: 16, fontWeight: FontWeight.bold)));

    bossWarningText = TextComponent(
      text: "WARNING: BOSS APPROACHING!",
      anchor: Anchor.center,
      textRenderer: TextPaint(style: const TextStyle(color: Colors.red, fontSize: 32, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
    )..opacity = 0;

    // --- WORLD ---
    player = Player(joystick, floorBounds: Vector2(200, 600));
    world.add(player);

    // --- VIEWPORT ADDITIONS ---
    camera.viewport.add(joystick);
    camera.viewport.add(attackButton);
    camera.viewport.add(skillButton);
    camera.viewport.add(autoButton);
    camera.viewport.add(inventoryDisplay);
    camera.viewport.add(distanceText);
    camera.viewport.add(xpLevelText);
    camera.viewport.add(PlayerHealthBar(player: player));
    camera.viewport.add(XpBarComponent(player: player));
    camera.viewport.add(bossWarningText);

    spawnInitialObjects();
  }

  // --- RESPONSIVE CAMERA LOGIC ---
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Portrait: Scale to fit 450 width. Landscape: Scale to fit 800 height.
    double zoom;
    if (size.x < size.y) {
      zoom = size.x / 450;
    } else {
      zoom = size.y / 800;
    }
    camera.viewfinder.zoom = zoom;

    // Re-center Inventory UI based on new viewport size
    if (isLoaded) {
      inventoryDisplay.position = Vector2(size.x / 2 - 175, 20); // Center top
      bossWarningText.position = size / 2; // Center screen
    }
  }

  void spawnInitialObjects() {
    for(int i=0; i<5; i++) {
      world.add(Rock(position: Vector2(i * 150 + 300, 300 + _rnd.nextDouble() * 200)));
    }
  }

  void toggleAuto() {
    player.autoAttackEnabled = !player.autoAttackEnabled;
    autoText.text = player.autoAttackEnabled ? "AUTO: ON" : "AUTO: OFF";
    autoText.textRenderer = TextPaint(style: TextStyle(color: player.autoAttackEnabled ? Colors.green : Colors.red, fontWeight: FontWeight.bold));
  }

  @override
  void update(double dt) {
    if (isGameOver) return;
    super.update(dt);
    _time += dt;

    // Camera Tracking (X-Axis only, fixed Y)
    camera.viewfinder.position = Vector2(player.position.x, 300);

    // Update Distance
    if (player.position.x > _distanceTraveled) _distanceTraveled = player.position.x;
    distanceText.text = 'Distance: ${(_distanceTraveled / 10).toInt()}m';
    xpLevelText.text = 'Lvl ${player.level}';

    // --- SPAWNER & BOSS LOGIC ---
    if (!_bossActive) {
      // Check Boss Trigger
      if (_distanceTraveled > _nextBossDistance) {
        triggerBossSequence();
      } else {
        // Normal Spawning
        _spawnTimer += dt;
        if (_spawnTimer > 2.0) {
          _spawnTimer = 0;
          double spawnX = player.position.x + size.x / camera.viewfinder.zoom + 100; // Adjust spawn for zoom
          double spawnY = 200 + _rnd.nextDouble() * 400;

          if (_rnd.nextDouble() < 0.6) {
            world.add(Enemy(position: Vector2(spawnX, spawnY), hpScale: 1.0 + (player.level * 0.1)));
          } else {
            world.add(Rock(position: Vector2(spawnX, spawnY)));
          }
        }
      }
    }

    // Cleanup
    for (final child in world.children.toList()) {
      if (child is PositionComponent && !(child is Player)) {
        if (child.position.x < player.position.x - (size.x / camera.viewfinder.zoom)) {
          child.removeFromParent();
        }
      }
    }
  }

  void triggerBossSequence() {
    _bossActive = true;

    // Flashing Warning
    bossWarningText.opacity = 1;
    bossWarningText.add(
      SequenceEffect([
        OpacityEffect.to(0, EffectController(duration: 0.5)),
        OpacityEffect.to(1, EffectController(duration: 0.5)),
        OpacityEffect.to(0, EffectController(duration: 0.5)),
        OpacityEffect.to(1, EffectController(duration: 0.5)),
        OpacityEffect.to(0, EffectController(duration: 1.0)), // Fade out
      ])
    );

    // Spawn Boss after delay
    Future.delayed(const Duration(seconds: 3), () {
      double spawnX = player.position.x + 400;
      world.add(BossEnemy(position: Vector2(spawnX, 400), hpScale: 1.0 + (player.level * 0.5)));
    });
  }

  void onBossDefeated() {
    _bossActive = false;
    _nextBossDistance += 1000;
    // Loot Explosion
    for(int i=0; i<3; i++) {
       world.add(LootBox(position: player.position + Vector2(_rnd.nextDouble()*100, _rnd.nextDouble()*100)));
    }
  }
}

// ================= BOSS ENEMY =================
class BossEnemy extends Enemy {
  BossEnemy({required Vector2 position, double hpScale = 1.0})
    : super(position: position, hpScale: hpScale * 5.0) { // 5x HP
    maxHp = 500 * hpScale;
    currentHp = maxHp;
  }

  double _chargeTimer = 0;
  bool _isCharging = false;

  @override
  Future<void> onLoad() async {
    // Bigger Visuals
    size = Vector2(120, 120);
    bodyVisual = RectangleComponent(size: size, paint: BasicPalette.red.paint()); // Boss is Red
    weaponVisual = RectangleComponent(size: Vector2(100, 15), paint: BasicPalette.darkRed.paint(), anchor: Anchor.centerLeft, position: Vector2(size.x/2, size.y/2))..opacity = 0;

    // Boss Bar
    add(RectangleComponent(position: Vector2(0, -20), size: Vector2(120, 10), paint: BasicPalette.black.paint()));
    hpBar = RectangleComponent(position: Vector2(0, -20), size: Vector2(120, 10), paint: BasicPalette.red.paint()); // Red HP bar

    add(hpBar);
    add(bodyVisual);
    add(weaponVisual);
  }

  @override
  void update(double dt) {
    // Boss AI: Chase -> Charge
    _damageCooldown -= dt;
    priority = position.y.toInt();
    hpBar.size.x = 120 * (currentHp / maxHp).clamp(0.0, 1.0);

    double dist = position.distanceTo(gameRef.player.position);

    if (!_isCharging) {
      // Phase 1: Slow Chase
      if (dist > 100) {
        Vector2 dir = (gameRef.player.position - position).normalized();
        position.add(dir * 40 * dt); // Slower speed
        scale.x = dir.x > 0 ? 1 : -1;
      }

      _chargeTimer += dt;
      if (_chargeTimer > 5.0) {
        // Start Charge
        _isCharging = true;
        _chargeTimer = 0;
        bodyVisual.paint = BasicPalette.white.paint(); // Flash warning

        // Charge Logic
        Future.delayed(const Duration(seconds: 1), () {
          bodyVisual.paint = BasicPalette.red.paint();
          // Dash towards player
          add(MoveEffect.to(gameRef.player.position, EffectController(duration: 0.5, curve: Curves.easeIn)));
          // Reset
          Future.delayed(const Duration(seconds: 1), () => _isCharging = false);
        });
      }
    }

    // Damage Collision (Contact Damage)
    if (toAbsoluteRect().overlaps(gameRef.player.bodyVisual.toAbsoluteRect())) {
      gameRef.player.takeDamage(1.0); // Constant contact damage
    }
  }

  @override
  void takeDamage(double amount) {
    if (_damageCooldown > 0) return;
    super.takeDamage(amount);
    if (currentHp <= 0) {
      gameRef.onBossDefeated(); // Notify game loop
    }
  }
}

// ================= INVENTORY & UI CLASSES =================
class InventoryDisplay extends PositionComponent with HasGameRef<VanguardGame> {
  late RectangleComponent equippedSlot;
  final List<InventorySlot> gridSlots = [];

  InventoryDisplay() : super(size: Vector2(350, 150));

  @override
  Future<void> onLoad() async {
    add(TextComponent(text: "EQUIPPED", position: Vector2(0, 0), textRenderer: TextPaint(style: const TextStyle(fontSize: 10, color: Colors.white))));
    equippedSlot = RectangleComponent(position: Vector2(0, 15), size: Vector2(40, 40), paint: Paint()..color = const Color(0xFF444444));
    add(equippedSlot);

    double startX = 60, startY = 0, boxSize = 25, gap = 5;
    for (int row = 0; row < 5; row++) {
      for (int col = 0; col < 5; col++) {
        final slot = InventorySlot(index: (row * 5) + col, position: Vector2(startX + (col * (boxSize + gap)), startY + (row * (boxSize + gap))), size: Vector2(boxSize, boxSize));
        add(slot);
        gridSlots.add(slot);
      }
    }
  }

  void updateInventoryVisuals() {
    final weapon = gameRef.player.currentWeapon;
    equippedSlot.children.whereType<RectangleComponent>().forEach((c) => c.removeFromParent());
    equippedSlot.add(_getWeaponIcon(weapon, Vector2(20, 20)));

    final invList = gameRef.player.inventory.toList();
    for (int i = 0; i < gridSlots.length; i++) {
      gridSlots[i].clearIcon();
      if (i < invList.length) gridSlots[i].setWeapon(invList[i]);
    }
  }

  RectangleComponent _getWeaponIcon(WeaponType type, Vector2 center) {
    Paint p;
    Vector2 s;
    switch(type) {
      case WeaponType.dagger: p = BasicPalette.yellow.paint(); s = Vector2(10, 10); break;
      case WeaponType.sword: p = BasicPalette.brown.paint(); s = Vector2(15, 15); break;
      case WeaponType.axe: p = BasicPalette.red.paint(); s = Vector2(20, 20); break;
    }
    return RectangleComponent(size: s, paint: p, anchor: Anchor.center, position: center);
  }
}

class InventorySlot extends RectangleComponent with TapCallbacks, HasGameRef<VanguardGame> {
  final int index;
  WeaponType? storedWeapon;
  InventorySlot({required this.index, required Vector2 position, required Vector2 size}) : super(position: position, size: size, paint: BasicPalette.gray.withAlpha(100).paint());

  void setWeapon(WeaponType type) {
    storedWeapon = type;
    Paint p = (type == WeaponType.dagger) ? BasicPalette.yellow.paint() : (type == WeaponType.sword) ? BasicPalette.brown.paint() : BasicPalette.red.paint();
    add(RectangleComponent(size: size * 0.6, paint: p, anchor: Anchor.center, position: size/2));
  }

  void clearIcon() { storedWeapon = null; children.whereType<RectangleComponent>().forEach((c) => c.removeFromParent()); }
  @override
  void onTapDown(TapDownEvent event) { if (storedWeapon != null) gameRef.player.equipWeapon(storedWeapon!); }
}

// ================= PLAYER =================
class Player extends PositionComponent with HasGameRef<VanguardGame> {
  final JoystickComponent joystick;
  final Vector2 floorBounds;
  Set<WeaponType> inventory = { WeaponType.sword };
  WeaponType currentWeapon = WeaponType.sword;

  int level = 1;
  double currentXp = 0, targetXp = 100, maxHp = 100, currentHp = 100;
  double damage = 20, attackSpeed = 0.5, range = 100;
  bool autoAttackEnabled = true, isAttacking = false, isSwirling = false;

  double _swingTimer = 0, _damageCooldown = 0;
  final Set<Enemy> _hitTargets = {};
  Vector2 facingDirection = Vector2(1, 0);

  late RectangleComponent bodyVisual;
  late RectangleComponent stickWeapon;
  late CircleComponent swirlEffect;

  Player(this.joystick, {required this.floorBounds}) : super(size: Vector2(60, 90), anchor: Anchor.bottomCenter) { position = Vector2(100, 300); }

  void collectLoot(WeaponType newWeapon) {
    if (!inventory.contains(newWeapon)) {
      inventory.add(newWeapon);
      gameRef.inventoryDisplay.updateInventoryVisuals();
      gameRef.world.add(DamageText("Found ${newWeapon.name}!", position: position.clone()..y-=80, color: const Color(0xFFFFD700)));
    }
  }

  void equipWeapon(WeaponType type) {
    currentWeapon = type;
    if(type == WeaponType.dagger) { damage=10; attackSpeed=0.2; range=60; stickWeapon.size=Vector2(40,5); stickWeapon.paint=BasicPalette.yellow.paint(); }
    if(type == WeaponType.sword) { damage=20; attackSpeed=0.5; range=100; stickWeapon.size=Vector2(60,10); stickWeapon.paint=BasicPalette.brown.paint(); }
    if(type == WeaponType.axe) { damage=45; attackSpeed=1.0; range=130; stickWeapon.size=Vector2(80,15); stickWeapon.paint=BasicPalette.red.paint(); }
    gameRef.inventoryDisplay.updateInventoryVisuals();
  }

  void startAttack() { if (!isAttacking && !isSwirling) { isAttacking = true; _swingTimer = 0; stickWeapon.opacity = 1; _hitTargets.clear(); } }

  void gainXp(double amount) {
    currentXp += amount;
    while (currentXp >= targetXp) {
      currentXp -= targetXp;
      level++;
      targetXp *= 1.5;
      maxHp += 20;
      currentHp = maxHp;
      damage += 5;
      gameRef.world.add(LevelUpText(position: position.clone()..y -= 80));
    }
  }

  void activateSkill() {
    if (isSwirling) return;
    isSwirling = true; isAttacking = false; stickWeapon.opacity = 0; swirlEffect.opacity = 1;
    for (final child in gameRef.world.children) { if (child is Enemy && position.distanceTo(child.position) <= 200) child.takeDamage(100); }
    Future.delayed(const Duration(milliseconds: 800), () { isSwirling = false; swirlEffect.opacity = 0; });
  }

  @override
  Future<void> onLoad() async {
    bodyVisual = RectangleComponent(size: size, paint: BasicPalette.green.paint());
    stickWeapon = RectangleComponent(size: Vector2(60, 10), paint: BasicPalette.brown.paint(), anchor: Anchor.centerLeft, position: Vector2(size.x/2+10, size.y/2), angle: -pi/4)..opacity = 0;
    swirlEffect = CircleComponent(radius: 200, anchor: Anchor.center, position: size/2, paint: BasicPalette.cyan.withAlpha(100).paint())..opacity = 0;
    add(bodyVisual); add(stickWeapon); add(swirlEffect);
    Future.delayed(Duration.zero, () => gameRef.inventoryDisplay.updateInventoryVisuals());
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_damageCooldown > 0) _damageCooldown -= dt;

    if (!joystick.delta.isZero()) {
      position.add(joystick.relativeDelta * 250 * dt);
      scale.x = joystick.relativeDelta.x > 0.1 ? 1 : (joystick.relativeDelta.x < -0.1 ? -1 : scale.x);
    }
    position.y = position.y.clamp(floorBounds.x, floorBounds.y);
    priority = position.y.toInt();

    // Loot
    for (final child in gameRef.world.children.toList()) { if (child is LootBox && child.toAbsoluteRect().overlaps(bodyVisual.toAbsoluteRect())) child.pickup(); }

    // Combat
    if (!isSwirling) {
      if (isAttacking) {
        _swingTimer += dt;
        double progress = _swingTimer / attackSpeed;
        stickWeapon.angle = -pi/4 + (sin(progress * pi) * pi/2);
        if (progress > 0.2 && progress < 0.8) {
           for (final child in gameRef.world.children) {
            if (child is Enemy && stickWeapon.toAbsoluteRect().overlaps(child.bodyVisual.toAbsoluteRect()) && !_hitTargets.contains(child)) {
                child.takeDamage(damage); _hitTargets.add(child);
            }
          }
        }
        if (_swingTimer >= attackSpeed) { isAttacking = false; stickWeapon.opacity = 0; }
      } else if (autoAttackEnabled) {
        for (final child in gameRef.world.children) { if (child is Enemy && position.distanceTo(child.position) < range) { startAttack(); break; } }
      }
    } else { swirlEffect.angle += dt * 15; }
  }

  void takeDamage(double amount) {
    if (_damageCooldown > 0) return;
    currentHp -= amount; _damageCooldown = 0.5;
    bodyVisual.paint = BasicPalette.red.paint();
    Future.delayed(const Duration(milliseconds: 200), () => bodyVisual.paint = BasicPalette.green.paint());
    if (currentHp <= 0) gameRef.isGameOver = true;
  }
}

// ================= STANDARD ENEMY =================
class Enemy extends PositionComponent with HasGameRef<VanguardGame> {
  double maxHp = 40, currentHp = 40, _damageCooldown = 0;
  late RectangleComponent bodyVisual, weaponVisual, hpBar;

  Enemy({required Vector2 position, double hpScale = 1.0}) : super(position: position, size: Vector2(60, 90), anchor: Anchor.bottomCenter) {
    maxHp *= hpScale; currentHp = maxHp;
  }

  @override
  Future<void> onLoad() async {
    bodyVisual = RectangleComponent(size: size, paint: BasicPalette.purple.paint());
    weaponVisual = RectangleComponent(size: Vector2(50, 8), paint: BasicPalette.red.paint(), anchor: Anchor.centerLeft, position: Vector2(size.x/2, size.y/2), angle: -pi/4)..opacity = 0;
    hpBar = RectangleComponent(position: Vector2(0, -10), size: Vector2(60, 6), paint: BasicPalette.green.paint());
    add(hpBar); add(bodyVisual); add(weaponVisual); add(RectangleComponent(position: Vector2(0, -10), size: Vector2(60, 6), paint: BasicPalette.red.paint()..style=PaintingStyle.stroke));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_damageCooldown > 0) _damageCooldown -= dt;
    priority = position.y.toInt();
    hpBar.size.x = 60 * (currentHp / maxHp).clamp(0.0, 1.0);

    double dist = position.distanceTo(gameRef.player.position);
    if (dist > 70) {
      Vector2 dir = (gameRef.player.position - position).normalized();
      position.add(dir * 60 * dt);
      scale.x = dir.x > 0 ? 1 : -1;
      weaponVisual.opacity = 0;
    } else {
      weaponVisual.opacity = 1;
      weaponVisual.angle = -pi/5 + (sin(gameRef.currentTime() * 10) * pi/3);
      if (weaponVisual.toAbsoluteRect().overlaps(gameRef.player.bodyVisual.toAbsoluteRect())) gameRef.player.takeDamage(5 * dt);
    }
  }

  void takeDamage(double amount) {
    if (_damageCooldown > 0) return;
    currentHp -= amount; _damageCooldown = 0.2;
    bodyVisual.paint = BasicPalette.white.paint();
    Future.delayed(const Duration(milliseconds: 50), () => bodyVisual.paint = BasicPalette.purple.paint());
    gameRef.world.add(DamageText("-${amount.toInt()}", position: position.clone()..y-=60));
    if (currentHp <= 0) {
      gameRef.player.currentXp += 35;
      gameRef.player.gainXp(0); // Trigger level check
      if (Random().nextDouble() < 0.25) gameRef.world.add(LootBox(position: position.clone()));
      removeFromParent();
    }
  }
}

// ================= HELPERS (Loot, Rock, Text, Bars) =================
class LootBox extends PositionComponent with HasGameRef<VanguardGame> {
  LootBox({required Vector2 position}) : super(position: position, size: Vector2(30, 30), anchor: Anchor.center);
  @override Future<void> onLoad() async { add(RectangleComponent(size: size, paint: Paint()..color = const Color(0xFFFFD700))); add(MoveEffect.by(Vector2(0,-10), EffectController(duration: 1, alternate: true, infinite: true))); }
  void pickup() { gameRef.player.collectLoot(WeaponType.values[Random().nextInt(3)]); removeFromParent(); }
}

class Rock extends PositionComponent {
  Rock({required Vector2 position}) : super(position: position, size: Vector2(50, 30), anchor: Anchor.bottomCenter);
  @override Future<void> onLoad() async { add(CircleComponent(radius: 25, paint: BasicPalette.gray.paint())); }
  @override void update(double dt) { super.update(dt); priority = position.y.toInt(); }
}

class DamageText extends TextComponent {
  DamageText(String text, {required Vector2 position, Color color = Colors.white}) : super(text: text, position: position, textRenderer: TextPaint(style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)));
  @override void update(double dt) { position.y -= 100 * dt; if (position.y < -500) removeFromParent(); } // Simple cleanup
}

class LevelUpText extends TextComponent {
  LevelUpText({required Vector2 position}) : super(text: "LEVEL UP!", position: position, textRenderer: TextPaint(style: const TextStyle(color: Colors.yellow, fontSize: 32, fontWeight: FontWeight.bold)));
  @override Future<void> onLoad() async { add(MoveEffect.by(Vector2(0, -80), EffectController(duration: 2.0))); add(RemoveEffect(delay: 2.0)); }
}

class PlayerHealthBar extends PositionComponent {
  final Player player;
  PlayerHealthBar({required this.player});
  @override void render(Canvas c) {
    c.drawRect(const Rect.fromLTWH(20, 70, 150, 15), BasicPalette.gray.paint());
    c.drawRect(Rect.fromLTWH(20, 70, 150 * (player.currentHp/player.maxHp).clamp(0,1), 15), BasicPalette.blue.paint());
  }
}

class XpBarComponent extends PositionComponent {
  final Player player;
  XpBarComponent({required this.player});
  @override void render(Canvas c) {
    c.drawRect(const Rect.fromLTWH(20, 90, 150, 10), BasicPalette.gray.paint());
    c.drawRect(Rect.fromLTWH(20, 90, 150 * (player.currentXp/player.targetXp).clamp(0,1), 10), BasicPalette.yellow.paint());
  }
}
