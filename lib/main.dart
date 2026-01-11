import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/palette.dart';
import 'package:flame/text.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';
import 'dart:math';
// Removed 'dart:ui' to avoid conflicts with material.dart

void main() {
  runApp(const GameWidget.controlled(gameFactory: VanguardGame.new));
}

// ================= HELPERS & MATH =================
class SimpleVector3 {
  double x, y, z;
  SimpleVector3(this.x, this.y, this.z);
  SimpleVector3 operator +(SimpleVector3 other) => SimpleVector3(x + other.x, y + other.y, z + other.z);
  SimpleVector3 operator *(double s) => SimpleVector3(x * s, y * s, z * s);

  void setValues(double x, double y, double z) {
    this.x = x; this.y = y; this.z = z;
  }
}

// ================= ENUMS =================
enum WeaponType { none, dagger, sword, axe, bow }
enum GameState { running, bossWarning, bossBattle }

extension WeaponTypeExtension on WeaponType {
  String get name => toString().split('.').last.toUpperCase();
}

extension ShapeOpacity on ShapeComponent {
  double get opacity => paint.color.opacity;
  set opacity(double value) {
    paint.color = paint.color.withOpacity(value);
  }
}

// ================= SKELETON SYSTEM =================
class StickmanBone {
  String id;
  SimpleVector3 baseOffset;
  SimpleVector3 animOffset = SimpleVector3(0,0,0);
  SimpleVector3 rotation = SimpleVector3(0,0,0); // Euler angles
  List<StickmanBone> children = [];
  SimpleVector3 absolutePos = SimpleVector3(0,0,0); // Computed per frame

  StickmanBone(this.id, this.baseOffset);

  void addChild(StickmanBone child) => children.add(child);
}

// ================= STICKMAN ANIMATOR =================
class StickmanAnimator {
  Color color;
  final double scale;
  WeaponType weaponType;
  bool isAttacking = false;

  double _time = 0.0;
  double _runWeight = 0.0;
  double _facingAngle = 0.0;
  double _attackTimer = 0.0;

  late StickmanBone root;
  late Map<String, StickmanBone> bones;

  StickmanAnimator({
    required this.color,
    this.scale = 1.0,
    this.weaponType = WeaponType.none
  }) {
    _initSkeleton();
  }

  void _initSkeleton() {
    // Define Skeleton matching "Stand" pose request and original dimensions
    bones = {};

    // Root
    root = StickmanBone("hip", SimpleVector3(0,0,0)); bones["hip"] = root;

    // Torso
    var neck = StickmanBone("neck", SimpleVector3(0, -25, 0)); bones["neck"] = neck; root.addChild(neck);
    var head = StickmanBone("head", SimpleVector3(0, -8, 0)); bones["head"] = head; neck.addChild(head); // Head offset from neck

    // Arms
    var lShoulder = StickmanBone("lShoulder", SimpleVector3(0,0,0)); bones["lShoulder"] = lShoulder; neck.addChild(lShoulder);
    var lElbow = StickmanBone("lElbow", SimpleVector3(-6, 10, 0)); bones["lElbow"] = lElbow; lShoulder.addChild(lElbow);
    var lHand = StickmanBone("lHand", SimpleVector3(0, 10, 0)); bones["lHand"] = lHand; lElbow.addChild(lHand);

    var rShoulder = StickmanBone("rShoulder", SimpleVector3(0,0,0)); bones["rShoulder"] = rShoulder; neck.addChild(rShoulder);
    var rElbow = StickmanBone("rElbow", SimpleVector3(6, 10, 0)); bones["rElbow"] = rElbow; rShoulder.addChild(rElbow);
    var rHand = StickmanBone("rHand", SimpleVector3(0, 10, 0)); bones["rHand"] = rHand; rElbow.addChild(rHand);

    // Legs
    var lHip = StickmanBone("lHip", SimpleVector3(0,0,0)); bones["lHip"] = lHip; root.addChild(lHip);
    var lKnee = StickmanBone("lKnee", SimpleVector3(-3, 12, 0)); bones["lKnee"] = lKnee; lHip.addChild(lKnee);
    var lFoot = StickmanBone("lFoot", SimpleVector3(-3, 12, 0)); bones["lFoot"] = lFoot; lKnee.addChild(lFoot);

    var rHip = StickmanBone("rHip", SimpleVector3(0,0,0)); bones["rHip"] = rHip; root.addChild(rHip);
    var rKnee = StickmanBone("rKnee", SimpleVector3(3, 12, 0)); bones["rKnee"] = rKnee; rHip.addChild(rKnee);
    var rFoot = StickmanBone("rFoot", SimpleVector3(3, 12, 0)); bones["rFoot"] = rFoot; rKnee.addChild(rFoot);
  }

  double get attackDuration {
    switch (weaponType) {
      case WeaponType.dagger: return 0.2;
      case WeaponType.sword: return 0.5;
      case WeaponType.axe: return 1.0;
      default: return 0.3;
    }
  }

