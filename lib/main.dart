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

void main() {
  runApp(const GameWidget.controlled(gameFactory: VanguardGame.new));
}

// ================= STICKMAN LIBRARY ADAPTER =================

class StickmanNode {
  String id;
  v.Vector3 position;
  List<StickmanNode> children = [];
  StickmanNode(this.id, v.Vector3 pos) : position = v.Vector3.copy(pos);
  StickmanNode clone() {
    final copy = StickmanNode(id, position);
    for (final child in children) copy.children.add(child.clone());
    return copy;
  }
}

class StickmanSkeleton {
  late StickmanNode root;
  double headRadius = 6.0;
  double strokeWidth = 3.0;
  final Map<String, StickmanNode> _nodes = {};

  StickmanSkeleton() {
    root = StickmanNode('hip', v.Vector3.zero());
    final neck = StickmanNode('neck', v.Vector3(0, -25, 0));
    root.children.add(neck);
    final head = StickmanNode('head', v.Vector3(0, -10, 0));
    neck.children.add(head);
    final lElbow = StickmanNode('lElbow', v.Vector3(-6, 10, 0));
    neck.children.add(lElbow);
    final lHand = StickmanNode('lHand', v.Vector3(0, 10, 0));
    lElbow.children.add(lHand);
    final rElbow = StickmanNode('rElbow', v.Vector3(6, 10, 0));
    neck.children.add(rElbow);
    final rHand = StickmanNode('rHand', v.Vector3(0, 10, 0));
    rElbow.children.add(rHand);
    final lKnee = StickmanNode('lKnee', v.Vector3(-3, 12, 0));
    root.children.add(lKnee);
    final lFoot = StickmanNode('lFoot', v.Vector3(0, 12, 0));
    lKnee.children.add(lFoot);
    final rKnee = StickmanNode('rKnee', v.Vector3(3, 12, 0));
    root.children.add(rKnee);
    final rFoot = StickmanNode('rFoot', v.Vector3(0, 12, 0));
    rKnee.children.add(rFoot);
    _refreshNodeCache();
  }

  StickmanSkeleton._fromRoot(this.root) { _refreshNodeCache(); }

  void _refreshNodeCache() {
    _nodes.clear();
    void traverse(StickmanNode node) {
      _nodes[node.id] = node;
      for (var c in node.children) traverse(c);
    }
    traverse(root);
  }

  StickmanSkeleton clone() {
    final copy = StickmanSkeleton._fromRoot(root.clone());
    copy.headRadius = headRadius;
    copy.strokeWidth = strokeWidth;
    return copy;
  }

  v.Vector3 _getPos(String id) => _nodes[id]?.position ?? v.Vector3.zero();
  v.Vector3 get hip => _getPos('hip');
  v.Vector3 get neck => _getPos('neck');
  v.Vector3 get head => _getPos('head');
  v.Vector3 get lKnee => _getPos('lKnee');
  v.Vector3 get rKnee => _getPos('rKnee');
  v.Vector3 get lFoot => _getPos('lFoot');
  v.Vector3 get rFoot => _getPos('rFoot');
  v.Vector3 get lElbow => _getPos('lElbow');
  v.Vector3 get rElbow => _getPos('rElbow');
  v.Vector3 get lHand => _getPos('lHand');
  v.Vector3 get rHand => _getPos('rHand');
}

// ================= USER POSE DATA =================
final StickmanSkeleton myPose = StickmanSkeleton()
  ..headRadius = 6.9
  ..strokeWidth = 5.4
  ..hip.setValues(1.0, 0.0, 0.0)
  ..neck.setValues(0.0, -14.7, 0.0)
  ..head.setValues(0.0, -22.0, 0.0)
  ..lKnee.setValues(-4.1, 11.8, 0.0)
  ..rKnee.setValues(5.0, 12.0, 0.0)
  ..lFoot.setValues(-7.2, 24.5, 0.0)
  ..rFoot.setValues(7.9, 24.3, 0.0)
  ..lElbow.setValues(-6.1, -7.2, 0.0)
  ..rElbow.setValues(6.2, -7.4, 0.0)
  ..lHand.setValues(-10.0, 0.0, 0.0)
  ..rHand.setValues(10.0, 0.0, 0.0);

