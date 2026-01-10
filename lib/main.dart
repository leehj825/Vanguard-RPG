import 'package:flame/collisions.dart';
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
enum GameState { running, bossWarning, bossBattle }

extension WeaponTypeExtension on WeaponType {
  String get name => toString().split('.').last.toUpperCase();
}

// ================= GAME ENGINE =================
class VanguardGame extends FlameGame with HasCollisionDetection, TapCallbacks {
  late Player player;

  // HUD Elements
  late JoystickComponent joystick;
  late HudButtonComponent attackButton;
  late HudButtonComponent skillButton;
  late HudButtonComponent autoButton;
  late InventoryDisplay inventoryDisplay;
  late TextComponent autoText;
  late TextComponent distanceText;
  late TextComponent xpLevelText;
  late PlayerHealthBar playerHealthBar;
  late XpBarComponent xpBar;

  // Boss Elements
  late TextComponent bossWarningText;
  late BossHealthBar bossHealthBar;
  BossEnemy? currentBoss;

  // Systems
  GameState gameState = GameState.running;
  double _spawnTimer = 0;
  double _bossWarningTimer = 0;
  double _lastBossTriggerX = 0;
  final Random _rnd = Random();
  bool isGameOver = false;

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.center;

    // --- HUD SETUP ---
    final knobPaint = BasicPalette.white.withAlpha(200).paint();
    final backgroundPaint = BasicPalette.white.withAlpha(50).paint();