  void update(double dt, Vector2 velocity, bool isDashing) {
    _time += dt * 10;

    double speed = velocity.length;
    double targetWeight = speed > 10 ? 1.0 : 0.0;
    _runWeight += (targetWeight - _runWeight) * dt * 5;

    // Face Direction Logic
    if (speed > 10) {
      double targetAngle = velocity.x > 0 ? -pi / 2 : pi / 2;
      double diff = targetAngle - _facingAngle;
      if (diff.abs() > pi) diff -= 2 * pi * diff.sign;
      _facingAngle += diff * dt * 10;
    }

    if (isAttacking) {
      _attackTimer += dt;
      if (_attackTimer > attackDuration) {
        isAttacking = false;
        _attackTimer = 0.0;
      }
    }

    // --- ANIMATION LOGIC ---
    // Reset all pose offsets
    bones.values.forEach((b) { b.animOffset.setValues(0,0,0); b.rotation.setValues(0,0,0); });

    // "Stand" Pose Request: rFoot offset by 7.8
    // Only apply when not running full speed
    if (_runWeight < 0.5) {
       bones["rFoot"]!.animOffset.y = 7.8 * (1.0 - _runWeight);
    }

    // Running / Breathing Animation
    double legSwing = sin(_time) * 0.8 * _runWeight;
    double armSwing = cos(_time) * 0.8 * _runWeight;

    // Breathing (Torso bob)
    double breath = sin(_time * 0.5) * 1.0;
    bones["neck"]!.rotation.y = breath * (1 - _runWeight); // Y offset actually? No rotation for bob.
    // Hack: adjust baseOffset or animOffset for bobbing?
    // Using animOffset on Neck
    bones["neck"]!.animOffset.y = (breath * (1 - _runWeight)) + ((sin(_time)).abs() * 3.0 * _runWeight);

    // Apply Rotations (X-axis for swinging)
    bones["lHip"]!.rotation.x = legSwing;
    bones["lKnee"]!.rotation.x = 0.2; // Slight bend offset

    bones["rHip"]!.rotation.x = -legSwing;
    bones["rKnee"]!.rotation.x = 0.2;

    double lArmAngle = -armSwing;
    double rArmAngle = armSwing;

    if (isAttacking) {
       double p = (_attackTimer / attackDuration).clamp(0.0, 1.0);
       if (weaponType == WeaponType.none) rArmAngle = -1.5;
       else rArmAngle = -2.8 + (2.6 * p);
    } else if (weaponType != WeaponType.none) {
       rArmAngle = -0.5;
    }

    bones["lShoulder"]!.rotation.x = lArmAngle;
    bones["lElbow"]!.rotation.x = -0.3; // Forearm bend

    bones["rShoulder"]!.rotation.x = rArmAngle;
    bones["rElbow"]!.rotation.x = -0.3;

    // Punch Extension
    if (isAttacking && weaponType == WeaponType.none) {
       double punchProgress = sin((_attackTimer / 0.3) * pi);
       bones["rHand"]!.animOffset.z = punchProgress * 15;
       bones["rHand"]!.animOffset.y = -punchProgress * 5;
    }
  }

  void render(Canvas canvas, Vector2 position, double height) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.scale(scale);

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final Paint fillPaint = Paint()..color = color..style = PaintingStyle.fill;

    // 1. Calculate Absolute Positions
    _computeAbsolutePositions(root, SimpleVector3(0,0,0), SimpleVector3(0,0,0));

    // 2. Apply Y-Rotation (Facing) to all absolute positions
    // This is easier than rotating every bone locally
    Map<String, SimpleVector3> p3d = {};
    bones.forEach((k, v) {
      SimpleVector3 pos = SimpleVector3(v.absolutePos.x, v.absolutePos.y, v.absolutePos.z);
      _applyRotationY(pos, _facingAngle);
      p3d[k] = pos;
    });

    // 3. Project to 2D
    Map<String, Offset> p2d = {};
    p3d.forEach((k, v) {
      p2d[k] = _project(v, Vector2.zero());
    });

    void drawBone(String start, String end) {
      canvas.drawLine(p2d[start]!, p2d[end]!, paint);
    }

    void drawLeft() {
      drawBone("lHip", "lKnee"); drawBone("lKnee", "lFoot");
      drawBone("lShoulder", "lElbow"); drawBone("lElbow", "lHand");
      if (weaponType == WeaponType.bow) {
        Offset hand = p2d["lHand"]!;
        Paint bp = Paint()..color = Colors.brown..style = PaintingStyle.stroke..strokeWidth = 2;
        canvas.drawArc(Rect.fromCenter(center: hand, width: 10, height: 30), (_facingAngle > 0 ? pi/2 : -pi/2), pi, false, bp);
      }
    }