// ================= GAME COMPONENTS =================

enum WeaponType { none, dagger, sword, axe, bow }

extension WeaponTypeExtension on WeaponType {
  String get name => toString().split('.').last.toUpperCase();
}

class StickmanAnimator {
  Color color;
  final double scale;
  WeaponType weaponType;
  StickmanSkeleton skeleton;
  final StickmanSkeleton _basePose;

  double _facingDirection = 1.0;
  double _runTime = 0.0;
  double _attackTime = 0.0;
  final double _attackDuration = 0.15; // Fast swing

  // Cache for hitbox calculation
  Offset lastWeaponTip = Offset.zero;

  StickmanAnimator({
    required this.color,
    this.scale = 1.0,
    this.weaponType = WeaponType.none,
  }) : skeleton = myPose.clone(), _basePose = myPose.clone();

  void triggerAttack() {
    if (_attackTime <= 0) {
      _attackTime = _attackDuration;
    }
  }

  void update(double dt, Vector2 velocity) {
    if (velocity.x.abs() > 0.1) _facingDirection = velocity.x.sign;

    // Running Logic
    if (velocity.length > 10) {
      _runTime += dt * 10;
      double legSwing = sin(_runTime) * 8;
      double kneeLift = max(0, sin(_runTime)) * 5;

      skeleton.lKnee.x = _basePose.lKnee.x + legSwing;
      skeleton.lFoot.x = _basePose.lFoot.x + legSwing * 1.5;
      skeleton.lFoot.y = _basePose.lFoot.y - kneeLift;

      double rLegSwing = sin(_runTime + pi) * 8;
      double rKneeLift = max(0, sin(_runTime + pi)) * 5;
      skeleton.rKnee.x = _basePose.rKnee.x + rLegSwing;
      skeleton.rFoot.x = _basePose.rFoot.x + rLegSwing * 1.5;
      skeleton.rFoot.y = _basePose.rFoot.y - rKneeLift;

      skeleton.lElbow.x = _basePose.lElbow.x - legSwing;
      skeleton.lHand.x = _basePose.lHand.x - legSwing;

      // Only animate right arm if NOT attacking
      if (_attackTime <= 0) {
        skeleton.rElbow.x = _basePose.rElbow.x + legSwing;
        skeleton.rHand.x = _basePose.rHand.x + legSwing;
      }
    } else {
       // Reset Logic
       skeleton.lKnee.x = _basePose.lKnee.x; skeleton.lFoot.x = _basePose.lFoot.x; skeleton.lFoot.y = _basePose.lFoot.y;
       skeleton.rKnee.x = _basePose.rKnee.x; skeleton.rFoot.x = _basePose.rFoot.x; skeleton.rFoot.y = _basePose.rFoot.y;
       skeleton.lElbow.x = _basePose.lElbow.x; skeleton.lHand.x = _basePose.lHand.x;
       if (_attackTime <= 0) {
          skeleton.rElbow.x = _basePose.rElbow.x; skeleton.rHand.x = _basePose.rHand.x;
       }
    }

    // --- CIRCULAR SWING ATTACK ---
    if (_attackTime > 0) {
       _attackTime -= dt;
       double progress = 1.0 - (_attackTime / _attackDuration);

       // Arc: Starts Up (-pi/2), ends Front (0) or slightly down (pi/4)
       double startAngle = -pi * 0.8; // Almost fully up/back
       double endAngle = pi * 0.2;    // Slightly down/forward
       double currentAngle = startAngle + (endAngle - startAngle) * progress;

       double armLength = 25.0; // Forearm length

       // Elbow stays roughly at shoulder, maybe moves slightly
       // We pivot around the Neck/Shoulder area
       // Calculate Hand Position based on angle
       double cx = _basePose.neck.x;
       double cy = _basePose.neck.y;

       // Elbow is half-way along the arc
       skeleton.rElbow.x = cx + cos(currentAngle) * (armLength * 0.5);
       skeleton.rElbow.y = cy + sin(currentAngle) * (armLength * 0.5);

       // Hand is at the end
       skeleton.rHand.x = cx + cos(currentAngle) * armLength;
       skeleton.rHand.y = cy + sin(currentAngle) * armLength;
    }
  }

