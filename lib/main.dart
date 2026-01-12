import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/palette.dart';
import 'package:flame/text.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as v;

import 'package:vanguard_path/stickman_3d.dart';

void main() {
  runApp(const GameWidget.controlled(gameFactory: VanguardGame.new));
}

// ================= GAME COMPONENTS =================

enum WeaponType { none, dagger, sword, axe, bow }

extension WeaponTypeExtension on WeaponType {
  String get name => toString().split('.').last.toUpperCase();
}

class VanguardGame extends FlameGame with TapCallbacks {
  late Player player;
  late final JoystickComponent joystick;
  late InventoryDisplay inventoryDisplay;
  late BossWarningText bossWarning;
  late BossHealthBar bossHealthBar;
  late HudButtonComponent kickButton;

  double distanceTraveled = 0;
  double nextBossDistance = 1000;
  bool isBossSequenceActive = false;

  double _spawnTimer = 0;
  final Random rng = Random();

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.center;

    joystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: BasicPalette.white.withAlpha(200).paint()),
      background: CircleComponent(radius: 50, paint: BasicPalette.white.withAlpha(50).paint()),
      margin: const EdgeInsets.only(left: 40, bottom: 40),
    );

    inventoryDisplay = InventoryDisplay();
    bossWarning = BossWarningText();
    bossHealthBar = BossHealthBar();

    player = Player(joystick, floorBounds: Vector2(200, 600));
    world.add(player);

    camera.viewport.add(joystick);
    camera.viewport.add(inventoryDisplay);
    camera.viewport.add(bossWarning);
    camera.viewport.add(bossHealthBar);

    kickButton = HudButtonComponent(
      button: CircleComponent(radius: 30, paint: BasicPalette.red.withAlpha(200).paint()),
      buttonDown: CircleComponent(radius: 30, paint: BasicPalette.white.withAlpha(200).paint()),
      onPressed: () => player.attack(),
      anchor: Anchor.center,
    );
    camera.viewport.add(kickButton);
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    // Removed direct tap attack to rely on button, or keep it as backup?
    // Keeping it as backup if not clicking HUD, but now we have a button.
    if (!joystick.containsPoint(event.localPosition) && !inventoryDisplay.containsPoint(event.localPosition) && !kickButton.containsPoint(event.localPosition)) {
      // player.attack(); // Disable tap-to-attack to prioritize button usage? Or keep?
      // User said "I do not see kick button", implies they want a button.
      // I'll keep tap-to-attack disabled to avoid confusion or accidental taps,
      // or keep it for convenience. Let's keep it but check button bounds.
      // Actually, HudButton consumes the event if pressed.

      // Let's rely on the button as requested.
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x == 0 || size.y == 0) return;
    bool isPortrait = size.y > size.x;
    camera.viewfinder.zoom = isPortrait ? size.x / 450 : size.y / 800;
    if (isLoaded) {
      joystick.position = Vector2(60, size.y - 60);
      inventoryDisplay.position = Vector2(size.x / 2 - 175, 20);
      bossWarning.position = size / 2;
      bossHealthBar.position = Vector2(size.x / 2 - 200, 80);
      kickButton.position = Vector2(size.x - 60, size.y - 60);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    camera.viewfinder.position = Vector2(player.position.x, 300);

    if (player.position.x > distanceTraveled) distanceTraveled = player.position.x;

    if (!isBossSequenceActive && distanceTraveled > nextBossDistance) {
      startBossSequence();
    }

    if (!isBossSequenceActive) {
      _spawnTimer += dt;
      if (_spawnTimer > 2.0) {
        _spawnTimer = 0;
        double spawnX = player.position.x + 600;
        double spawnY = 300 + rng.nextDouble() * 200;

        if (rng.nextBool()) {
          world.add(Enemy(position: Vector2(spawnX, spawnY)));
        } else {
          world.add(Rock(position: Vector2(spawnX, spawnY)));
        }
      }
    }

    for (final child in world.children) {
      if (child is PositionComponent && child.position.x < player.position.x - 600) {
        child.removeFromParent();
      }
    }
  }

  void startBossSequence() {
    isBossSequenceActive = true;
    bossWarning.show();
  }

  void spawnBoss() {
    world.add(Boss(position: Vector2(player.position.x + 500, 400)));
  }

  void onBossDefeated() {
    isBossSequenceActive = false;
    nextBossDistance += 1000;
  }
}

