/*
===========================================================================
Gyro aiming from the iPad's own motion sensor, for playing without a
controller.

It is meant for the last few degrees of aim, not for turning: the thumb on the
look area still does the large movements and the wrist trims the shot. That is
how gyro aiming is played everywhere it works well, and it is why the default
sensitivity here is low.

The axes are worked out from gravity rather than from the interface
orientation, so it behaves the same whichever way round the iPad is held and
does not have to be told:

  yaw   -- rotation about the direction gravity points, which is turning the
           whole device like a steering wheel laid flat
  pitch -- rotation about the horizontal axis lying in the screen, which is
           tipping the far edge up and down

Both come out of one dot product each, and neither needs a special case.

The two axes are handed over in the same units and the same convention as the
controller's gyro in IN_GamepadGyro -- view degrees per second times
GYRO_AXIS_SCALE, positive yaw to the right and positive pitch downwards -- so a
player who puts the pad down mid-mission does not find the aim answering
differently to the same movement.

Sharing that convention is not the same as sharing the sensor, and two things
follow from it:

  in_touchGyro decides whether this one runs at all, and at 2 it runs alongside
  the controller's gyro rather than instead of it. The two contributions are
  added, which is why neither side writes the joystick axes directly any more:
  both hand their numbers to IN_GyroContribute in sdl_input.c and the total goes
  out once a frame. The comment there explains why writing them cannot work.

  The inversion toggles are this sensor's own -- in_touchGyroInvertYaw and
  in_touchGyroInvertPitch -- and no longer the controller's in_gyroInvert*. One
  pair for both looked like it kept the two gyros in agreement, but there is
  nothing here for them to agree about: the controller reports in the frame SDL
  documents for its own body, this builds its axes out of the gravity vector,
  and whether either comes out backwards on a given device is settled
  separately. Sharing the toggle only meant that a player who flipped the
  horizontal to suit the pad flipped the tablet's the wrong way in the same
  breath.
===========================================================================
*/

#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>

#include "../../SP/code/qcommon/q_shared.h"
#include "../../SP/code/qcommon/qcommon.h"
#include "../../SP/code/client/client.h"

extern void IOSTouch_SetTabletGyro( int pitch, int yaw );
extern int  IOSTouch_ControllerConnected( void );

static CMMotionManager *motionManager = nil;
static cvar_t *in_touchGyro = NULL;
static cvar_t *in_touchGyroSens = NULL;
static cvar_t *in_touchGyroYawSens = NULL;
static cvar_t *in_touchGyroPitchSens = NULL;
static cvar_t *in_touchGyroInvertYaw = NULL;
static cvar_t *in_touchGyroInvertPitch = NULL;

// Same treatment as the controller's gyro: the resting reading is not zero, so
// it is measured and taken out rather than hidden behind a deadzone.
static double gyroBias[3];
static int    gyroRestSince;
static int    gyroSampleTime;

// What in_touchGyro selects. It is a switch with an extra notch rather than a
// number, and the notch in the middle is what this cvar has always done, left
// where it was so that a config already carrying in_touchGyro 1 plays exactly
// as it did before any of this was written.
//
// Standing aside for a controller is a deliberate default rather than a
// leftover of the old wiring: a player who has picked up a pad is aiming with
// the pad, and an iPad propped on a table or shifting about in a case has no
// business adding its own movements to that. ALWAYS is for the player who has
// both in his hands at once and wants the tablet's wrist trim on top of the
// pad's gyro -- the two are added, not chosen between.
#define TOUCH_GYRO_OFF     0   // never
#define TOUCH_GYRO_NO_PAD  1   // only while no controller is in use
#define TOUCH_GYRO_ALWAYS  2   // always, added to the controller's gyro

#define TOUCH_GYRO_REST_RATE  0.030   // rad/s; below anything done on purpose
#define TOUCH_GYRO_DEADZONE   0.012   // rad/s; what is left after the bias
#define TOUCH_GYRO_SETTLE     250     // ms of stillness before the bias is believed
#define TOUCH_GYRO_BIAS_TAU   0.4     // seconds; how fast the estimate converges

