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

  double _facingAngle = 0.0;

  StickmanAnimator({
    required this.color,
    this.scale = 1.0,
    this.weaponType = WeaponType.none,
  }) : skeleton = lStandPose.clone();

  void update(double dt, Vector2 velocity) {
    if (velocity.length > 10) {
      double targetAngle = velocity.x > 0 ? pi / 2 : -pi / 2;
      double diff = targetAngle - _facingAngle;
      if (diff.abs() > pi) diff -= 2 * pi * diff.sign;
      _facingAngle += diff * dt * 10;
    }
  }

  void render(Canvas canvas, Vector2 position, double height) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.scale(scale);

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = skeleton.strokeWidth
      ..strokeCap = StrokeCap.round;

    final Paint fillPaint = Paint()..color = color..style = PaintingStyle.fill;

    Offset toScreen(v.Vector3 p) {
      double c = cos(_facingAngle);
      double s = sin(_facingAngle);
      double rx = p.x * c + p.z * s;
      double rz = -p.x * s + p.z * c;
      return Offset(rx, p.y + (rz * 0.3));
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
      canvas.drawLine(rHandPos, rHandPos + Offset(20 * cos(_facingAngle), -20), Paint()..color=Colors.white..strokeWidth=2);
    }

    canvas.restore();
  }
}

class VanguardGame extends FlameGame with TapCallbacks {
  late Player player;
  late final JoystickComponent joystick;
  late InventoryDisplay inventoryDisplay;

  double nextSpawnX = 500;
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

    // Initial spawn removed, handled by update loop
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
      if (rng.nextBool()) {
        world.add(Rock(position: Vector2(nextSpawnX, 300 + rng.nextDouble() * 300)));
      } else {
        world.add(Enemy(position: Vector2(nextSpawnX, 300 + rng.nextDouble() * 300)));
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

  Enemy({required Vector2 position}) : super(position: position, size: Vector2(60, 90), anchor: Anchor.bottomCenter) {
    animator = StickmanAnimator(color: Colors.red, weaponType: WeaponType.none);
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
    final direction = (player.position - position).normalized();

    // Simple tracking
    if (position.distanceTo(player.position) < 400 && position.distanceTo(player.position) > 40) {
      position.add(direction * 100 * dt);
      animator.update(dt, direction * 100);
    } else {
       animator.update(dt, Vector2.zero());
    }

    priority = position.y.toInt();
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