class Player extends PositionComponent with HasGameRef<VanguardGame> {
  final JoystickComponent joystick;
  final Vector2 floorBounds;

  StickmanAnimator? animator;
  late RectangleComponent bodyHitbox;

  double maxHp = 100;
  double currentHp = 100;

  List<WeaponType> inventory = [WeaponType.sword];
  WeaponType currentWeapon = WeaponType.sword;

  double _facingDirection = 1.0;

  Player(this.joystick, {required this.floorBounds}) : super(size: Vector2(150, 225), anchor: Anchor.bottomCenter) {
    position = Vector2(100, 300);
  }

  @override
  Future<void> onLoad() async {
    // CHANGED: Ensure the load method matches the library's API
    animator = await StickmanAnimator.load('assets/test.sap');

    animator?.color = Colors.green;
    bodyHitbox = RectangleComponent(size: size, paint: Paint()..color = Colors.transparent);
    add(bodyHitbox);
  }

  void equipWeapon(WeaponType type) {
    currentWeapon = type;
    animator?.setWeapon(type.name);
  }

  void collectLoot(WeaponType type) {
    if (!inventory.contains(type)) {
      inventory.add(type);
      gameRef.inventoryDisplay.refresh();
    }
  }

  void attack() {
    // FIXED: Use 'Kick' because 'attack' does not exist in test.sap
    animator?.play('Kick');

    Vector2 tipWorld = position + Vector2(40 * _facingDirection, -45);

    for (final c in gameRef.world.children) {
      if (c is Enemy) {
        if (tipWorld.distanceTo(c.position + Vector2(0, -45)) < 50) {
           c.takeDamage(20);
        }
      }
    }
  }

  void takeDamage(int amount) {
    currentHp -= amount;
    animator?.color = Colors.white;
    Future.delayed(const Duration(milliseconds: 100), () => animator?.color = Colors.green);
    if (currentHp <= 0) {
       removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    // FIXED: Use v.Vector2 (64-bit) explicitly to avoid type mismatch with Flame/stickman_3d components
    animator?.render(canvas, v.Vector2(size.x/2, size.y), size.y, _facingDirection);
    super.render(canvas);
  }

  @override
  void update(double dt) {
    super.update(dt);
    Vector2 velocity = Vector2.zero();
    if (!joystick.delta.isZero()) {
      velocity = joystick.relativeDelta * 250;
      position.add(velocity * dt);

      if (velocity.x.abs() > 0.1) _facingDirection = velocity.x.sign;
    }

    position.y = position.y.clamp(floorBounds.x, floorBounds.y);
    priority = position.y.toInt();

    if (animator != null) {
      if (!animator!.isPlaying('Kick')) {
        if (velocity.length > 10) {
            animator!.play('Run'); // This now finds 'Run' due to case-insensitive fix
        } else {
            animator!.play('idle'); // Will fallback to procedural pose since 'idle' is missing
        }

        // FIXED: Pass velocity to allow procedural animation fallbacks
        animator!.update(dt, velocity.x, velocity.y);
      } else {
        // While kicking, update without velocity to keep it in place (or pass velocity if you want sliding kick)
        animator!.update(dt, 0, 0);
      }
    }

    for(final c in gameRef.world.children) {
      if (c is LootBox && c.toAbsoluteRect().overlaps(bodyHitbox.toAbsoluteRect())) c.pickup();
    }
  }
}

class Enemy extends PositionComponent with HasGameRef<VanguardGame> {
  StickmanAnimator? animator;
  int health = 30;
  double _attackCooldown = 0.0;
  double _facingDirection = 1.0;

  Enemy({required Vector2 position}) : super(position: position, size: Vector2(150, 225), anchor: Anchor.bottomCenter);