    void drawRight() {
      drawBone("rHip", "rKnee"); drawBone("rKnee", "rFoot");
      drawBone("rShoulder", "rElbow"); drawBone("rElbow", "rHand");

      if (weaponType != WeaponType.none && weaponType != WeaponType.bow) {
        Offset hand = p2d["rHand"]!;
        // Calculate tip based on rHand position + projected vector
        // Or better: use the bone rotation?
        // Since we projected points, we need to project the weapon tip too.
        // Weapon aligns with rHand bone (rElbow -> rHand).
        // Let's use the stickmanBone "rHand" absolute rotation? No, we just have points.

        // Use previous logic: Weapon vector relative to hand
        // In local space of rHand: (0, len, 0)
        double len = 20.0;
        if (weaponType == WeaponType.dagger) len = 10.0;
        if (weaponType == WeaponType.axe) len = 25.0;

        // Parent (Elbow) rotation affects Hand. Hand rotation affects Weapon.
        // rHand bone has `rotation`.
        // To get accurate tip, we should add a "weaponTip" bone?
        // Or just rotate vector by (rArmAngle - 0.3) manually like before?
        // The rotation is encoded in the bone hierarchy now.
        // But `p3d` doesn't have orientation.
        // Let's deduce direction from Elbow->Hand
        SimpleVector3 dir = p3d["rHand"]! + (p3d["rHand"]! + (p3d["rElbow"]! * -1)); // Vector Elbow->Hand
        // Normalize? No, length varies with projection.
        // Just add an extension vector in 3D space before projection.

        // Re-calculate tip in 3D:
        // We need the rotation of the rHand.
        // Let's add a virtual bone for the weapon tip!
        StickmanBone rHandBone = bones["rHand"]!;
        // Tip is offset (0, len, 0) relative to rHand
        SimpleVector3 tipLocal = _rotateX(SimpleVector3(0, len, 0), 0); // No extra rotation needed if aligned with bone Y
        // Need to apply hierarchy rotations... this is getting complex for render.
        // Let's keep it simple: Extend vector Elbow->Hand
        SimpleVector3 armVec = bones["rHand"]!.absolutePos + (bones["rElbow"]!.absolutePos * -1);
        double armLen = sqrt(armVec.x*armVec.x + armVec.y*armVec.y + armVec.z*armVec.z);
        SimpleVector3 tip3d = bones["rHand"]!.absolutePos + (armVec * (len / armLen));

        // Apply Y Rotation
        _applyRotationY(tip3d, _facingAngle);
        Offset tip = _project(tip3d, Vector2.zero());

        Paint wp = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2;
        if (weaponType == WeaponType.dagger) wp.color = Colors.yellow;
        if (weaponType == WeaponType.sword) wp.color = Colors.brown;
        if (weaponType == WeaponType.axe) wp.color = Colors.red;

        canvas.drawLine(hand, tip, wp);
        if (weaponType == WeaponType.axe) canvas.drawCircle(tip, 6, Paint()..color = Colors.grey..style = PaintingStyle.fill);
        if (weaponType == WeaponType.sword) {
           Offset mid = hand + (tip - hand) * 0.2;
           Offset perp = Offset(tip.dy - hand.dy, hand.dx - tip.dx);
           double l = sqrt(perp.dx*perp.dx + perp.dy*perp.dy);
           if (l > 0) perp = perp.scale(1/l, 1/l) * 5.0;
           canvas.drawLine(mid - perp, mid + perp, wp);
        }
      }
    }

    void drawBody() {
      drawBone("hip", "neck");
      // Head
      Offset headCenter = p2d["head"]!;
      canvas.drawCircle(headCenter, 6, fillPaint);
    }

    if (sin(_facingAngle) >= 0) {
       drawRight(); drawBody(); drawLeft();
    } else {
       drawLeft(); drawBody(); drawRight();
    }
    canvas.restore();
  }

  void _computeAbsolutePositions(StickmanBone bone, SimpleVector3 parentPos, SimpleVector3 parentRot) {
    // 1. Accumulate Rotation
    SimpleVector3 currentRot = parentRot + bone.rotation;

    // 2. Apply Local Transformation: Base + Anim
    SimpleVector3 local = bone.baseOffset + bone.animOffset;

    // 3. Rotate Local vector by Current Accumulated Rotation
    // This moves the bone end-point based on the joint rotation
    local = _rotateX(local, currentRot.x);
    local = _rotateY(local, currentRot.y);
    local = _rotateZ(local, currentRot.z);

    // 4. Absolute Position = Parent + Rotated Local
    bone.absolutePos = parentPos + local;

    for (var child in bone.children) {
      // For children, the pivot is this bone's end point (absolutePos)
      // and the rotation context includes this bone's rotation.
      _computeAbsolutePositions(child, bone.absolutePos, currentRot);
    }
  }

  // Math Helpers
  SimpleVector3 _rotateX(SimpleVector3 v, double angle) {
    double c = cos(angle);
    double s = sin(angle);
    return SimpleVector3(v.x, v.y * c - v.z * s, v.y * s + v.z * c);
  }
  SimpleVector3 _rotateY(SimpleVector3 v, double angle) {
    double c = cos(angle);
    double s = sin(angle);
    return SimpleVector3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
  }
  SimpleVector3 _rotateZ(SimpleVector3 v, double angle) {
    double c = cos(angle);
    double s = sin(angle);
    return SimpleVector3(v.x * c - v.y * s, v.x * s + v.y * c, v.z);
  }
  void _applyRotationY(SimpleVector3 v, double angle) {
    double c = cos(angle);
    double s = sin(angle);
    double newX = v.x * c + v.z * s;
    double newZ = -v.x * s + v.z * c;
    v.x = newX;
    v.z = newZ;
  }
  Offset _project(SimpleVector3 p, Vector2 center) {
    return Offset(center.x + p.x, center.y + p.y + (p.z * 0.3));
  }
}

