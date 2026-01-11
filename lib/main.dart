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
    for (final child in children) {
      copy.children.add(child.clone());
    }
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
    final lShoulder = StickmanNode('lShoulder', v.Vector3(0, 0, 0));
    final rShoulder = StickmanNode('rShoulder', v.Vector3(0, 0, 0));
    neck.children.add(lShoulder);
    neck.children.add(rShoulder);
    final lElbow = StickmanNode('lElbow', v.Vector3(-6, 10, 0));
    lShoulder.children.add(lElbow);
    final lHand = StickmanNode('lHand', v.Vector3(0, 10, 0));
    lElbow.children.add(lHand);
    final rElbow = StickmanNode('rElbow', v.Vector3(6, 10, 0));
    rShoulder.children.add(rElbow);
    final rHand = StickmanNode('rHand', v.Vector3(0, 10, 0));
    rElbow.children.add(rHand);
    final lHip = StickmanNode('lHip', v.Vector3(0, 0, 0));
    final rHip = StickmanNode('rHip', v.Vector3(0, 0, 0));
    root.children.add(lHip);
    root.children.add(rHip);
    final lKnee = StickmanNode('lKnee', v.Vector3(-3, 12, 0));
    lHip.children.add(lKnee);
    final lFoot = StickmanNode('lFoot', v.Vector3(0, 12, 0));
    lKnee.children.add(lFoot);
    final rKnee = StickmanNode('rKnee', v.Vector3(3, 12, 0));
    rHip.children.add(rKnee);
    final rFoot = StickmanNode('rFoot', v.Vector3(0, 12, 0));
    rKnee.children.add(rFoot);
    _refreshNodeCache();
  }

  StickmanSkeleton._fromRoot(this.root) {
    _refreshNodeCache();
  }

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
  v.Vector3 get lShoulder => _getPos('lShoulder');
  v.Vector3 get rShoulder => _getPos('rShoulder');
  v.Vector3 get lHip => _getPos('lHip');
  v.Vector3 get rHip => _getPos('rHip');
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