// Must match GYRO_VIEW_DEGREES_PER_RAD and GYRO_AXIS_SCALE in sdl_input.c, and
// GYRO_AXIS_SCALE in cl_input.c. The first is what the sensitivity means -- at
// in_touchGyroSens 1.0 the view turns this many degrees a second for each rad/s
// of real rotation -- and the second is only the resolution the integer axis
// carries it in.
#define TOUCH_GYRO_VIEW_DEGREES_PER_RAD  180.2185
#define TOUCH_GYRO_AXIS_SCALE            32.0

/*
==============
Sys_IOS_GyroSetAxes

Hands this sensor's contribution to the input side, which adds it to the
controller's and writes the axes once a frame.

Both the sending-only-on-change and the writing itself used to live here. They
had to move: cl.joystickAxis latches -- it keeps whatever was last written until
something writes again -- and with two gyros writing the same pair of axes the
one that happened to speak second simply erased the other. The rule that made
the latch safe still holds and is now IN_GyroContribute's to keep: going quiet
has to be said, which is why the early exits below all pass through here with
zeroes rather than just returning.
==============
*/
static void Sys_IOS_GyroSetAxes( int pitch, int yaw )
{
	IOSTouch_SetTabletGyro( pitch, yaw );
}

/*
==============
Sys_IOS_GyroAxisSens

Picks between a sensitivity set for this axis and the one set for both. The
twin of IN_AxisSens in sdl_input.c, which carries the long version of why zero
means "nothing set here" rather than "do not move": it is what lets a config
that already has a tuned in_touchGyroSens in it go on playing exactly as it did.
==============
*/
static double Sys_IOS_GyroAxisSens( const cvar_t *axis )
{
	if ( axis && axis->value > 0.0f ) {
		return axis->value;
	}

	return in_touchGyroSens->value;
}

/*
==============
Sys_IOS_GyroDeadzone

Takes the deadzone off a rate rather than cutting at it, so that whatever bias
is left in a reading does not arrive at full strength the moment the reading
clears the threshold. See IN_GyroDeadzone in sdl_input.c, which does the same
for the controller and explains it at length.
==============
*/
static double Sys_IOS_GyroDeadzone( double rate )
{
	if ( rate > TOUCH_GYRO_DEADZONE ) {
		return rate - TOUCH_GYRO_DEADZONE;
	}

	if ( rate < -TOUCH_GYRO_DEADZONE ) {
		return rate + TOUCH_GYRO_DEADZONE;
	}

	return 0.0;
}

/*
==============
Sys_IOS_GyroInit
==============
*/
void Sys_IOS_GyroInit( void )
{
	if ( motionManager ) {
		return;
	}

	in_touchGyro = Cvar_Get( "in_touchGyro", "0", CVAR_ARCHIVE );
	in_touchGyroSens = Cvar_Get( "in_touchGyroSens", "1.0", CVAR_ARCHIVE );

	// Horizontal and vertical separately, zero meaning "leave this axis to
	// in_touchGyroSens". Both start at zero so that a config already carrying a
	// sensitivity somebody sat down and tuned is untouched by this being added.
	in_touchGyroYawSens = Cvar_Get( "in_touchGyroYawSens", "0", CVAR_ARCHIVE );
	in_touchGyroPitchSens = Cvar_Get( "in_touchGyroPitchSens", "0", CVAR_ARCHIVE );

	Cvar_CheckRange( in_touchGyroYawSens, 0.0f, 10.0f, qfalse );
	Cvar_CheckRange( in_touchGyroPitchSens, 0.0f, 10.0f, qfalse );

	// in_touchGyro is read as one of three named states rather than as a number,
	// so it is clamped rather than trusted: a hand-edited config carrying a 3
	// would match none of them and the sensor would go quiet with no way to see
	// why. The default stays 0 -- this has never been on unless asked for.
	Cvar_CheckRange( in_touchGyro, TOUCH_GYRO_OFF, TOUCH_GYRO_ALWAYS, qtrue );

	// This sensor's own, not the controller's in_gyroInvert*. Off by default
	// because the axes above are built from gravity and should already come out
	// the right way round; they are here because if they do not, there is no way
	// to tell from in here and no way for the player to find out but to try it.
	//
	// Separate from the controller's pair because the two sensors do not share a
	// frame of reference -- see the block at the top of this file -- so the signs
	// that are right for one say nothing about the other.
	in_touchGyroInvertYaw = Cvar_Get( "in_touchGyroInvertYaw", "0", CVAR_ARCHIVE );
	in_touchGyroInvertPitch = Cvar_Get( "in_touchGyroInvertPitch", "0", CVAR_ARCHIVE );

	motionManager = [[CMMotionManager alloc] init];

	if ( !motionManager.deviceMotionAvailable ) {
		Com_Printf( "Gyro: no device motion on this device\n" );
		motionManager = nil;
		return;
	}

	// 120Hz, to match the display. Device motion rather than raw gyro data
	// because it comes with gravity already separated out, which is what the
	// axes below are built from.
	motionManager.deviceMotionUpdateInterval = 1.0 / 120.0;

	Com_Printf( "Gyro: device motion available\n" );
}