  @override
  Future<void> onLoad() async {
      animator = await StickmanAnimator.load('assets/test.sap');
      animator?.color = Colors.red;
  }

  void takeDamage(int amount) {
    health -= amount;
    animator?.color = Colors.white;
    Future.delayed(const Duration(milliseconds: 100), () => animator?.color = (this is Boss) ? Colors.purple : Colors.red);
    if (health <= 0) {
      if (Random().nextDouble() < 0.5) gameRef.world.add(LootBox(position: position));
      removeFromParent();
      if (this is Boss) gameRef.onBossDefeated();
    }
  }

  @override
  void render(Canvas canvas) {
    // FIXED: Use v.Vector2 (64-bit) explicitly
    animator?.render(canvas, v.Vector2(size.x/2, size.y), size.y, _facingDirection);
    super.render(canvas);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final player = gameRef.player;
    if (player.parent == null || animator == null) return;

    double dist = position.distanceTo(player.position);
    double vx = 0;
    double vy = 0;

    if (animator != null && animator!.isPlaying('Kick')) {
       animator!.update(dt, 0, 0);
       return;
    }

    if (dist < 400 && dist > 50) {
      Vector2 dir = (player.position - position).normalized();
      position.add(dir * 80 * dt);
      if (dir.x.abs() > 0.1) _facingDirection = dir.x.sign;

      vx = dir.x * 80;
      vy = dir.y * 80;

      animator!.play('Run');
      animator!.update(dt, vx, vy);

    } else if (dist <= 50) {
      if (_attackCooldown <= 0) {
        animator!.play('Kick'); // Use Kick
        if (player.position.distanceTo(position) < 50) {
          player.takeDamage(5);
        }
        _attackCooldown = 1.5;
      } else {
        animator!.play('idle');
      }
      animator!.update(dt, 0, 0);
    } else {
      animator!.play('idle');
      animator!.update(dt, 0, 0);
    }

    if (_attackCooldown > 0) _attackCooldown -= dt;
    priority = position.y.toInt();
  }
}

class Boss extends Enemy {
  Boss({required super.position}) {
    health = 200;
    size = Vector2(300, 450);
  }

  @override
  Future<void> onLoad() async {
      await super.onLoad();
      animator?.color = Colors.purple;
      // Added back scale and weapon config
      animator?.scale = 2.0;
      // animator?.setWeapon('AXE'); // Optional: Add if desired and package supports it
  }
}

// ... [InventoryDisplay, InventorySlot, BossWarningText, etc. remains unchanged] ...
class InventoryDisplay extends PositionComponent with HasGameRef<VanguardGame> {
  final List<InventorySlot> slots = [];

  InventoryDisplay() : super(size: Vector2(350, 100));

  @override
  Future<void> onLoad() async {
    add(RectangleComponent(size: size, paint: BasicPalette.black.withAlpha(150).paint()));

    double startX = 10;
    double startY = 10;
    double slotSize = 40;
    double gap = 10;

    for (int row = 0; row < 2; row++) {
      for (int col = 0; col < 5; col++) {
        int index = row * 5 + col;
        final slot = InventorySlot(index, Vector2(startX + col * (slotSize + gap), startY + row * (slotSize + gap)));
        add(slot);
        slots.add(slot);
      }
    }
    refresh();
  }

  void refresh() {
    final inv = gameRef.player.inventory;
    for (int i = 0; i < slots.length; i++) {
      if (i < inv.length) {
        slots[i].setWeapon(inv[i]);
      } else {
        slots[i].clear();
      }
    }
  }
}

class InventorySlot extends PositionComponent with TapCallbacks, HasGameRef<VanguardGame> {
  final int index;
  WeaponType? weapon;

  InventorySlot(this.index, Vector2 position) : super(position: position, size: Vector2(40, 40));

  @override
  Future<void> onLoad() async {
    add(RectangleComponent(size: size, paint: Paint()..color = Colors.grey..style = PaintingStyle.stroke));
  }

