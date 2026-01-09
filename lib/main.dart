import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/palette.dart';
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

  // Systems
  double _spawnTimer = 0;
  final Random _rnd = Random();
  bool isGameOver = false;

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;

    // --- HUD SETUP ---
    final knobPaint = BasicPalette.white.withAlpha(200).paint();
    final backgroundPaint = BasicPalette.white.withAlpha(50).paint();

    // 1. Controls
    joystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: knobPaint),
      background: CircleComponent(radius: 50, paint: backgroundPaint),
      margin: const EdgeInsets.only(left: 40, bottom: 40),
    );

    // Manual Attack (Red)
    final attackButton = HudButtonComponent(
      button: CircleComponent(radius: 35, paint: BasicPalette.red.withAlpha(200).paint()),
      margin: const EdgeInsets.only(right: 40, bottom: 20),
      onPressed: () => player.startAttack(),
      children: [
        TextComponent(
          text: "ATK",
          textRenderer: TextPaint(style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          position: Vector2(22, 25), // Approx center
          anchor: Anchor.center,
        )
      ]
    );

    // Skill Button (Blue) with Label
    final skillButton = HudButtonComponent(
      button: CircleComponent(radius: 25, paint: BasicPalette.cyan.withAlpha(200).paint()),
      margin: const EdgeInsets.only(right: 40, bottom: 100),
      onPressed: () => player.activateSkill(),
      children: [
        TextComponent(
          text: "SWIRL",
          textRenderer: TextPaint(style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
          position: Vector2(25, 25),
          anchor: Anchor.center,
        )
      ]
    );

    // Auto Toggle (Top Right)
    final autoButton = HudButtonComponent(
      button: RectangleComponent(size: Vector2(100, 40), paint: BasicPalette.black.withAlpha(150).paint()),
      margin: const EdgeInsets.only(right: 20, top: 20),
      onPressed: toggleAuto,
    );
    autoText = TextComponent(
      text: "AUTO: ON",
      textRenderer: TextPaint(style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
      position: Vector2(50, 20),
      anchor: Anchor.center,
    );
    autoButton.button!.add(autoText);

    // 2. Inventory UI (Top Center)
    inventoryDisplay = InventoryDisplay();

    // 3. Stats UI (Top Left)
    distanceText = TextComponent(
      text: 'Distance: 0m',
      position: Vector2(20, 20),
      textRenderer: TextPaint(style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    );

    xpLevelText = TextComponent(
      text: 'Lvl 1',
      position: Vector2(20, 40),
      textRenderer: TextPaint(style: const TextStyle(color: Colors.yellow, fontSize: 16, fontWeight: FontWeight.bold)),
    );

    // --- WORLD ---
    player = Player(joystick, floorBounds: Vector2(200, 600));

    add(player);
    add(joystick);
    add(attackButton);
    add(skillButton);
    add(autoButton);
    add(inventoryDisplay);
    add(distanceText);
    add(xpLevelText);
    // Note: PlayerHealthBar and XpBarComponent logic can be simple rectangles added to HUD or Player.
    // Given the Player has a health bar on themselves (no, Enemy has it), we should add a HUD health bar.
    add(PlayerHealthBar(player: player));
    add(XpBarComponent(player: player));

    // Initial Spawns
    spawnInitialObjects();
  }

  void spawnInitialObjects() {
    for(int i=0; i<5; i++) {
      add(Rock(position: Vector2(i * 150 + 300, 300 + _rnd.nextDouble() * 200)));
    }
  }

  void toggleAuto() {
    player.autoAttackEnabled = !player.autoAttackEnabled;
    if(player.autoAttackEnabled) {
      autoText.text = "AUTO: ON";
      autoText.textRenderer = TextPaint(style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold));
    } else {
      autoText.text = "AUTO: OFF";
      autoText.textRenderer = TextPaint(style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isGameOver) return;

    // Camera & HUD Sync
    double targetX = player.position.x - 100;
    if (targetX < 0) targetX = 0;
    camera.viewfinder.position = Vector2(targetX, 0);

    // Simple HUD Movement (Lock to screen)
    Vector2 cam = camera.viewfinder.position;
    joystick.position = cam + Vector2(80, size.y - 80);
    inventoryDisplay.position = cam + Vector2(size.x / 2 - 125, 20); // Center Top
    distanceText.position = cam + Vector2(20, 20);
    xpLevelText.position = cam + Vector2(20, 45);

    // Update Text
    distanceText.text = 'Distance: ${(player.position.x / 10).toInt()}m';
    xpLevelText.text = 'Lvl ${player.level}';

    // Spawning Logic
    _spawnTimer += dt;
    if (_spawnTimer > 2.0) {
      _spawnTimer = 0;
      double spawnX = player.position.x + size.x + 100;
      double spawnY = 200 + _rnd.nextDouble() * (size.y - 250);

      if (_rnd.nextDouble() < 0.6) {
        add(Enemy(position: Vector2(spawnX, spawnY), hpScale: 1.0 + (player.level * 0.1)));
      } else {
        add(Rock(position: Vector2(spawnX, spawnY)));
      }
    }

    // Cleanup
    // Iterate over a copy to avoid ConcurrentModificationError
    for (final child in children.toList()) {
       if (child is PositionComponent && child != player && child != joystick) {
         // Only remove if it's part of the world (not HUD)
         // But here HUD elements are also PositionComponents added to game.
         // HUD elements move with camera, so their position relative to camera is fixed,
         // but their absolute position updates.
         // However, in this implementation:
         // joystick.position = cam + ...
         // So joystick moves forward.
         // We need to differentiate world objects (Enemy, Rock, LootBox) from HUD.
         if (child is Enemy || child is Rock || child is LootBox) {
            if (child.position.x < player.position.x - size.x) child.removeFromParent();
         }
       }
    }
  }
}

// ================= INVENTORY UI =================
class InventoryDisplay extends PositionComponent with HasGameRef<VanguardGame> {
  // 5x5 Grid + 1 Equipped Slot
  late RectangleComponent equippedSlot;
  late TextComponent equippedLabel;
  final List<InventorySlot> gridSlots = [];

  InventoryDisplay() : super(size: Vector2(350, 150)); // Container Size

  @override
  Future<void> onLoad() async {
    // 1. Equipped Slot (Left side)
    add(TextComponent(text: "EQUIPPED", position: Vector2(0, 0), textRenderer: TextPaint(style: const TextStyle(fontSize: 10, color: Colors.white))));
    equippedSlot = RectangleComponent(
      position: Vector2(0, 15),
      size: Vector2(40, 40),
      paint: Paint()..color = const Color(0xFF444444), // Dark Gray
    );
    add(equippedSlot);

    // 2. The 5x5 Grid (Right side)
    double startX = 60;
    double startY = 0;
    double boxSize = 25;
    double gap = 5;

    for (int row = 0; row < 5; row++) {
      for (int col = 0; col < 5; col++) {
        final slot = InventorySlot(
          index: (row * 5) + col,
          position: Vector2(startX + (col * (boxSize + gap)), startY + (row * (boxSize + gap))),
          size: Vector2(boxSize, boxSize),
        );
        add(slot);
        gridSlots.add(slot);
      }
    }
  }

  void updateInventoryVisuals() {
    // Update Equipped
    final weapon = gameRef.player.currentWeapon;
    equippedSlot.children.whereType<RectangleComponent>().forEach((c) => c.removeFromParent());
    equippedSlot.add(_getWeaponIcon(weapon, Vector2(20, 20)));

    // Update Grid
    final invList = gameRef.player.inventory.toList();
    for (int i = 0; i < gridSlots.length; i++) {
      gridSlots[i].clearIcon();
      if (i < invList.length) {
        gridSlots[i].setWeapon(invList[i]);
      }
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

  InventorySlot({required this.index, required Vector2 position, required Vector2 size})
      : super(position: position, size: size, paint: BasicPalette.gray.withAlpha(100).paint());

  void setWeapon(WeaponType type) {
    storedWeapon = type;
    // Add icon
    Paint p;
    switch(type) {
      case WeaponType.dagger: p = BasicPalette.yellow.paint(); break;
      case WeaponType.sword: p = BasicPalette.brown.paint(); break;
      case WeaponType.axe: p = BasicPalette.red.paint(); break;
    }
    add(RectangleComponent(size: size * 0.6, paint: p, anchor: Anchor.center, position: size/2));
  }

  void clearIcon() {
    storedWeapon = null;
    children.whereType<RectangleComponent>().forEach((c) => c.removeFromParent());
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (storedWeapon != null) {
      // Equip this weapon
      gameRef.player.equipWeapon(storedWeapon!);
    }
  }
}

// ================= PLAYER =================
class Player extends PositionComponent with HasGameRef<VanguardGame> {
  final JoystickComponent joystick;
  final Vector2 floorBounds;

  // Inventory
  Set<WeaponType> inventory = { WeaponType.sword }; // Start with sword
  WeaponType currentWeapon = WeaponType.sword;

  // Stats
  int level = 1;
  double currentXp = 0;
  double targetXp = 100;
  double maxHp = 100;
  late double currentHp;

  // Combat Stats
  double damage = 20;
  double attackSpeed = 0.5;
  double range = 100;
  bool autoAttackEnabled = true;

  // Visuals
  final double moveSpeed = 250;
  late RectangleComponent bodyVisual;
  late RectangleComponent stickWeapon;
  late CircleComponent swirlEffect;

  // State
  bool isAttacking = false;
  bool isSwirling = false;
  double _swingTimer = 0;
  double _damageCooldown = 0;
  Vector2 facingDirection = Vector2(1, 0);

  Player(this.joystick, {required this.floorBounds})
      : super(size: Vector2(60, 90), anchor: Anchor.bottomCenter) {
    position = Vector2(100, 300);
    currentHp = maxHp;
  }

  void collectLoot(WeaponType newWeapon) {
    if (!inventory.contains(newWeapon)) {
      inventory.add(newWeapon);
      gameRef.add(DamageText("Found ${newWeapon.name}!", position: position.clone()..y -= 80, color: const Color(0xFFFFD700)));
      // Update UI
      gameRef.inventoryDisplay.updateInventoryVisuals();
    } else {
      gameRef.add(DamageText("Duplicate Discarded", position: position.clone()..y -= 80, color: Colors.grey));
    }
  }

  void equipWeapon(WeaponType type) {
    currentWeapon = type;
    switch (type) {
      case WeaponType.dagger:
        damage = 10; attackSpeed = 0.2; range = 60;
        stickWeapon.size = Vector2(40, 5); stickWeapon.paint = BasicPalette.yellow.paint();
        break;
      case WeaponType.sword:
        damage = 20; attackSpeed = 0.5; range = 100;
        stickWeapon.size = Vector2(60, 10); stickWeapon.paint = BasicPalette.brown.paint();
        break;
      case WeaponType.axe:
        damage = 45; attackSpeed = 1.0; range = 130;
        stickWeapon.size = Vector2(80, 15); stickWeapon.paint = BasicPalette.red.paint();
        break;
    }
    gameRef.inventoryDisplay.updateInventoryVisuals();
  }

  void startAttack() {
    if (isAttacking || isSwirling) return;
    isAttacking = true;
    _swingTimer = 0;
    stickWeapon.opacity = 1;
  }

  void gainXp(double amount) {
    currentXp += amount;
    while (currentXp >= targetXp) {
      currentXp -= targetXp;
      level++;
      targetXp *= 1.5;
      maxHp += 20;
      currentHp = maxHp;
      gameRef.add(
        LevelUpText(
          position: position.clone()..y -= 80,
        )
      );
    }
  }

  @override
  Future<void> onLoad() async {
    bodyVisual = RectangleComponent(size: size, paint: BasicPalette.green.paint());
    stickWeapon = RectangleComponent(size: Vector2(60, 10), paint: BasicPalette.brown.paint(), anchor: Anchor.centerLeft, position: Vector2(size.x/2+10, size.y/2), angle: -pi/4)..opacity = 0;
    swirlEffect = CircleComponent(radius: 200, anchor: Anchor.center, position: size/2, paint: BasicPalette.cyan.withAlpha(100).paint())..opacity = 0;

    add(bodyVisual);
    add(stickWeapon);
    add(swirlEffect);

    // Init UI
    Future.delayed(Duration.zero, () => gameRef.inventoryDisplay.updateInventoryVisuals());
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_damageCooldown > 0) _damageCooldown -= dt;

    // Move
    if (!joystick.delta.isZero()) {
      position.add(joystick.relativeDelta * moveSpeed * dt);
      if (joystick.relativeDelta.x > 0.1) facingDirection = Vector2(1, 0);
      if (joystick.relativeDelta.x < -0.1) facingDirection = Vector2(-1, 0);
    }
    scale.x = facingDirection.x;
    if (position.x < 0) position.x = 0;
    position.y = position.y.clamp(floorBounds.x, gameRef.size.y - 50);
    priority = position.y.toInt();

    // Loot Check
    // Use safe iteration if modifying parent, but here we call pickup() which modifies parent (LootBox).
    // So we should iterate over copy of children.
    for (final child in gameRef.children.toList()) {
      if (child is LootBox && child.toAbsoluteRect().overlaps(bodyVisual.toAbsoluteRect())) {
        child.pickup();
      }
    }

    // Attack
    if (!isSwirling) {
      if (isAttacking) {
        _swingTimer += dt;
        double progress = _swingTimer / attackSpeed;
        stickWeapon.angle = -pi/4 + (sin(progress * pi) * pi/2);

        // Hitbox check during active swing part
        if (progress > 0.2 && progress < 0.8) {
           for (final child in gameRef.children.toList()) {
            if (child is Enemy) {
              if (stickWeapon.toAbsoluteRect().overlaps(child.bodyVisual.toAbsoluteRect())) {
                 child.takeDamage(damage * dt * 5);
              }
            }
          }
        }
        if (_swingTimer >= attackSpeed) {
          isAttacking = false;
          stickWeapon.opacity = 0;
        }
      } else if (autoAttackEnabled) {
        // Auto Trigger
        for (final child in gameRef.children) {
          if (child is Enemy && position.distanceTo(child.position) < range) {
            startAttack();
            break;
          }
        }
      }
    } else {
      swirlEffect.angle += dt * 15;
    }
  }

  void activateSkill() {
    if (isSwirling) return;
    isSwirling = true;
    isAttacking = false;
    stickWeapon.opacity = 0;
    swirlEffect.opacity = 1;

    for (final child in gameRef.children.toList()) {
      if (child is Enemy && position.distanceTo(child.position) <= 200) {
           child.takeDamage(100);
      }
    }
    Future.delayed(const Duration(milliseconds: 800), () {
      isSwirling = false;
      swirlEffect.opacity = 0;
    });
  }

  void takeDamage(double amount) {
    if (_damageCooldown > 0) return;
    currentHp -= amount;
    _damageCooldown = 0.5;
    bodyVisual.paint = BasicPalette.red.paint();
    Future.delayed(const Duration(milliseconds: 200), () => bodyVisual.paint = BasicPalette.green.paint());
    gameRef.add(DamageText("-${amount.toInt()}", position: position.clone()..y -= 50, color: Colors.red));

    if (currentHp <= 0) {
      gameRef.isGameOver = true;
      gameRef.add(
        TextComponent(
          text: "GAME OVER",
          textRenderer: TextPaint(style: const TextStyle(fontSize: 48, color: Colors.red, fontWeight: FontWeight.bold)),
          position: gameRef.camera.viewfinder.position + Vector2(gameRef.size.x/2, gameRef.size.y/2),
          anchor: Anchor.center,
        )
      );
    }
  }
}

// ================= ENEMY =================
class Enemy extends PositionComponent with HasGameRef<VanguardGame> {
  double maxHp = 40;
  late double currentHp;
  late RectangleComponent bodyVisual;
  late RectangleComponent weaponVisual;
  final double hpScale;
  final double moveSpeed = 60;
  bool isAttacking = false;
  double _attackTimer = 0;
  double _damageCooldown = 0;

  Enemy({required Vector2 position, this.hpScale = 1.0})
      : super(position: position, size: Vector2(60, 90), anchor: Anchor.bottomCenter) {
    maxHp = 40 * hpScale;
    currentHp = maxHp;
  }

  late RectangleComponent hpBar;

  @override
  Future<void> onLoad() async {
    bodyVisual = RectangleComponent(size: size, paint: BasicPalette.purple.paint());
    weaponVisual = RectangleComponent(size: Vector2(50, 8), paint: BasicPalette.red.paint(), anchor: Anchor.centerLeft, position: Vector2(size.x/2 - 10, size.y/2), angle: -pi/4)..opacity = 0;

    // Health Bars
    add(RectangleComponent(position: Vector2(0, -10), size: Vector2(60, 6), paint: BasicPalette.red.paint()));
    hpBar = RectangleComponent(position: Vector2(0, -10), size: Vector2(60, 6), paint: BasicPalette.green.paint());
    add(hpBar);

    add(bodyVisual);
    add(weaponVisual);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_damageCooldown > 0) _damageCooldown -= dt;
    priority = position.y.toInt();

    // HP Bar Update
    hpBar.size.x = 60 * (currentHp / maxHp).clamp(0.0, 1.0);

    double dist = position.distanceTo(gameRef.player.position);
    if (dist > 70) {
      isAttacking = false;
      weaponVisual.opacity = 0;
      Vector2 direction = (gameRef.player.position - position).normalized();
      position.add(direction * moveSpeed * dt);
      if (direction.x > 0) scale.x = 1; else scale.x = -1;
    } else {
      isAttacking = true;
      weaponVisual.opacity = 1;
      _attackTimer += dt * 10;
      weaponVisual.angle = -pi/5 + (sin(_attackTimer) * pi/3);
      if (weaponVisual.toAbsoluteRect().overlaps(gameRef.player.bodyVisual.toAbsoluteRect())) {
        gameRef.player.takeDamage(5);
      }
    }
  }

  void takeDamage(double amount) {
    if (_damageCooldown > 0) return;
    currentHp -= amount;
    _damageCooldown = 0.2;
    bodyVisual.paint = BasicPalette.white.paint();
    Future.delayed(const Duration(milliseconds: 50), () => bodyVisual.paint = BasicPalette.purple.paint());
    gameRef.add(DamageText("-${amount.toInt()}", position: position.clone()..y -= 60));

    if (currentHp <= 0) {
      gameRef.player.gainXp(35);
      if (Random().nextDouble() < 0.25) gameRef.add(LootBox(position: position.clone()));
      removeFromParent();
    }
  }
}

// ================= LOOT =================
class LootBox extends PositionComponent with HasGameRef<VanguardGame> {
  LootBox({required Vector2 position}) : super(position: position, size: Vector2(30, 30), anchor: Anchor.center);
  @override
  Future<void> onLoad() async {
    add(RectangleComponent(size: size, paint: Paint()..color = const Color(0xFFFFD700)));
    add(MoveEffect.by(Vector2(0, -10), EffectController(duration: 1, reverse: true, infinite: true)));
  }
  void pickup() {
    final type = WeaponType.values[Random().nextInt(WeaponType.values.length)];
    gameRef.player.collectLoot(type);
    removeFromParent();
  }
}

// ================= HELPERS =================
class Rock extends PositionComponent {
  Rock({required Vector2 position}) : super(position: position, size: Vector2(50, 30), anchor: Anchor.bottomCenter);
  @override
  Future<void> onLoad() async { add(CircleComponent(size: size, paint: BasicPalette.gray.paint())); }
  @override
  void update(double dt) { super.update(dt); priority = position.y.toInt(); }
}

class DamageText extends TextComponent {
  final Vector2 velocity = Vector2(0, -100);
  double lifeTime = 0.8;
  DamageText(String text, {required Vector2 position, Color color = Colors.white})
      : super(text: text, position: position, textRenderer: TextPaint(style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold, shadows: [const Shadow(blurRadius: 2, color: Colors.black)])));
  @override
  void update(double dt) {
    super.update(dt);
    position.add(velocity * dt);
    lifeTime -= dt;
    if (lifeTime <= 0) removeFromParent();
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

class PlayerHealthBar extends PositionComponent {
  final Player player;
  final Paint _barBackPaint = BasicPalette.gray.paint();
  final Paint _barForePaint = BasicPalette.blue.paint();

  PlayerHealthBar({required this.player}) : super(size: Vector2(150, 15));

  @override
  void update(double dt) {
    super.update(dt);
    // Keep fixed on screen relative to camera is handled by parenting or manual update.
    // Here we act as a HUD element added to game, so we need to move with camera.
    // For simplicity, let's attach to the Stats area.
    position = player.gameRef.camera.viewfinder.position + Vector2(20, 70);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _barBackPaint);
    double hpPercent = 0;
    if (player.maxHp > 0) {
      hpPercent = player.currentHp / player.maxHp;
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

  XpBarComponent({required this.player}) : super(size: Vector2(150, 10));

  @override
  void update(double dt) {
    super.update(dt);
    position = player.gameRef.camera.viewfinder.position + Vector2(20, 90);
  }

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
