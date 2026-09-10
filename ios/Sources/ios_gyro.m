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
===========================================================================
*/

#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>

#include "../../SP/code/qcommon/q_shared.h"
#include "../../SP/code/qcommon/qcommon.h"
#include "../../SP/code/client/client.h"

extern void IOSTouch_QueueAxis( int axis, int value );
extern int  IOSTouch_ControllerConnected( void );

static CMMotionManager *motionManager = nil;
static cvar_t *in_touchGyro = NULL;
static cvar_t *in_touchGyroSens = NULL;
static cvar_t *in_gyroInvertYaw = NULL;
static cvar_t *in_gyroInvertPitch = NULL;

// Same treatment as the controller's gyro: the resting reading is not zero, so
// it is measured and taken out rather than hidden behind a deadzone.
static double gyroBias[3];
static int    gyroRestSince;
static int    gyroSampleTime;
static int    gyroAxis[2];      // [0] pitch, [1] yaw, as last put on the axes

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

Puts the gyro's contribution on the two joystick axes, but only when it has
changed.

cl.joystickAxis latches -- it keeps whatever was last written until something
writes again -- so falling inside the deadzone and simply returning left the
last reading in place and the view turning at that rate for good. Going quiet
has to be sent, exactly once.
==============
*/
static void Sys_IOS_GyroSetAxes( int pitch, int yaw )
{
	if ( pitch != gyroAxis[0] ) {
		gyroAxis[0] = pitch;
		IOSTouch_QueueAxis( AXIS_GYRO_PITCH, pitch );
	}

	if ( yaw != gyroAxis[1] ) {
		gyroAxis[1] = yaw;
		IOSTouch_QueueAxis( AXIS_GYRO_YAW, yaw );
	}
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

	// Shared with the controller's gyro, registered there too with the same
	// defaults. Whichever of the two comes up first creates them, and a player
	// who has had to flip an axis has flipped it for both.
	in_gyroInvertYaw = Cvar_Get( "in_gyroInvertYaw", "0", CVAR_ARCHIVE );
	in_gyroInvertPitch = Cvar_Get( "in_gyroInvertPitch", "0", CVAR_ARCHIVE );

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
	double magnitude, length, yaw, pitch, scale;
	int now, elapsed, i;

	if ( !motionManager || !in_touchGyro ) {
		return;
	}

	// Off, or the controller's own gyro is doing this job.
	if ( !in_touchGyro->integer || IOSTouch_ControllerConnected() ) {
		if ( motionManager.deviceMotionActive ) {
			[motionManager stopDeviceMotionUpdates];
		}

		// The axes have to be released as well as the sensor. They latch, so a
		// controller arriving mid-turn would otherwise leave this side's last
		// reading on them for the controller's gyro to add to.
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

	// The two shared last resorts, for a device that turns out to measure the
	// other way round. Whichever gyro is in use, the same toggle fixes it.
	if ( in_gyroInvertYaw && in_gyroInvertYaw->integer ) {
		yaw = -yaw;
	}
	if ( in_gyroInvertPitch && in_gyroInvertPitch->integer ) {
		pitch = -pitch;
	}

	// rad/s -> view degrees per second -> axis units. CL_JoystickMove scales by
	// frametime, which is exactly right for a rate.
	scale = in_touchGyroSens->value * TOUCH_GYRO_VIEW_DEGREES_PER_RAD *
		TOUCH_GYRO_AXIS_SCALE;

	Sys_IOS_GyroSetAxes(
		(int)Com_Clamp( -32767.0f, 32767.0f, (float)( pitch * scale ) ),
		(int)Com_Clamp( -32767.0f, 32767.0f, (float)( yaw * scale ) ) );
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

	// The axes keep their last value, so leaving without clearing them would
	// leave the view turning at whatever rate the sensor last reported.
	Sys_IOS_GyroSetAxes( 0, 0 );

	Com_Memset( gyroBias, 0, sizeof( gyroBias ) );
	gyroRestSince = 0;
	gyroSampleTime = 0;
}