final StickmanSkeleton lStandPose = StickmanSkeleton()
  ..headRadius = 8.0
  ..strokeWidth = 5.3
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
  ..rHand.setValues(10.0, 0.0, 0.0)
  ..lShoulder.setValues(0, 0, 0)
  ..rShoulder.setValues(0, 0, 0)
  ..lHip.setValues(0, 0, 0)
  ..rHip.setValues(0, 0, 0);


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

  double _facingDirection = 1.0; // 1 for Right, -1 for Left
  double _runTime = 0.0;
  double _attackTime = 0.0;

  StickmanAnimator({
    required this.color,
    this.scale = 1.0,
    this.weaponType = WeaponType.none,
  }) : skeleton = lStandPose.clone(), _basePose = lStandPose.clone();

  void triggerAttack() {
    if (_attackTime <= 0) {
      _attackTime = 0.3; // Attack duration
    }
  }

  void update(double dt, Vector2 velocity) {
    // 1. Handle Direction (Flip Scale)
    if (velocity.x.abs() > 0.1) {
      _facingDirection = velocity.x.sign;
    }

    // 2. Handle Running Animation
    if (velocity.length > 10) {
      _runTime += dt * 10;

      double legSwing = sin(_runTime) * 8;
      double kneeLift = max(0, sin(_runTime)) * 5;

      // Left Leg
      skeleton.lKnee.x = _basePose.lKnee.x + legSwing;
      skeleton.lFoot.x = _basePose.lFoot.x + legSwing * 1.5;
      skeleton.lFoot.y = _basePose.lFoot.y - kneeLift;

      // Right Leg (opposite phase)
      double rLegSwing = sin(_runTime + pi) * 8;
      double rKneeLift = max(0, sin(_runTime + pi)) * 5;
      skeleton.rKnee.x = _basePose.rKnee.x + rLegSwing;
      skeleton.rFoot.x = _basePose.rFoot.x + rLegSwing * 1.5;
      skeleton.rFoot.y = _basePose.rFoot.y - rKneeLift;

      // Arms (swing opposite to legs)
      skeleton.lElbow.x = _basePose.lElbow.x - legSwing;
      skeleton.lHand.x = _basePose.lHand.x - legSwing;

    } else {
      _runTime = 0;
      // Reset logic could be added here to return to base pose
    }

    // 3. Handle Attack Animation
    if (_attackTime > 0) {
       _attackTime -= dt;
       // Attack Animation: Thrust Right Arm
       double progress = 1.0 - (_attackTime / 0.3); // 0.0 to 1.0
       double thrust = sin(progress * pi) * 20; // extend out and back

       skeleton.rElbow.x = _basePose.rElbow.x + thrust;
       skeleton.rHand.x = _basePose.rHand.x + thrust * 1.5;
    } else if (velocity.length <= 10) {
       // Reset limbs if standing still and not attacking
       skeleton.rElbow.x = _basePose.rElbow.x;
       skeleton.rHand.x = _basePose.rHand.x;
       skeleton.lElbow.x = _basePose.lElbow.x;
       skeleton.lHand.x = _basePose.lHand.x;

       skeleton.lKnee.x = _basePose.lKnee.x;
       skeleton.lFoot.x = _basePose.lFoot.x;
       skeleton.lFoot.y = _basePose.lFoot.y;

       skeleton.rKnee.x = _basePose.rKnee.x;
       skeleton.rFoot.x = _basePose.rFoot.x;
       skeleton.rFoot.y = _basePose.rFoot.y;
    } else {
       // Running arms logic applies (handled in run block above for X swing)
       // But we need to ensure Y/Z reset or consistent state if we modified them previously
       double legSwing = sin(_runTime) * 8;
       skeleton.rElbow.x = _basePose.rElbow.x + legSwing;
       skeleton.rHand.x = _basePose.rHand.x + legSwing;
    }
  }

  void render(Canvas canvas, Vector2 position, double height) {
    canvas.save();
    canvas.translate(position.x, position.y);
    // Flip horizontal based on direction
    canvas.scale(scale * _facingDirection, scale);

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = skeleton.strokeWidth
      ..strokeCap = StrokeCap.round;

    final Paint fillPaint = Paint()..color = color..style = PaintingStyle.fill;

    // Simple 2D projection (Z ignored as visual depth)
    Offset toScreen(v.Vector3 p) {
      return Offset(p.x, p.y);
    }

    void drawNode(StickmanNode node, Offset parentPos) {
      Offset currentPos = toScreen(node.position);
      if (node.id != 'hip') {
        canvas.drawLine(parentPos, currentPos, paint);
      }
      if (node.id == 'head') {
        canvas.drawCircle(currentPos, skeleton.headRadius, fillPaint);
      }
      for (var child in node.children) {
        drawNode(child, currentPos);
      }
    }

    drawNode(skeleton.root, toScreen(skeleton.root.position));

    if (weaponType != WeaponType.none) {
      final rHandPos = toScreen(skeleton.rHand);
      canvas.drawLine(rHandPos, rHandPos + const Offset(20, -20), Paint()..color=Colors.white..strokeWidth=2);
    }

    canvas.restore();
  }
}

class VanguardGame extends FlameGame with TapCallbacks {
  late Player player;
  late final JoystickComponent joystick;
  late InventoryDisplay inventoryDisplay;

  double nextSpawnX = 500;
  int spawnCount = 0; // Track spawns for Boss
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

    player = Player(joystick, floorBounds: Vector2(200, 600));
    world.add(player);

    camera.viewport.add(joystick);
    camera.viewport.add(inventoryDisplay);
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    // Avoid attacking if tapping HUD
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
      inventoryDisplay.position = Vector2(size.x / 2 - 100, 20);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    camera.viewfinder.position = Vector2(player.position.x, 300);

    // Endless spawning
    final screenRight = camera.viewfinder.position.x + (size.x / 2 / camera.viewfinder.zoom);
    if (screenRight + 200 > nextSpawnX) {
      spawnCount++;
      double spawnY = 300 + rng.nextDouble() * 300;

      if (spawnCount % 5 == 0) {
        // Spawn Boss every 5th spawn
        world.add(Boss(position: Vector2(nextSpawnX, spawnY)));
      } else {
        if (rng.nextBool()) {
          world.add(Rock(position: Vector2(nextSpawnX, spawnY)));
        } else {
          world.add(Enemy(position: Vector2(nextSpawnX, spawnY)));
        }
      }
      nextSpawnX += 300 + rng.nextDouble() * 400;
    }
  }
}