// ================= GAME ENGINE =================
class VanguardGame extends FlameGame with TapCallbacks {
  late Player player;
  late final JoystickComponent joystick;

  // HUD Elements
  late InventoryDisplay inventoryDisplay;
  late TextComponent autoText;
  late TextComponent distanceText;
  late TextComponent xpLevelText;
  late TextComponent bossWarningText;
  late BossHealthBar bossHealthBar;
  late HudButtonComponent attackButton;
  late HudButtonComponent skillButton;
  late HudButtonComponent autoButton;
  late PlayerHealthBar playerHealthBar;
  late XpBarComponent xpBar;

  BossEnemy? currentBoss;

  GameState gameState = GameState.running;
  double _spawnTimer = 0;
  double _distanceTraveled = 0;
  double _bossWarningTimer = 0;
  double _lastBossTriggerX = 0;
  double _time = 0;

  final Random _rnd = Random();
  bool isGameOver = false;

  double currentTime() => _time;

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.center;

    final knobPaint = BasicPalette.white.withAlpha(200).paint();
    final backgroundPaint = BasicPalette.white.withAlpha(50).paint();

    joystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: knobPaint),
      background: CircleComponent(radius: 50, paint: backgroundPaint),
    );

    attackButton = HudButtonComponent(
      button: CircleComponent(radius: 35, paint: BasicPalette.red.withAlpha(200).paint()),
      onPressed: () => player.startAttack(),
      children: [TextComponent(text: "ATK", position: Vector2(22, 25), anchor: Anchor.center, textRenderer: TextPaint(style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)))]
    );

    skillButton = HudButtonComponent(
      button: CircleComponent(radius: 25, paint: BasicPalette.cyan.withAlpha(200).paint()),
      onPressed: () => player.activateSkill(),
      children: [TextComponent(text: "SWIRL", position: Vector2(25, 25), anchor: Anchor.center, textRenderer: TextPaint(style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)))]
    );

    autoButton = HudButtonComponent(
      button: RectangleComponent(size: Vector2(100, 40), paint: BasicPalette.black.withAlpha(150).paint()),
      onPressed: toggleAuto,
    );
    // Initialize autoText BEFORE adding to button (though adding to button does not require it to be fully initialized, access in toggleAuto does)
    // Actually, I removed the initialization in previous step by mistake. Adding it back.
    autoText = TextComponent(text: "AUTO: ON", position: Vector2(50, 20), anchor: Anchor.center, textRenderer: TextPaint(style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)));
    autoButton.button!.add(autoText);

    inventoryDisplay = InventoryDisplay();

    distanceText = TextComponent(text: 'Distance: 0m', textRenderer: TextPaint(style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)));
    xpLevelText = TextComponent(text: 'Lvl 1', textRenderer: TextPaint(style: const TextStyle(color: Colors.yellow, fontSize: 16, fontWeight: FontWeight.bold)));

    bossWarningText = TextComponent(
      text: "BOSS APPROACHING!",
      anchor: Anchor.center,
      textRenderer: TextPaint(style: const TextStyle(color: Colors.red, fontSize: 32, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
    );

    bossHealthBar = BossHealthBar(game: this);

    player = Player(joystick, floorBounds: Vector2(200, 600));
    world.add(player);

    playerHealthBar = PlayerHealthBar(player: player);
    xpBar = XpBarComponent(player: player);

    camera.viewport.add(joystick);
    camera.viewport.add(attackButton);
    camera.viewport.add(skillButton);
    camera.viewport.add(autoButton);
    camera.viewport.add(inventoryDisplay);
    camera.viewport.add(distanceText);
    camera.viewport.add(xpLevelText);
    camera.viewport.add(playerHealthBar);
    camera.viewport.add(xpBar);
    camera.viewport.add(bossHealthBar);

    spawnInitialObjects();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Prevent division by zero crash if window is initializing
    if (size.x == 0 || size.y == 0) return;

    bool isPortrait = size.y > size.x;
    double targetZoom = isPortrait ? size.x / 450 : size.y / 800;
    camera.viewfinder.zoom = targetZoom;

    if (isLoaded) _updateHudPositions(size);
  }

  void _updateHudPositions(Vector2 size) {
    double margin = 40;
    joystick.position = Vector2(margin + 20, size.y - margin - 20);
    attackButton.position = Vector2(size.x - 60, size.y - 60);
    skillButton.position = Vector2(size.x - 140, size.y - 60);
    autoButton.position = Vector2(size.x - 120, 20);
    inventoryDisplay.position = Vector2(size.x / 2 - 175, 20);
    distanceText.position = Vector2(20, 20);
    xpLevelText.position = Vector2(20, 45);
    playerHealthBar.position = Vector2(20, 70);
    xpBar.position = Vector2(20, 90);
    bossWarningText.position = size / 2;
    bossHealthBar.position = Vector2(size.x / 2 - 200, 80);
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

  void spawnBoss() {
    gameState = GameState.bossBattle;
    double spawnX = player.position.x + 500;
    double spawnY = 300;
    double hpScale = 1.0 + (player.level * 0.2);
    currentBoss = BossEnemy(position: Vector2(spawnX, spawnY), hpScale: hpScale);
    world.add(currentBoss!);
  }

  void onBossDefeated() {
    gameState = GameState.running;
    currentBoss = null;
    _spawnTimer = 2.0;
    _lastBossTriggerX = player.position.x;
  }

  @override
  void update(double dt) {
    if (isGameOver) return;
    super.update(dt);
    _time += dt;

    camera.viewfinder.position = Vector2(player.position.x, 300);

    distanceText.text = 'Distance: ${(player.position.x / 10).toInt()}m';
    xpLevelText.text = 'Lvl ${player.level}';

    if (gameState == GameState.running) {
       if (player.position.x > _lastBossTriggerX + 1000) {
         gameState = GameState.bossWarning;
         _bossWarningTimer = 3.0;
         if (!camera.viewport.children.contains(bossWarningText)) {
            camera.viewport.add(bossWarningText);
         }
       }

       _spawnTimer += dt;
       if (_spawnTimer > 2.0) {
         _spawnTimer = 0;
         double spawnX = player.position.x + 600;
         double spawnY = 200 + _rnd.nextDouble() * 250;

         if (_rnd.nextDouble() < 0.6) {
           world.add(Enemy(position: Vector2(spawnX, spawnY), hpScale: 1.0 + (player.level * 0.1)));
         } else {
           world.add(Rock(position: Vector2(spawnX, spawnY)));
         }
       }
    } else if (gameState == GameState.bossWarning) {
       _bossWarningTimer -= dt;
       bossWarningText.textRenderer = TextPaint(style: (bossWarningText.textRenderer as TextPaint).style.copyWith(color: (sin(_time * 15) > 0) ? Colors.red : Colors.transparent));

       if (_bossWarningTimer <= 0) {
         if (bossWarningText.parent != null) bossWarningText.removeFromParent();
         spawnBoss();
       }
    }

    for (final child in world.children.toList()) {
       if (child is Enemy || child is Rock || child is LootBox) {
          if ((child as PositionComponent).position.x < player.position.x - 600) {
             child.removeFromParent();
          }
       }
    }
  }
}

// ================= PLAYER =================
class Player extends PositionComponent with HasGameRef<VanguardGame> {
  final JoystickComponent joystick;
  final Vector2 floorBounds;

  late StickmanAnimator animator;
  late RectangleComponent bodyHitbox;
  late RectangleComponent weaponHitbox;
  late CircleComponent swirlEffect;

  Set<WeaponType> inventory = { WeaponType.sword };
  WeaponType currentWeapon = WeaponType.sword;

  int level = 1;
  double currentXp = 0, targetXp = 100, maxHp = 100, currentHp = 100;
  double damage = 20, attackSpeed = 0.5, range = 100;
  bool autoAttackEnabled = true, isAttacking = false, isSwirling = false;

  double _swingTimer = 0, _damageCooldown = 0;
  final Set<Enemy> _hitTargets = {};
  Vector2 velocity = Vector2.zero();

  Player(this.joystick, {required this.floorBounds}) : super(size: Vector2(60, 90), anchor: Anchor.bottomCenter) {
    position = Vector2(100, 300);
    animator = StickmanAnimator(color: Colors.green, weaponType: currentWeapon);
  }

  void collectLoot(WeaponType newWeapon) {
    if (!inventory.contains(newWeapon)) {
      inventory.add(newWeapon);
      gameRef.inventoryDisplay.updateInventoryVisuals();
      gameRef.world.add(DamageText("Found ${newWeapon.name}!", position: position.clone()..y-=80, color: const Color(0xFFFFD700)));
    } else {
      gameRef.world.add(DamageText("Duplicate", position: position.clone()..y-=80, color: Colors.grey));
    }
  }

  void equipWeapon(WeaponType type) {
    currentWeapon = type;
    if(type == WeaponType.dagger) { damage=10; attackSpeed=0.2; range=60; weaponHitbox.size=Vector2(40,5); }
    if(type == WeaponType.sword) { damage=20; attackSpeed=0.5; range=100; weaponHitbox.size=Vector2(60,10); }
    if(type == WeaponType.axe) { damage=45; attackSpeed=1.0; range=130; weaponHitbox.size=Vector2(80,15); }
    animator.weaponType = type;
    gameRef.inventoryDisplay.updateInventoryVisuals();
  }

  void startAttack() { if (!isAttacking && !isSwirling) { isAttacking = true; _swingTimer = 0; _hitTargets.clear(); } }

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
    isSwirling = true; isAttacking = false; swirlEffect.opacity = 1;
    for (final child in gameRef.world.children.toList()) { if (child is Enemy && position.distanceTo(child.position) <= 200) child.takeDamage(100); }
    Future.delayed(const Duration(milliseconds: 800), () { isSwirling = false; swirlEffect.opacity = 0; });
  }

  @override
  Future<void> onLoad() async {
    bodyHitbox = RectangleComponent(size: size, paint: Paint()..color = Colors.transparent);
    weaponHitbox = RectangleComponent(size: Vector2(60, 10), paint: Paint()..color = Colors.transparent, anchor: Anchor.centerLeft, position: Vector2(size.x/2+10, size.y/2), angle: -pi/4);
    swirlEffect = CircleComponent(radius: 200, anchor: Anchor.center, position: size/2, paint: BasicPalette.cyan.withAlpha(100).paint())..opacity = 0;

    add(bodyHitbox); add(weaponHitbox); add(swirlEffect);
    Future.delayed(Duration.zero, () => gameRef.inventoryDisplay.updateInventoryVisuals());
  }

  @override
  void render(Canvas canvas) {
    animator.render(canvas, Vector2(size.x/2, size.y), size.y);
    super.render(canvas);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_damageCooldown > 0) _damageCooldown -= dt;

    velocity = Vector2.zero();
    if (!joystick.delta.isZero()) {
      velocity = joystick.relativeDelta * 250;
      position.add(velocity * dt);
    }
    position.y = position.y.clamp(floorBounds.x, floorBounds.y);
    priority = position.y.toInt();

    animator.isAttacking = isAttacking;
    animator.update(dt, velocity, false);

    // Loot
    for (final child in gameRef.world.children.toList()) { if (child is LootBox && child.toAbsoluteRect().overlaps(bodyHitbox.toAbsoluteRect())) child.pickup(); }

    // Combat
    if (!isSwirling) {
      if (isAttacking) {
        _swingTimer += dt;
        double progress = _swingTimer / attackSpeed;
        weaponHitbox.angle = -pi/4 + (sin(progress * pi) * pi/2);

        if (progress > 0.2 && progress < 0.8) {
           for (final child in gameRef.world.children.toList()) {
            if (child is Enemy && weaponHitbox.toAbsoluteRect().overlaps(child.bodyHitbox.toAbsoluteRect()) && !_hitTargets.contains(child)) {
                child.takeDamage(damage); _hitTargets.add(child);
            }
          }
        }
        if (_swingTimer >= attackSpeed) { isAttacking = false; }
      } else if (autoAttackEnabled) {
        bool targetFound = false;
        for (final child in gameRef.world.children) { if (child is Enemy && position.distanceTo(child.position) < range) { targetFound = true; break; } }
        if (!targetFound && gameRef.currentBoss != null && position.distanceTo(gameRef.currentBoss!.position) < range) targetFound = true;
        if (targetFound) startAttack();
      }
    } else { swirlEffect.angle += dt * 15; }
  }

  void takeDamage(double amount) {
    if (_damageCooldown > 0 || gameRef.isGameOver) return;
    currentHp -= amount; _damageCooldown = 0.5;

    animator.color = Colors.red;
    Future.delayed(const Duration(milliseconds: 200), () {
      if (isMounted) animator.color = Colors.green;
    });

    gameRef.world.add(DamageText("-${amount.toInt()}", position: position.clone()..y -= 50, color: Colors.red));

    if (currentHp <= 0) {
      gameRef.isGameOver = true;
      gameRef.camera.viewport.add(
        HudButtonComponent(
          button: TextComponent(text: "GAME OVER - RESTART", textRenderer: TextPaint(style: const TextStyle(fontSize: 40, color: Colors.red, backgroundColor: Colors.black))),
          position: gameRef.size / 2, anchor: Anchor.center,
          onPressed: () {
             gameRef.isGameOver = false;
             gameRef.player.currentHp = gameRef.player.maxHp;
             gameRef.player.position = Vector2(100, 300);
             gameRef.gameState = GameState.running;
             for (final child in gameRef.world.children.toList()) {
               if (child is Enemy || child is Rock || child is LootBox || child is DamageText) child.removeFromParent();
             }
             gameRef.camera.viewport.children.whereType<HudButtonComponent>().last.removeFromParent();
          }
        )
      );
    }
  }
}

