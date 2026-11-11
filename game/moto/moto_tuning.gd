extends RefCounted

# Every number of the motocross stage: physics, controls, camera, juice, art and track.
# Units: world units (1 art pixel = 6), seconds, radians unless the name says _DEG.
# Bike local frame: origin at the centre of mass, x forward (the bike faces right), y down; forces
# are per unit mass (accelerations).

# --- Physics ------------------------------------------------------------------------------------
# Lighter than the player (2600) so a full-speed jump hangs ~1.3 s: room for a backflip.
const GRAVITY := 2300.0
const SUBSTEPS := 4
const WHEEL_RADIUS := 90.0
# Moment of inertia over mass (radius of gyration squared).
const INERTIA := 25600.0
# Contact spring and damper per wheel (per unit mass): static sag about GRAVITY / (2 * SPRING).
const SPRING := 120.0
const DAMP := 9.0
# Compression past this is the end of the suspension: position and normal speed are corrected.
const TRAVEL := 54.0
# Drive and brake forces are limited to GRIP times the wheel's normal force.
const GRIP := 1.1
const ENGINE_ACCEL := 2800.0
const TOP_SPEED := 3500.0
# Rear, front.
const BRAKE_ACCEL := [1000.0, 1500.0]
const REVERSE_ACCEL := 500.0
const REVERSE_MAX := 320.0
# The reverse never comes from braking to a stop: it engages once the bike stands still (ground
# speed under REVERSE_ENGAGE_SPEED, wheels down) with the brake held REVERSE_HOLD seconds, or at
# once when the brake is pressed again while standing still.
const REVERSE_ENGAGE_SPEED := 20.0
const REVERSE_HOLD := 0.4
const ROLL_DRAG := 0.05
# Lean torque (angular acceleration) in the air and on the ground. On the ground leaning back
# lifts the front by itself in ~0.15 s (the throttle lifts it faster, the brake or letting go
# brings it down); held on for ~1 s with the throttle or ~2.5 s without it, the bike passes its
# balance point and loops out into a crash. The throttle alone never wheelies (its torque stays
# under the front wheel's load). Leaning forward presses the front down.
const AIR_LEAN := 16.0
const GROUND_LEAN_BACK := 20.0
const GROUND_LEAN_FORWARD := 12.0
# In the air the throttle lifts the nose and the brake drops it (angular acceleration).
const AIR_THROTTLE_PITCH := 1.0
# With no lean held in the air the bike noses along its flight path (a rider's natural correction),
# so a plain jump lands on the slope and a released flip settles; angular acceleration per radian.
const AIR_ALIGN := 4.0
const AIR_ALIGN_MIN_SPEED := 300.0
const SPIN_DAMP_AIR := 1.2
# High on the ground so a wheelie rises and falls at a pace the player can ride.
const SPIN_DAMP_GROUND := 12.0
const MAX_SPIN := 9.0
# Air time needed before a touchdown counts as a landing.
const LAND_MIN_AIR := 0.15
# Touchdown normal speed of a full-strength landing (sound, shake, dust, squat).
const HARD_LANDING := 1100.0
const RESPAWN_DELAY := 1.2
# Below this speed, on both wheels, the rider may get off.
const DISMOUNT_MAX_SPEED := 60.0
# Steeper than this (the bike's tilt or the ground where the rider steps) and there is no "Descer":
# the dismount is authored for standing ground, and on the final 45 degree bank the rider would
# step into the slope. Mounting a parked bike is always allowed (it was parked within the limit).
const DISMOUNT_MAX_SLOPE_DEG := 26.0
# After a crash: contact radius and Coulomb friction of the frame points.
const CRASH_RADIUS := 14.0
const CRASH_FRICTION := 0.7
# Normal speed into the ground over which a frame point hitting it is a crash (a gentle touch of
# the tail on a wheelie is not).
const CRASH_MIN_SPEED := 0.0
# Physics frames run on parked/respawned bikes to settle the suspension before showing them.
const SETTLE_STEPS := 150

# --- Geometry (local, from the centre of mass; measured on assets/moto/*.png) --------------------
const FRONT_AXLE := Vector2(177, 36)
const REAR_AXLE := Vector2(-190, 34.7)
# Swingarm pivot on the frame (the pixel corner next to the eye centre).
const SWING_PIVOT := Vector2(-24, 42)
const PEG := Vector2(-75, 33)
const GRIP_POINT := Vector2(45, -183)
const SEAT := Vector2(-45, -114)
# Frame points that crash the rider when they reach the ground (and collide once crashed): bar
# top, seat rear, tail, front fender.
const CRASH_POINTS := [Vector2(75, -204), Vector2(-159, -120), Vector2(-276, -114), Vector2(270, -72)]
# The rider's head over the bike: crashes too, but is no contact once the rider is thrown off.
const HEAD_POINT := Vector2(-20, -350)
# Frame points that only collide once crashed (skid plate, footpeg).
const BODY_POINTS := [Vector2(0, 66), Vector2(-75, 40)]
# Unit direction the front wheel travels along when the fork compresses (up the fork).
const FORK_AXIS := Vector2(-0.38, -0.925)
# Where the rider stands to mount and lands after getting off: x from the footpeg.
const MOUNT_DX := -40.0
const DISMOUNT_DX := -40.0
# Rider meta for the rig while riding: squat from the suspension and the landing.
const SQUAT_BASE := 0.3
const SQUAT_FROM_TRAVEL := 0.9
const SQUAT_LANDING := 0.7
const SQUAT_DECAY := 5.0
const LEAN_SMOOTHING := 12.0