/*
==============
Sys_IOS_GyroFrame
==============
*/
void Sys_IOS_GyroFrame( void )
{
	CMDeviceMotion *motion;
	double rate[3], gravity[3], horizontal[3];
	double magnitude, length, yaw, pitch, yawScale, pitchScale;
	int now, elapsed, i;

	if ( !motionManager || !in_touchGyro ) {
		// No sensor on this device, or too early to have a cvar to read. Nothing
		// is ever going to come out of here, so say so rather than leave whatever
		// was last handed over standing in the sum.
		Sys_IOS_GyroSetAxes( 0, 0 );
		return;
	}

	// Off, or set to stand aside while the controller's own gyro does this job.
	// At TOUCH_GYRO_ALWAYS neither of those applies and the sensor keeps running
	// with a pad connected, which is the whole of the difference: what comes out
	// of here is added to the controller's contribution rather than replacing it.
	if ( in_touchGyro->integer == TOUCH_GYRO_OFF ||
		( in_touchGyro->integer == TOUCH_GYRO_NO_PAD && IOSTouch_ControllerConnected() ) ) {
		if ( motionManager.deviceMotionActive ) {
			[motionManager stopDeviceMotionUpdates];
		}

		// The contribution has to be released as well as the sensor. It is held
		// until replaced, so a controller arriving mid-turn would otherwise leave
		// this side's last reading in the sum for the controller's gyro to be
		// added to for the rest of the session.
		Sys_IOS_GyroSetAxes( 0, 0 );
		gyroSampleTime = 0;
		return;
	}

	if ( !motionManager.deviceMotionActive ) {
		[motionManager startDeviceMotionUpdates];

		// A fresh sensor: what was learned before the pause describes a device
		// that has since been carried about, warmed up or cooled down.
		Com_Memset( gyroBias, 0, sizeof( gyroBias ) );
		gyroRestSince = 0;
		gyroSampleTime = 0;
		return;
	}

	motion = motionManager.deviceMotion;

	if ( !motion ) {
		return;
	}

	now = Sys_Milliseconds();
	elapsed = gyroSampleTime ? now - gyroSampleTime : 0;
	gyroSampleTime = now;

	rate[0] = motion.rotationRate.x;
	rate[1] = motion.rotationRate.y;
	rate[2] = motion.rotationRate.z;

	gravity[0] = motion.gravity.x;
	gravity[1] = motion.gravity.y;
	gravity[2] = motion.gravity.z;

	magnitude = 0.0;
	for ( i = 0; i < 3; i++ ) {
		rate[i] -= gyroBias[i];
		magnitude += rate[i] * rate[i];
	}

	if ( magnitude < TOUCH_GYRO_REST_RATE * TOUCH_GYRO_REST_RATE ) {
		if ( !gyroRestSince ) {
			gyroRestSince = now;
		}

		if ( now - gyroRestSince > TOUCH_GYRO_SETTLE ) {
			// Per second rather than per frame. This is polled once a frame, not
			// at the 120Hz the sensor was asked for, so a fixed fraction made the
			// estimate converge at whatever rate the renderer happened to manage.
			double converge = elapsed * 0.001 / TOUCH_GYRO_BIAS_TAU;

			if ( converge > 1.0 ) {
				converge = 1.0;
			}

			for ( i = 0; i < 3; i++ ) {
				gyroBias[i] += rate[i] * converge;
			}
		}
	} else {
		gyroRestSince = 0;
	}

	// Turning about gravity is yaw, whichever way the device is held.
	//
	// The sign is the player's, not the maths'. gravity points down, so turning
	// the iPad to the left -- the rotation vector pointing up, against gravity
	// -- makes this dot product negative, and the axes below want positive for
	// a view that turns right. Taking the dot product as it comes is therefore
	// what makes tilting left look left. It used to be negated here, which is
	// why the view went the opposite way to the hands.
	yaw = rate[0] * gravity[0] + rate[1] * gravity[1] + rate[2] * gravity[2];

	// The horizontal axis of the screen is perpendicular to both gravity and
	// the screen's normal, which in the device's own frame is simply z.
	horizontal[0] =  gravity[1];
	horizontal[1] = -gravity[0];
	horizontal[2] =  0.0;

	length = sqrt( horizontal[0] * horizontal[0] + horizontal[1] * horizontal[1] );

	if ( length > 0.001 ) {
		horizontal[0] /= length;
		horizontal[1] /= length;

		// horizontal points to the left of the screen, and raising the far edge
		// is a rotation about it in the positive sense, so this dot product is
		// positive for exactly the movement that should look up -- and the
		// pitch axis wants a negative for looking up. Hence the negation. This
		// axis was already the right way round and is left as it was.
		pitch = -( rate[0] * horizontal[0] + rate[1] * horizontal[1] );
	} else {
		// The iPad is lying flat: there is no horizontal axis on the screen to
		// speak of, so leave pitch alone rather than invent one.
		pitch = 0.0;
	}

	yaw = Sys_IOS_GyroDeadzone( yaw );
	pitch = Sys_IOS_GyroDeadzone( pitch );

	// in_invertLook is deliberately not read here, unlike in IN_GamepadGyro.
	// There it keeps the gyro pointing the same way as the stick it is being
	// added to; here the thing being added to is the finger on the look area,
	// which goes through CL_MouseMove and has never honoured that cvar.
	// Honouring it on one half of tablet aiming and not the other is the exact
	// fault being fixed on the controller side.

	// The two last resorts, for a device that turns out to measure the other way
	// round. This sensor's own toggles: the controller's in_gyroInvert* pair used
	// to be read here as well, and a horizontal flipped to suit a DualSense was
	// flipping this one too, in the opposite direction to what the hands were
	// asking for. The frames of reference are unrelated, so the signs are.
	if ( in_touchGyroInvertYaw && in_touchGyroInvertYaw->integer ) {
		yaw = -yaw;
	}
	if ( in_touchGyroInvertPitch && in_touchGyroInvertPitch->integer ) {
		pitch = -pitch;
	}

	// rad/s -> view degrees per second -> axis units. CL_JoystickMove scales by
	// frametime, which is exactly right for a rate.
	//
	// A scale each. Turning the iPad about gravity is a movement of the whole
	// forearm and tipping its far edge is a movement of the wrist alone, so the
	// horizontal and the vertical never wanted the same number; in_touchGyroSens
	// still sets both until one of the per-axis keys is given a value of its own.
	yawScale = Sys_IOS_GyroAxisSens( in_touchGyroYawSens ) *
		TOUCH_GYRO_VIEW_DEGREES_PER_RAD * TOUCH_GYRO_AXIS_SCALE;
	pitchScale = Sys_IOS_GyroAxisSens( in_touchGyroPitchSens ) *
		TOUCH_GYRO_VIEW_DEGREES_PER_RAD * TOUCH_GYRO_AXIS_SCALE;

	// Scaled before the contribution is handed over, not after the two gyros are
	// added: this sensor's sensitivity has to mean how much this sensor moves the
	// view, whatever the controller happens to be doing at the same moment.
	Sys_IOS_GyroSetAxes(
		(int)Com_Clamp( -32767.0f, 32767.0f, (float)( pitch * pitchScale ) ),
		(int)Com_Clamp( -32767.0f, 32767.0f, (float)( yaw * yawScale ) ) );
}

/*
==============
Sys_IOS_GyroShutdown
==============
*/
void Sys_IOS_GyroShutdown( void )
{
	if ( motionManager ) {
		[motionManager stopDeviceMotionUpdates];
		motionManager = nil;
	}

	// The contribution is held until replaced, so leaving without clearing it
	// would leave the view turning at whatever rate the sensor last reported --
	// and, with a controller also aiming, would go on being added to its gyro.
	Sys_IOS_GyroSetAxes( 0, 0 );

	Com_Memset( gyroBias, 0, sizeof( gyroBias ) );
	gyroRestSince = 0;
	gyroSampleTime = 0;
}