// ================= ENEMIES =================
class Enemy extends PositionComponent with HasGameRef<VanguardGame> {
  double maxHp = 40, currentHp = 40, _damageCooldown = 0;
  late RectangleComponent bodyHitbox, weaponHitbox;
  late StickmanAnimator animator;
  final double hpScale;
  double moveSpeed = 60;
  bool isAttacking = false;
  double _attackTimer = 0;

  Enemy({required Vector2 position, this.hpScale = 1.0}) : super(position: position, size: Vector2(60, 90), anchor: Anchor.bottomCenter) {
    maxHp *= hpScale; currentHp = maxHp;
    animator = StickmanAnimator(color: Colors.red, weaponType: WeaponType.sword);
  }

  @override
  Future<void> onLoad() async {
    bodyHitbox = RectangleComponent(size: size, paint: Paint()..color = Colors.transparent);
    weaponHitbox = RectangleComponent(size: Vector2(50, 8), paint: Paint()..color = Colors.transparent, anchor: Anchor.centerLeft, position: Vector2(size.x/2, size.y/2), angle: -pi/4);
    add(bodyHitbox); add(weaponHitbox);
  }

  @override
  void render(Canvas canvas) {
    animator.render(canvas, Vector2(size.x/2, size.y), size.y);
    super.render(canvas);
    canvas.drawRect(Rect.fromLTWH(0, -10, 60, 6), PaletteEntry(Colors.red).paint());
    canvas.drawRect(Rect.fromLTWH(0, -10, 60 * (currentHp/maxHp).clamp(0,1), 6), PaletteEntry(Colors.green).paint());
  }