  void setWeapon(WeaponType w) {
    weapon = w;
    Color c = Colors.white;
    if (w == WeaponType.sword) c = Colors.blue;
    if (w == WeaponType.axe) c = Colors.red;
    if (w == WeaponType.dagger) c = Colors.yellow;

    children.whereType<RectangleComponent>().where((c) => c.paint.style == PaintingStyle.fill).forEach((c) => c.removeFromParent());
    add(RectangleComponent(size: size * 0.8, position: size * 0.1, paint: Paint()..color = c));
    updateHighlight();
  }

  void clear() {
    weapon = null;
    children.whereType<RectangleComponent>().where((c) => c.paint.style == PaintingStyle.fill).forEach((c) => c.removeFromParent());
    updateHighlight();
  }

  void updateHighlight() {
    children.whereType<RectangleComponent>().where((c) => c.priority == 10).forEach((c) => c.removeFromParent());
    if (weapon != null && gameRef.player.currentWeapon == weapon) {
      add(RectangleComponent(
        size: size,
        paint: Paint()..color = Colors.green..style = PaintingStyle.stroke..strokeWidth = 3,
        priority: 10
      ));
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (weapon != null) {
      gameRef.player.equipWeapon(weapon!);
      gameRef.inventoryDisplay.refresh();
    }
  }
}

class BossWarningText extends TextComponent with HasGameRef<VanguardGame> {
  double _timer = 0;
  bool _visible = false;

  BossWarningText() : super(
    text: "WARNING: BOSS APPROACHING",
    anchor: Anchor.center,
    textRenderer: TextPaint(style: const TextStyle(color: Colors.transparent, fontSize: 40, fontWeight: FontWeight.bold)),
  );

  void show() {
    _visible = true;
    _timer = 3.0;
  }

  @override
  void update(double dt) {
    if (!_visible) return;
    super.update(dt);
    _timer -= dt;
    textRenderer = TextPaint(style: TextStyle(
      color: (sin(_timer * 15) > 0) ? Colors.red : Colors.transparent,
      fontSize: 40, fontWeight: FontWeight.bold
    ));
    if (_timer <= 0) {
      _visible = false;
      textRenderer = TextPaint(style: const TextStyle(color: Colors.transparent, fontSize: 40, fontWeight: FontWeight.bold));
      gameRef.spawnBoss();
    }
  }
}

class BossHealthBar extends PositionComponent with HasGameRef<VanguardGame> {
  BossHealthBar() : super(size: Vector2(400, 25), anchor: Anchor.topCenter);
  @override
  void render(Canvas c) {
    final boss = gameRef.world.children.whereType<Boss>().firstOrNull;
    if (boss == null) return;
    c.drawRect(size.toRect(), Paint()..color = Colors.grey);
    double pct = (boss.health / 200).clamp(0.0, 1.0);
    c.drawRect(Rect.fromLTWH(0, 0, size.x * pct, size.y), Paint()..color = Colors.red);
    c.drawRect(size.toRect(), Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
  }
}

class LootBox extends PositionComponent with HasGameRef<VanguardGame> {
  LootBox({required Vector2 position}) : super(position: position, size: Vector2(30, 30), anchor: Anchor.center);
  @override Future<void> onLoad() async {
    add(RectangleComponent(size: size, paint: Paint()..color = const Color(0xFFFFD700)));
    add(MoveEffect.by(Vector2(0,-10), EffectController(duration: 1, alternate: true, infinite: true)));
  }
  @override
  void update(double dt) {
    super.update(dt);
    priority = position.y.toInt(); // Z-Sorting fix
  }
  void pickup() {
    gameRef.player.collectLoot(WeaponType.values[Random().nextInt(4)+1]); // Random weapon
    removeFromParent();
  }
}

class Rock extends PositionComponent {
  Rock({required Vector2 position}) : super(position: position, size: Vector2(50, 30), anchor: Anchor.bottomCenter);
  @override Future<void> onLoad() async { add(CircleComponent(radius: 25, paint: BasicPalette.gray.paint())); }
  @override void update(double dt) { super.update(dt); priority = position.y.toInt(); }
}