class Player extends PositionComponent with HasGameRef<VanguardGame> {
  final JoystickComponent joystick;
  final Vector2 floorBounds;
  late StickmanAnimator animator;
  late RectangleComponent bodyHitbox;
  int health = 100;

  Set<WeaponType> inventory = { WeaponType.sword };
  WeaponType currentWeapon = WeaponType.sword;

  Player(this.joystick, {required this.floorBounds}) : super(size: Vector2(60, 90), anchor: Anchor.bottomCenter) {
    position = Vector2(100, 300);
    animator = StickmanAnimator(color: Colors.green, weaponType: currentWeapon);
  }

  void equipWeapon(WeaponType type) {
    currentWeapon = type;
    animator.weaponType = type;
  }

  void attack() {
    animator.triggerAttack();
    // Simple hitbox check for attack
    for (final c in gameRef.world.children) {
      if (c is Enemy && c.distance(this) < 80) { // range check
        c.takeDamage(10);
      }
    }
  }

  void takeDamage(int amount) {
    health -= amount;
    // Visual flash
    animator.color = Colors.white;
    Future.delayed(const Duration(milliseconds: 100), () => animator.color = Colors.green);

    if (health <= 0) {
      // Game Over logic (reset or stop)
      removeFromParent(); // Simple death
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
  late RectangleComponent bodyHitbox;
  int health = 30;
  double _attackCooldown = 0.0;

  Enemy({required Vector2 position}) : super(position: position, size: Vector2(60, 90), anchor: Anchor.bottomCenter) {
    animator = StickmanAnimator(color: Colors.red, weaponType: WeaponType.none);
  }

  void takeDamage(int amount) {
    health -= amount;
    animator.color = Colors.white; // Flash white
    Future.delayed(const Duration(milliseconds: 100), () => animator.color = (this is Boss) ? Colors.purple : Colors.red);

    if (health <= 0) {
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
    final player = gameRef.player;
    if (player.parent == null) return; // Player dead

    final direction = (player.position - position).normalized();
    double dist = position.distanceTo(player.position);

    // AI Logic
    if (dist < 400 && dist > 40) {
      position.add(direction * 100 * dt);
      animator.update(dt, direction * 100);
    } else if (dist <= 40) {
      // Attack range
      animator.update(dt, Vector2.zero());
      if (_attackCooldown <= 0) {
        animator.triggerAttack();
        player.takeDamage(5);
        _attackCooldown = 1.0;
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
    health = 100;
    animator = StickmanAnimator(color: Colors.purple, scale: 2.0, weaponType: WeaponType.axe);
    size = Vector2(120, 180);
  }

  @override
  void takeDamage(int amount) {
    super.takeDamage(amount);
    // Boss specific reaction?
  }
}


// ================= HELPERS (Loot, etc) =================

class InventoryDisplay extends PositionComponent with HasGameRef<VanguardGame> {
  InventoryDisplay() : super(size: Vector2(200, 50));
  @override Future<void> onLoad() async {
    add(RectangleComponent(size: size, paint: BasicPalette.black.withAlpha(100).paint()));
    add(TextComponent(text: "Inventory (Tap to equip)", position: Vector2(10,10)));
  }
}

class LootBox extends PositionComponent with HasGameRef<VanguardGame> {
  LootBox({required Vector2 position}) : super(position: position, size: Vector2(30, 30), anchor: Anchor.center);
  @override Future<void> onLoad() async {
    // FIXED: Using standard Paint instead of BasicPalette.gold
    add(RectangleComponent(size: size, paint: Paint()..color = const Color(0xFFFFD700)));
    add(MoveEffect.by(Vector2(0,-10), EffectController(duration: 1, alternate: true, infinite: true)));
  }
  void pickup() {
    gameRef.player.equipWeapon(WeaponType.axe);
    removeFromParent();
  }
}

class Rock extends PositionComponent {
  Rock({required Vector2 position}) : super(position: position, size: Vector2(50, 30), anchor: Anchor.bottomCenter);
  @override Future<void> onLoad() async { add(CircleComponent(radius: 25, paint: BasicPalette.gray.paint())); }
  @override void update(double dt) { super.update(dt); priority = position.y.toInt(); }
}