  @override
  void update(double dt) {
    // IMPORTANT: Call super.update(dt) so children (hitboxes) update correctly
    super.update(dt);

    if (_damageCooldown > 0) _damageCooldown -= dt;
    priority = position.y.toInt();

    double dist = position.distanceTo(gameRef.player.position);
    Vector2 velocity = Vector2.zero();

    if (dist > 70) {
      isAttacking = false;
      Vector2 dir = (gameRef.player.position - position).normalized();
      velocity = dir * moveSpeed;
      position.add(velocity * dt);
    } else {
      isAttacking = true;
      _attackTimer += dt * 5;
      weaponHitbox.angle = -pi/5 + (sin(_attackTimer) * pi/3);
      if (weaponHitbox.toAbsoluteRect().overlaps(gameRef.player.bodyHitbox.toAbsoluteRect())) gameRef.player.takeDamage(5 * dt);
    }

    animator.isAttacking = isAttacking;
    animator.update(dt, velocity, false);
  }

  void takeDamage(double amount) {
    if (_damageCooldown > 0) return;
    currentHp -= amount; _damageCooldown = 0.2;

    animator.color = Colors.white;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (isMounted) animator.color = Colors.red;
    });

    gameRef.world.add(DamageText("-${amount.toInt()}", position: position.clone()..y-=60));
    if (currentHp <= 0) {
      gameRef.player.gainXp(35);
      if (Random().nextDouble() < 0.25) gameRef.world.add(LootBox(position: position.clone()));
      removeFromParent();
    }
  }
}