# --- Art ----------------------------------------------------------------------------------------
const BODY_PNG := "res://assets/moto/moto_body.png"
const SWINGARM_PNG := "res://assets/moto/moto_swingarm.png"
const WHEEL_PNG := "res://assets/moto/moto_wheel.png"
# Rotation pivots in art px (pixel corners): body at the centre of mass, swingarm at its frame eye.
const BODY_PIVOT_ART := Vector2(46, 34)
const SWING_PIVOT_ART := Vector2(30, 8)
const WHEEL_PIVOT_ART := Vector2(15, 15)
# Swingarm angle (clockwise) that puts its axle eye on REAR_AXLE, and its eye-to-eye length.
const SWING_REST_DEG := 7.85
const SWING_LENGTH := 163.0
const BODY_ANGLE_STEP_DEG := 5.0
const WHEEL_FRAMES := 32
# Wheel spin (rad/s) above which the blurred wheel shows.
const WHEEL_BLUR_SPEED := 14.0
const WHEEL_BLUR_SAMPLES := 8
# Wheel spin in the air: throttle spins the rear up, both slow down.
const WHEEL_AIR_SPIN_UP := 30.0
const WHEEL_AIR_DECAY := 0.6
# Side stand while parked.
# The leg reaches from the footpeg to the ground behind it whatever the slope.
const STAND_BACK := 54.0
const STAND_COLOR := Color("#423a49")
# Build the sheets on a worker thread when they are not cached yet; the stage fades in after.
const FADE_IN := 0.35
const BIKE_Z := 0
const TRACK_Z := -1

# --- Track --------------------------------------------------------------------------------------
# Tabletop: run-up, a long 34 degree kicker 800 high, a short table and a 15 degree landing 3000
# long. Full throttle flies ~1.33 s and lands three quarters down the landing; 2200 u/s at the
# kicker foot still clears the table. Holding lean back from takeoff and releasing (or countering
# with lean forward) after 180 to 260 degrees lands a backflip on its wheels. Flat to the finish,
# banks at both ends.
const TRACK_POINTS := [
	Vector2(-1400, -900), Vector2(-1050, 0),
	Vector2(3800, 0), Vector2(4262, -23), Vector2(4720, -91), Vector2(5168, -204), Vector2(5603, -361),
	Vector2(6021, -561), Vector2(6417, -800), Vector2(7017, -800), Vector2(10017, 0),
	Vector2(13600, 0), Vector2(14100, -500), Vector2(14600, -500),
]
const TRACK_FILLET := 120.0
const TRACK_FILLET_STEP_DEG := 6.0
const TRACK_BLOCK_COLS := 512
# Fill rows drawn in the image under the dirt top (the dark rect goes on below).
const TRACK_FILL_ROWS := 64
const BOUNDS_ABOVE := 3600.0
const BOUNDS_BELOW := 420.0
const DIRT_DEPTH := 1800.0
const SPAWN_X := 0.0
# Bike centre of mass x where it is parked and where it respawns.
const PARK_X := 600.0
const FINISH_X := 11500.0
const FINISH_POLE_COLOR := Color("#f4e6e6")
const FINISH_FLAG_A := Color("#141013")
const FINISH_FLAG_B := Color("#f4e6e6")

# --- Camera -------------------------------------------------------------------------------------
const LOOKAHEAD := 650.0
const LOOKAHEAD_SMOOTHING := 2.5
const FLOOR_SCREEN_RATIO := 0.68
const AIR_FOLLOW_MARGIN := 300.0
const CAMERA_SMOOTHING_X := 9.0
const CAMERA_SMOOTHING_Y := 4.0
# Centre of mass to the ground under the bike at rest (camera floor reference).
const CAMERA_FLOOR_OFFSET := 114.0
const CAMERA_BLEND := 0.45

# --- Juice --------------------------------------------------------------------------------------
# Air rotation (radians) short of a whole turn that still counts as a flip, and how long the bike
# must stay up after the landing before the flip is celebrated.
const FLIP_TOLERANCE := 0.6
const FLIP_CONFIRM := 0.3
const FLIP_SHAKE := 10.0
const FLIP_CONFETTI := 26
# Falling faster than this lowers the camera (towards the landing), up to CAMERA_FALL_LOOK_MAX.
const CAMERA_FALL_LOOK_SPEED := 600.0
const CAMERA_FALL_LOOK := 0.45
const CAMERA_FALL_LOOK_MAX := 420.0
# Camera shake amount (world units) per unit of landing impact speed.
const SHAKE_PER_IMPACT := 0.012
const SHAKE_LANDING_TIME := 0.22
const SHAKE_CRASH := 26.0
const SHAKE_CRASH_TIME := 0.4
const HITSTOP_CRASH := 0.06
const ROOST_PER_FRAME := 2
const ROOST_SPEED := 520.0
const ROOST_MIN_SLIP := 0.25
const LAND_DUST := 14
const CRASH_DUST := 24
const DUST_LIFE := 0.55
const DUST_GRAVITY := 900.0
const DUST_DRAG := 2.5
const DUST_COLORS := [Color("#5a4030"), Color("#7a6250"), Color("#463126"), Color("#8f7a62")]
const ROOST_COLORS := [Color("#5a4030"), Color("#463126"), Color("#7a6250")]
# Engine loop: idle strength, plus throttle and speed (Sfx maps strength to volume and pitch).
const ENGINE_IDLE := 0.12
const ENGINE_THROTTLE := 0.45
const ENGINE_SPEED := 0.45
const ENGINE_AIR_REV := 0.25
const ENGINE_SMOOTHING := 8.0
const RUMBLE_IDLE := 0.15
const RUMBLE_THROTTLE := 0.55
const CRASH_RUMBLE := 1.0
const FINISH_SHAKE := 6.0