    // 1. Controls
    joystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: knobPaint),
      background: CircleComponent(radius: 50, paint: backgroundPaint),
    );

    // Manual Attack (Red)
    attackButton = HudButtonComponent(
      button: CircleComponent(radius: 35, paint: BasicPalette.red.withAlpha(200).paint()),
      onPressed: () => player.startAttack(),
      children: [
        TextComponent(
          text: "ATK",
          textRenderer: TextPaint(style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          position: Vector2(22, 25),
          anchor: Anchor.center,
        )
      ]
    );

    // Skill Button (Blue)
    skillButton = HudButtonComponent(
      button: CircleComponent(radius: 25, paint: BasicPalette.cyan.withAlpha(200).paint()),
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

    // Auto Toggle
    autoButton = HudButtonComponent(
      button: RectangleComponent(size: Vector2(100, 40), paint: BasicPalette.black.withAlpha(150).paint()),
      onPressed: toggleAuto,
    );
    autoText = TextComponent(
      text: "AUTO: ON",
      textRenderer: TextPaint(style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
      position: Vector2(50, 20),
      anchor: Anchor.center,
    );
    autoButton.button!.add(autoText);

    // 2. Inventory UI
    inventoryDisplay = InventoryDisplay();

    // 3. Stats UI
    distanceText = TextComponent(
      text: 'Distance: 0m',
      textRenderer: TextPaint(style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    );

    xpLevelText = TextComponent(
      text: 'Lvl 1',
      textRenderer: TextPaint(style: const TextStyle(color: Colors.yellow, fontSize: 16, fontWeight: FontWeight.bold)),
    );

    // 4. Boss UI
    bossWarningText = TextComponent(
      text: "BOSS WARNING",
      textRenderer: TextPaint(style: const TextStyle(color: Colors.red, fontSize: 40, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
      anchor: Anchor.center,
    )..opacity = 0; // Hidden by default

    bossHealthBar = BossHealthBar(game: this); // Hidden by default inside class logic or opacity

    // --- WORLD ---
    player = Player(joystick, floorBounds: Vector2(200, 600));
    world.add(player);

    playerHealthBar = PlayerHealthBar(player: player);
    xpBar = XpBarComponent(player: player);

    // --- HUD (Viewport) ---
    camera.viewport.add(joystick);
    camera.viewport.add(attackButton);
    camera.viewport.add(skillButton);
    camera.viewport.add(autoButton);
    camera.viewport.add(inventoryDisplay);
    camera.viewport.add(distanceText);
    camera.viewport.add(xpLevelText);
    camera.viewport.add(playerHealthBar);
    camera.viewport.add(xpBar);
    camera.viewport.add(bossWarningText);
    camera.viewport.add(bossHealthBar);

    spawnInitialObjects();
    _updateHudPositions(size);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);

    // 1. Responsive Zoom
    // Portrait: width 450. Landscape: height 800.
    bool isPortrait = size.y > size.x;
    double targetZoom = isPortrait ? size.x / 450 : size.y / 800;
    camera.viewfinder.zoom = targetZoom;

    // 2. Responsive HUD Positioning
    if (isLoaded) {
      _updateHudPositions(size);
    }
  }

  void _updateHudPositions(Vector2 size) {
    double margin = 40;

    // Joystick: Bottom Left
    joystick.position = Vector2(margin + 20, size.y - margin - 20);

    // Buttons: Bottom Right
    attackButton.position = Vector2(size.x - 60, size.y - 60);
    skillButton.position = Vector2(size.x - 140, size.y - 60);

    // Auto Toggle: Top Right
    autoButton.position = Vector2(size.x - 120, 20);

    // Inventory: Top Center
    inventoryDisplay.position = Vector2(size.x / 2 - 175, 20);

    // Stats: Top Left
    distanceText.position = Vector2(20, 20);
    xpLevelText.position = Vector2(20, 45);

    // Bars: Below Stats
    playerHealthBar.position = Vector2(20, 70);
    xpBar.position = Vector2(20, 90);

    // Boss Elements: Center / Top
    bossWarningText.position = size / 2;
    bossHealthBar.position = Vector2(size.x / 2 - 200, 80); // Below inventory
  }

  void spawnInitialObjects() {
    for(int i=0; i<5; i++) {
      world.add(Rock(position: Vector2(i * 150 + 300, 300 + _rnd.nextDouble() * 200)));
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

  void spawnBoss() {
    gameState = GameState.bossBattle;
    double spawnX = player.position.x + 500;
    double spawnY = 300; // Center Y roughly

    // Boss Stats Scale with Level
    double hpScale = 1.0 + (player.level * 0.2);
    currentBoss = BossEnemy(position: Vector2(spawnX, spawnY), hpScale: hpScale);
    world.add(currentBoss!);
  }

  void onBossDefeated() {
    gameState = GameState.running;
    currentBoss = null;
    _spawnTimer = 2.0; // Grace period
    _lastBossTriggerX = player.position.x; // Reset trigger
  }

  @override
  void update(double dt) {
    if (isGameOver) return;
    super.update(dt);

    // Camera Sync
    camera.viewfinder.position = Vector2(player.position.x, 300);

    // Update Text Content
    distanceText.text = 'Distance: ${(player.position.x / 10).toInt()}m';
    xpLevelText.text = 'Lvl ${player.level}';

    // State Machine
    if (gameState == GameState.running) {
       // Check Boss Trigger: Every 1000 distance units
       if (player.position.x > _lastBossTriggerX + 1000) {
         gameState = GameState.bossWarning;
         _bossWarningTimer = 3.0;
         bossWarningText.opacity = 1;
         // Flash effect
         bossWarningText.add(
           OpacityEffect.to(0, EffectController(duration: 0.5, alternate: true, infinite: true))
         );
       }

       // Normal Spawning
       _spawnTimer += dt;
       if (_spawnTimer > 2.0) {
         _spawnTimer = 0;
         double spawnX = player.position.x + 600; // spawn further ahead due to zoom
         double spawnY = 200 + _rnd.nextDouble() * 250;

         if (_rnd.nextDouble() < 0.6) {
           world.add(Enemy(position: Vector2(spawnX, spawnY), hpScale: 1.0 + (player.level * 0.1)));
         } else {
           world.add(Rock(position: Vector2(spawnX, spawnY)));
         }
       }
    } else if (gameState == GameState.bossWarning) {
       _bossWarningTimer -= dt;
       if (_bossWarningTimer <= 0) {
         bossWarningText.opacity = 0;
         bossWarningText.removeAll(bossWarningText.children); // remove effects
         spawnBoss();
       }
    } else if (gameState == GameState.bossBattle) {
       // Boss logic handled in BossEnemy class
       // Ensure boss warning is off
       bossWarningText.opacity = 0;
    }

    // Cleanup
    for (final child in world.children.toList()) {
       if (child is Enemy || child is Rock || child is LootBox) {
          if ((child as PositionComponent).position.x < player.position.x - 600) { // Increased buffer
             child.removeFromParent();
          }
       }
    }
  }
}

// ================= INVENTORY UI =================
class InventoryDisplay extends PositionComponent with HasGameRef<VanguardGame> {
  late RectangleComponent equippedSlot;
  final List<InventorySlot> gridSlots = [];

  InventoryDisplay() : super(size: Vector2(350, 150));

  @override
  Future<void> onLoad() async {
    add(TextComponent(text: "EQUIPPED", position: Vector2(0, 0), textRenderer: TextPaint(style: const TextStyle(fontSize: 10, color: Colors.white))));
    equippedSlot = RectangleComponent(
      position: Vector2(0, 15),
      size: Vector2(40, 40),
      paint: Paint()..color = const Color(0xFF444444),
    );
    add(equippedSlot);

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
    final weapon = gameRef.player.currentWeapon;
    equippedSlot.children.whereType<RectangleComponent>().forEach((c) => c.removeFromParent());
    equippedSlot.add(_getWeaponIcon(weapon, Vector2(20, 20)));

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
      gameRef.player.equipWeapon(storedWeapon!);
    }
  }
}

// ================= PLAYER =================
class Player extends PositionComponent with HasGameRef<VanguardGame> {
  final JoystickComponent joystick;
  final Vector2 floorBounds;

  Set<WeaponType> inventory = { WeaponType.sword };
  WeaponType currentWeapon = WeaponType.sword;

  int level = 1;
  double currentXp = 0;
  double targetXp = 100;
  double maxHp = 100;
  late double currentHp;

  double damage = 20;
  double attackSpeed = 0.5;
  double range = 100;
  bool autoAttackEnabled = true;

  final double moveSpeed = 250;
  late RectangleComponent bodyVisual;
  late RectangleComponent stickWeapon;
  late CircleComponent swirlEffect;

  bool isAttacking = false;
  bool isSwirling = false;
  double _swingTimer = 0;
  double _damageCooldown = 0;
  final Set<PositionComponent> _hitTargets = {};
  Vector2 facingDirection = Vector2(1, 0);

  Player(this.joystick, {required this.floorBounds})
      : super(size: Vector2(60, 90), anchor: Anchor.bottomCenter) {
    position = Vector2(100, 300);
    currentHp = maxHp;
  }

  void collectLoot(WeaponType newWeapon) {
    if (!inventory.contains(newWeapon)) {
      inventory.add(newWeapon);
      gameRef.world.add(DamageText("Found ${newWeapon.name}!", position: position.clone()..y -= 80, color: const Color(0xFFFFD700)));
      gameRef.inventoryDisplay.updateInventoryVisuals();
    } else {
      gameRef.world.add(DamageText("Duplicate Discarded", position: position.clone()..y -= 80, color: Colors.grey));
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
    _hitTargets.clear();
  }

  void gainXp(double amount) {
    currentXp += amount;
    while (currentXp >= targetXp) {
      currentXp -= targetXp;
      level++;
      targetXp *= 1.5;
      maxHp += 20;
      currentHp = maxHp;
      gameRef.world.add(LevelUpText(position: position.clone()..y -= 80));
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

    Future.delayed(Duration.zero, () => gameRef.inventoryDisplay.updateInventoryVisuals());
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_damageCooldown > 0) _damageCooldown -= dt;

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
    for (final child in gameRef.world.children.toList()) {
      if (child is LootBox && child.toAbsoluteRect().overlaps(bodyVisual.toAbsoluteRect())) {
        child.pickup();
      }
    }

    // Attack Logic
    if (!isSwirling) {
      if (isAttacking) {
        _swingTimer += dt;
        double progress = _swingTimer / attackSpeed;
        stickWeapon.angle = -pi/4 + (sin(progress * pi) * pi/2);

        if (progress > 0.2 && progress < 0.8) {
           for (final child in gameRef.world.children.toList()) {
            if (child is Enemy || child is BossEnemy) {
              if (child is PositionComponent && stickWeapon.toAbsoluteRect().overlaps((child as dynamic).bodyVisual.toAbsoluteRect())) {
                 if (!_hitTargets.contains(child)) {
                    if (child is Enemy) child.takeDamage(damage);
                    if (child is BossEnemy) child.takeDamage(damage);
                    _hitTargets.add(child);
                 }
              }
            }
          }
        }
        if (_swingTimer >= attackSpeed) {
          isAttacking = false;
          stickWeapon.opacity = 0;
        }
      } else if (autoAttackEnabled) {
        bool targetFound = false;
        // Check regular enemies
        for (final child in gameRef.world.children) {
          if (child is Enemy && position.distanceTo(child.position) < range) {
            targetFound = true; break;
          }
        }
        // Check boss
        if (!targetFound && gameRef.currentBoss != null && position.distanceTo(gameRef.currentBoss!.position) < range) {
           targetFound = true;
        }

        if (targetFound) startAttack();
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

    for (final child in gameRef.world.children.toList()) {
      if ((child is Enemy || child is BossEnemy) && position.distanceTo((child as PositionComponent).position) <= 200) {
           if (child is Enemy) child.takeDamage(100);
           if (child is BossEnemy) child.takeDamage(100);
      }
    }
    Future.delayed(const Duration(milliseconds: 800), () {
      isSwirling = false;
      swirlEffect.opacity = 0;
    });
  }

  void takeDamage(double amount) {
    if (_damageCooldown > 0 || gameRef.isGameOver) return;
    currentHp -= amount;
    _damageCooldown = 0.5;
    bodyVisual.paint = BasicPalette.red.paint();
    Future.delayed(const Duration(milliseconds: 200), () => bodyVisual.paint = BasicPalette.green.paint());
    gameRef.world.add(DamageText("-${amount.toInt()}", position: position.clone()..y -= 50, color: Colors.red));

    if (currentHp <= 0) {
      gameRef.isGameOver = true;
      gameRef.camera.viewport.add(
        HudButtonComponent(
          button: TextComponent(
            text: "GAME OVER - TAP TO RESTART",
            textRenderer: TextPaint(style: const TextStyle(fontSize: 40, color: Colors.red, fontWeight: FontWeight.bold, backgroundColor: Colors.black)),
            anchor: Anchor.center,
          ),
          position: gameRef.size / 2,
          anchor: Anchor.center,
          onPressed: () {
             // Basic Restart Logic: Reload app logic not available, just unpause?
             // Ideally we restart the whole game instance.
             // Given limitations, we will reset stats and resume.
             gameRef.isGameOver = false;
             gameRef.player.currentHp = gameRef.player.maxHp;
             gameRef.player.position = Vector2(100, 300);
             gameRef.gameState = GameState.running;

             // Clear World Entities
             for (final child in gameRef.world.children.toList()) {
               if (child is Enemy || child is Rock || child is LootBox || child is DamageText) {
                 child.removeFromParent();
               }
             }

             // Remove Game Over Text (this button)
             gameRef.camera.viewport.children.whereType<HudButtonComponent>().last.removeFromParent();
          }
        )
      );
    }
  }
}

// ================= ENEMIES =================
class Enemy extends PositionComponent with HasGameRef<VanguardGame> {
  double maxHp = 40;
  late double currentHp;
  late RectangleComponent bodyVisual;
  late RectangleComponent weaponVisual;
  final double hpScale;
  double moveSpeed = 60;
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
    gameRef.world.add(DamageText("-${amount.toInt()}", position: position.clone()..y -= 60));

    if (currentHp <= 0) {
      onDeath();
    }
  }

  void onDeath() {
    gameRef.player.gainXp(35);
    if (Random().nextDouble() < 0.25) gameRef.world.add(LootBox(position: position.clone()));
    removeFromParent();
  }
}

class BossEnemy extends Enemy {
  double dashTimer = 0;
  bool isDashing = false;

  BossEnemy({required super.position, required super.hpScale}) {
    maxHp = 500 * hpScale;
    currentHp = maxHp;
    size = Vector2(120, 120);
    moveSpeed = 40; // Slow normal move
  }

  @override
  Future<void> onLoad() async {
    // Red Square Visual
    bodyVisual = RectangleComponent(size: size, paint: BasicPalette.red.paint());
    weaponVisual = RectangleComponent(size: Vector2(100, 15), paint: BasicPalette.darkRed.paint(), anchor: Anchor.centerLeft, position: Vector2(size.x/2, size.y/2), angle: -pi/4)..opacity = 0;

    add(bodyVisual);
    add(weaponVisual);
    // Note: No HP bar above head, using BossHealthBar in HUD
  }

  @override
  void update(double dt) {
    // Manually update children to ensure animations play (since we don't call super.update due to hpBar issues)
    for (final child in children) {
      child.update(dt);
    }

    if (_damageCooldown > 0) _damageCooldown -= dt;
    priority = position.y.toInt();

    final player = gameRef.player;
    double dist = position.distanceTo(player.position);

    dashTimer += dt;

    if (isDashing) {
       // Dash Logic
       Vector2 dir = (player.position - position).normalized();
       position.add(dir * 300 * dt); // High speed
       if (dashTimer > 5.5) { // Dash for 0.5s
         isDashing = false;
         dashTimer = 0;
         moveSpeed = 40;
       }
       // Collision during dash
       if (toAbsoluteRect().overlaps(player.bodyVisual.toAbsoluteRect())) {
         player.takeDamage(20);
       }
    } else {
       // Normal AI
       if (dashTimer > 5.0) {
         isDashing = true;
         // Telegraph?
         gameRef.world.add(DamageText("DASH!", position: position.clone()..y-=50, color: Colors.red));
       }

       if (dist > 100) {
         Vector2 dir = (player.position - position).normalized();
         position.add(dir * moveSpeed * dt);
       } else {
         // Melee Attack
         _attackTimer += dt * 5;
         weaponVisual.opacity = 1;
         weaponVisual.angle = -pi/4 + (sin(_attackTimer) * pi/2);
         if (weaponVisual.toAbsoluteRect().overlaps(player.bodyVisual.toAbsoluteRect())) {
            player.takeDamage(10);
         }
       }
    }
  }

  @override
  void onDeath() {
    // Drop 3 Loot Boxes
    for(int i=0; i<3; i++) {
      gameRef.world.add(LootBox(position: position + Vector2(i*40.0, 0)));
    }
    gameRef.player.gainXp(500);
    gameRef.onBossDefeated();
    removeFromParent();
  }
}

// ================= HUD COMPONENTS =================
class BossHealthBar extends PositionComponent {
  final VanguardGame game;
  final Paint _barBack = Paint()..color = Colors.grey;
  final Paint _barFore = Paint()..color = Colors.red;

  BossHealthBar({required this.game}) : super(size: Vector2(400, 25));

  @override
  void render(Canvas canvas) {
    if (game.currentBoss == null) return;

    // Draw Border/Back
    canvas.drawRect(size.toRect(), _barBack);

    double pct = (game.currentBoss!.currentHp / game.currentBoss!.maxHp).clamp(0.0, 1.0);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x * pct, size.y), _barFore);

    // Text label
    const textStyle = TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold);
    const textSpan = TextSpan(text: "BOSS HP", style: textStyle);
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.x/2 - textPainter.width/2, size.y/2 - textPainter.height/2));
  }
}

// ================= LOOT & HELPERS =================
class LootBox extends PositionComponent with HasGameRef<VanguardGame> {
  LootBox({required Vector2 position}) : super(position: position, size: Vector2(30, 30), anchor: Anchor.center);
  @override
  Future<void> onLoad() async {
    add(RectangleComponent(size: size, paint: Paint()..color = const Color(0xFFFFD700)));
    add(MoveEffect.by(Vector2(0, -10), EffectController(duration: 1, alternate: true, infinite: true)));
  }
  void pickup() {
    final type = WeaponType.values[Random().nextInt(WeaponType.values.length)];
    gameRef.player.collectLoot(type);
    removeFromParent();
  }
}

class Rock extends PositionComponent {
  Rock({required Vector2 position}) : super(position: position, size: Vector2(50, 30), anchor: Anchor.bottomCenter);
  @override
  Future<void> onLoad() async { add(CircleComponent(radius: size.x / 2, paint: BasicPalette.gray.paint())); }
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
            style: const TextStyle(color: Colors.yellow, fontSize: 32, fontWeight: FontWeight.bold, shadows: [Shadow(offset: Offset(2, 2), color: Colors.black, blurRadius: 2)]),
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
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _barBackPaint);
    double hpPercent = (player.currentHp / player.maxHp).clamp(0.0, 1.0);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x * hpPercent, size.y), _barForePaint);
  }
}

class XpBarComponent extends PositionComponent {
  final Player player;
  final Paint _barBackPaint = BasicPalette.gray.paint();
  final Paint _barForePaint = BasicPalette.yellow.paint();

  XpBarComponent({required this.player}) : super(size: Vector2(150, 10));

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _barBackPaint);
    double xpPercent = (player.currentXp / player.targetXp).clamp(0.0, 1.0);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x * xpPercent, size.y), _barForePaint);
  }
}