class BossEnemy extends Enemy {
  double dashTimer = 0;
  bool isDashing = false;

  BossEnemy({required super.position, required super.hpScale}) {
    maxHp = 500 * hpScale;
    currentHp = maxHp;
    size = Vector2(120, 120);
    moveSpeed = 40;
    animator = StickmanAnimator(color: Colors.red, scale: 2.0, weaponType: WeaponType.axe);
  }

  @override
  void update(double dt) {
    // IMPORTANT: Call super.update(dt)
    super.update(dt);

    if (_damageCooldown > 0) _damageCooldown -= dt;
    priority = position.y.toInt();

    final player = gameRef.player;
    double dist = position.distanceTo(player.position);
    Vector2 velocity = Vector2.zero();
    dashTimer += dt;

    if (isDashing) {
       Vector2 dir = (player.position - position).normalized();
       velocity = dir * 300;
       position.add(velocity * dt);
       if (dashTimer > 5.5) { isDashing = false; dashTimer = 0; }
       if (toAbsoluteRect().overlaps(player.bodyHitbox.toAbsoluteRect())) player.takeDamage(20);
    } else {
       if (dashTimer > 5.0) { isDashing = true; gameRef.world.add(DamageText("DASH!", position: position.clone()..y-=50, color: Colors.red)); }

       if (dist > 100) {
         Vector2 dir = (player.position - position).normalized();
         velocity = dir * moveSpeed;
         position.add(velocity * dt);
       } else {
         isAttacking = true;
         if (toAbsoluteRect().overlaps(player.bodyHitbox.toAbsoluteRect())) player.takeDamage(1);
       }
    }

    animator.isAttacking = isAttacking || isDashing;
    animator.update(dt, velocity, isDashing);
  }

  @override
  void takeDamage(double amount) {
    // Override manual takeDamage because Enemy.takeDamage has lower cooldown/different logic
    if (_damageCooldown > 0) return;
    currentHp -= amount; _damageCooldown = 0.2;
    gameRef.world.add(DamageText("-${amount.toInt()}", position: position.clone()..y-=60));

    if (currentHp <= 0) {
      for(int i=0; i<3; i++) {
         gameRef.world.add(LootBox(position: position + Vector2(i*40.0 - 40, 0)));
      }
      gameRef.player.gainXp(500);
      gameRef.onBossDefeated();
      removeFromParent();
    }
  }
}