  void render(Canvas canvas, Vector2 position, double height) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.scale(scale * _facingDirection, scale);

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = skeleton.strokeWidth
      ..strokeCap = StrokeCap.round;

    final Paint fillPaint = Paint()..color = color..style = PaintingStyle.fill;

    Offset toScreen(v.Vector3 p) => Offset(p.x, p.y);

    void drawNode(StickmanNode node, Offset parentPos) {
      Offset currentPos = toScreen(node.position);
      if (node.id != 'hip') canvas.drawLine(parentPos, currentPos, paint);
      if (node.id == 'head') canvas.drawCircle(currentPos, skeleton.headRadius, fillPaint);
      for (var child in node.children) drawNode(child, currentPos);
    }
    drawNode(skeleton.root, toScreen(skeleton.root.position));

    // WEAPON DRAWING (Rotational)
    if (weaponType != WeaponType.none) {
      final rHandPos = toScreen(skeleton.rHand);
      final rElbowPos = toScreen(skeleton.rElbow);

      // Calculate angle from Elbow to Hand to determine sword direction
      final armDir = (rHandPos - rElbowPos);
      final angle = atan2(armDir.dy, armDir.dx);

      final swordLen = 35.0;
      final tipPos = rHandPos + Offset(cos(angle) * swordLen, sin(angle) * swordLen);

      // Store tip for Hitbox calculations (converted to world space roughly later)
      // Note: This 'lastWeaponTip' is in local space relative to the stickman center
      lastWeaponTip = tipPos;

      canvas.drawLine(rHandPos, tipPos, Paint()..color=Colors.white..strokeWidth=2);
    }

    canvas.restore();
  }
}

class VanguardGame extends FlameGame with TapCallbacks {
  late Player player;
  late final JoystickComponent joystick;
  late InventoryDisplay inventoryDisplay;
  late BossWarningText bossWarning;
  late BossHealthBar bossHealthBar;

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
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (!joystick.containsPoint(event.localPosition) && !inventoryDisplay.containsPoint(event.localPosition)) {
      player.attack();
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
  late StickmanAnimator animator;
  late RectangleComponent bodyHitbox;

  // Health
  double maxHp = 100;
  double currentHp = 100;

  List<WeaponType> inventory = [WeaponType.sword];
  WeaponType currentWeapon = WeaponType.sword;

  Player(this.joystick, {required this.floorBounds}) : super(size: Vector2(60, 90), anchor: Anchor.bottomCenter) {
    position = Vector2(100, 300);
    animator = StickmanAnimator(color: Colors.green, weaponType: currentWeapon);
  }

  void equipWeapon(WeaponType type) {
    currentWeapon = type;
    animator.weaponType = type;
  }

  void collectLoot(WeaponType type) {
    if (!inventory.contains(type)) {
      inventory.add(type);
      gameRef.inventoryDisplay.refresh();
    }
  }

  void attack() {
    animator.triggerAttack();

    // HITBOX LOGIC: Precise Tip Calculation
    // We need to convert the local tip position to world position
    // Facing direction matters
    double dir = animator._facingDirection;
    Offset tipLocal = animator.lastWeaponTip;

    // Convert local Offset (relative to anchor) to World Vector2
    // Local tip X needs to be flipped if facing left
    Vector2 tipWorld = position + Vector2(tipLocal.dx * dir, tipLocal.dy);

    for (final c in gameRef.world.children) {
      if (c is Enemy) {
        // Check distance from Sword Tip to Enemy Center
        if (tipWorld.distanceTo(c.position + Vector2(0, -45)) < 40) {
           c.takeDamage(20);
        }
      }
    }
  }

  void takeDamage(int amount) {
    currentHp -= amount;
    animator.color = Colors.white;
    Future.delayed(const Duration(milliseconds: 100), () => animator.color = Colors.green);
    if (currentHp <= 0) {
       // Game Over
       removeFromParent();
    }
  }

  @override
  Future<void> onLoad() async {
    bodyHitbox = RectangleComponent(size: size, paint: Paint()..color = Colors.transparent);
    add(bodyHitbox);
  }

  @override
  void render(Canvas canvas) {
    animator.render(canvas, Vector2(size.x/2, size.y), size.y);
    super.render(canvas);
  }

  @override
  void update(double dt) {
    super.update(dt);
    Vector2 velocity = Vector2.zero();
    if (!joystick.delta.isZero()) {
      velocity = joystick.relativeDelta * 250;
      position.add(velocity * dt);
    }
    position.y = position.y.clamp(floorBounds.x, floorBounds.y);
    priority = position.y.toInt();
    animator.update(dt, velocity);

    for(final c in gameRef.world.children) {
      if (c is LootBox && c.toAbsoluteRect().overlaps(bodyHitbox.toAbsoluteRect())) c.pickup();
    }
  }
}

class Enemy extends PositionComponent with HasGameRef<VanguardGame> {
  late StickmanAnimator animator;
  int health = 30;
  double _attackCooldown = 0.0;

  Enemy({required Vector2 position}) : super(position: position, size: Vector2(60, 90), anchor: Anchor.bottomCenter) {
    animator = StickmanAnimator(color: Colors.red, weaponType: WeaponType.none);
  }

  void takeDamage(int amount) {
    health -= amount;
    animator.color = Colors.white;
    Future.delayed(const Duration(milliseconds: 100), () => animator.color = (this is Boss) ? Colors.purple : Colors.red);
    if (health <= 0) {
      if (Random().nextDouble() < 0.5) gameRef.world.add(LootBox(position: position)); // Increased Drop Rate
      removeFromParent();
      if (this is Boss) gameRef.onBossDefeated();
    }
  }

  @override
  void render(Canvas canvas) {
    animator.render(canvas, Vector2(size.x/2, size.y), size.y);
    super.render(canvas);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final player = gameRef.player;
    if (player.parent == null) return;

    double dist = position.distanceTo(player.position);

    if (dist < 400 && dist > 50) {
      Vector2 dir = (player.position - position).normalized();
      position.add(dir * 80 * dt);
      animator.update(dt, dir * 80);
    } else if (dist <= 50) {
      animator.update(dt, Vector2.zero());
      if (_attackCooldown <= 0) {
        animator.triggerAttack(); // Swing animation

        // HITBOX LOGIC for Enemy
        double dir = animator._facingDirection;
        Offset tipLocal = animator.lastWeaponTip;
        Vector2 tipWorld = position + Vector2(tipLocal.dx * dir, tipLocal.dy);

        // Check Tip vs Player Body
        if (tipWorld.distanceTo(player.position + Vector2(0, -45)) < 30) {
          player.takeDamage(5);
        }
        _attackCooldown = 1.5;
      }
    } else {
      animator.update(dt, Vector2.zero());
    }

    if (_attackCooldown > 0) _attackCooldown -= dt;
    priority = position.y.toInt();
  }
}

class Boss extends Enemy {
  Boss({required super.position}) {
    health = 200;
    animator = StickmanAnimator(color: Colors.purple, scale: 2.0, weaponType: WeaponType.axe);
    size = Vector2(120, 180);
  }
}

// ================= UI & COMPONENTS =================

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