// ================= HUD COMPONENTS =================
class BossHealthBar extends PositionComponent {
  final VanguardGame game;
  BossHealthBar({required this.game}) : super(size: Vector2(400, 25));
  @override void render(Canvas c) {
    if (game.currentBoss == null) return;
    c.drawRect(size.toRect(), PaletteEntry(Colors.grey).paint());
    c.drawRect(Rect.fromLTWH(0, 0, size.x * (game.currentBoss!.currentHp / game.currentBoss!.maxHp).clamp(0,1), size.y), PaletteEntry(Colors.red).paint());
    const textStyle = TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold);
    const textSpan = TextSpan(text: "BOSS HP", style: textStyle);
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    textPainter.layout();
    textPainter.paint(c, Offset(size.x/2 - textPainter.width/2, size.y/2 - textPainter.height/2));
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
      case WeaponType.bow: p = BasicPalette.green.paint(); s = Vector2(15, 15); break;
      case WeaponType.none: p = BasicPalette.white.withAlpha(0).paint(); s = Vector2.zero(); break;
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
    Paint p;
    switch(type) {
      case WeaponType.dagger: p = BasicPalette.yellow.paint(); break;
      case WeaponType.sword: p = BasicPalette.brown.paint(); break;
      case WeaponType.axe: p = BasicPalette.red.paint(); break;
      case WeaponType.bow: p = BasicPalette.green.paint(); break;
      default: p = BasicPalette.gray.paint();
    }
    add(RectangleComponent(size: size * 0.6, paint: p, anchor: Anchor.center, position: size/2));
  }

  void clearIcon() { storedWeapon = null; children.whereType<RectangleComponent>().forEach((c) => c.removeFromParent()); }
  @override
  void onTapDown(TapDownEvent event) { if (storedWeapon != null) gameRef.player.equipWeapon(storedWeapon!); }
}

// ================= HELPERS =================
class LootBox extends PositionComponent with HasGameRef<VanguardGame> {
  LootBox({required Vector2 position}) : super(position: position, size: Vector2(30, 30), anchor: Anchor.center);
  @override Future<void> onLoad() async { add(RectangleComponent(size: size, paint: Paint()..color = const Color(0xFFFFD700))); add(MoveEffect.by(Vector2(0,-10), EffectController(duration: 1, alternate: true, infinite: true))); }
  void pickup() {
    final type = [WeaponType.dagger, WeaponType.sword, WeaponType.axe][Random().nextInt(3)];
    gameRef.player.collectLoot(type);
    removeFromParent();
  }
}

class Rock extends PositionComponent {
  Rock({required Vector2 position}) : super(position: position, size: Vector2(50, 30), anchor: Anchor.bottomCenter);
  @override Future<void> onLoad() async { add(CircleComponent(radius: 25, paint: BasicPalette.gray.paint())); }
  @override void update(double dt) { super.update(dt); priority = position.y.toInt(); }
}

class DamageText extends TextComponent {
  final Vector2 velocity = Vector2(0, -100);
  double lifeTime = 0.8;
  DamageText(String text, {required Vector2 position, Color color = Colors.white}) : super(text: text, position: position, textRenderer: TextPaint(style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)));
  @override void update(double dt) { super.update(dt); position.add(velocity * dt); lifeTime -= dt; if (lifeTime <= 0) removeFromParent(); }
}

class LevelUpText extends TextComponent {
  LevelUpText({required Vector2 position}) : super(text: "LEVEL UP!", position: position, textRenderer: TextPaint(style: const TextStyle(color: Colors.yellow, fontSize: 32, fontWeight: FontWeight.bold)));
  @override Future<void> onLoad() async { add(MoveEffect.by(Vector2(0, -80), EffectController(duration: 2.0))); add(RemoveEffect(delay: 2.0)); }
}

class PlayerHealthBar extends PositionComponent {
  final Player player;
  PlayerHealthBar({required this.player}) : super(size: Vector2(150, 15));
  @override void render(Canvas c) {
    c.drawRect(size.toRect(), BasicPalette.gray.paint());
    c.drawRect(Rect.fromLTWH(0, 0, size.x * (player.currentHp/player.maxHp).clamp(0,1), size.y), BasicPalette.blue.paint());
  }
}

class XpBarComponent extends PositionComponent {
  final Player player;
  XpBarComponent({required this.player}) : super(size: Vector2(150, 10));
  @override void render(Canvas c) {
    c.drawRect(size.toRect(), BasicPalette.gray.paint());
    c.drawRect(Rect.fromLTWH(0, 0, size.x * (player.currentXp/player.targetXp).clamp(0,1), size.y), BasicPalette.yellow.paint());
  }
}