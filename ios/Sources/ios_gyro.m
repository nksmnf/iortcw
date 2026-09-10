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

// Same treatment as the controller's gyro: the resting reading is not zero, so
// it is measured and taken out rather than hidden behind a deadzone.
static double gyroBias[3];
static int    gyroRestSince;

#define TOUCH_GYRO_REST_RATE  0.030   // rad/s; below anything done on purpose
#define TOUCH_GYRO_DEADZONE   0.012   // rad/s; what is left after the bias

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
	int i;

	if ( !motionManager || !in_touchGyro ) {
		return;
	}

	// Off, or the controller's own gyro is doing this job.
	if ( !in_touchGyro->integer || IOSTouch_ControllerConnected() ) {
		if ( motionManager.deviceMotionActive ) {
			[motionManager stopDeviceMotionUpdates];
		}
		return;
	}

	if ( !motionManager.deviceMotionActive ) {
		[motionManager startDeviceMotionUpdates];
		return;
	}

	motion = motionManager.deviceMotion;

	if ( !motion ) {
		return;
	}

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
			gyroRestSince = Sys_Milliseconds();
		}

		if ( Sys_Milliseconds() - gyroRestSince > 250 ) {
			for ( i = 0; i < 3; i++ ) {
				gyroBias[i] += rate[i] * 0.02;
			}
		}
	} else {
		gyroRestSince = 0;
	}

	// Turning about gravity is yaw, whichever way the device is held.
	yaw = -( rate[0] * gravity[0] + rate[1] * gravity[1] + rate[2] * gravity[2] );

	// The horizontal axis of the screen is perpendicular to both gravity and
	// the screen's normal, which in the device's own frame is simply z.
	horizontal[0] =  gravity[1];
	horizontal[1] = -gravity[0];
	horizontal[2] =  0.0;

	length = sqrt( horizontal[0] * horizontal[0] + horizontal[1] * horizontal[1] );

	if ( length > 0.001 ) {
		horizontal[0] /= length;
		horizontal[1] /= length;

		pitch = -( rate[0] * horizontal[0] + rate[1] * horizontal[1] );
	} else {
		// The iPad is lying flat: there is no horizontal axis on the screen to
		// speak of, so leave pitch alone rather than invent one.
		pitch = 0.0;
	}

	if ( fabs( yaw ) < TOUCH_GYRO_DEADZONE ) {
		yaw = 0.0;
	}
	if ( fabs( pitch ) < TOUCH_GYRO_DEADZONE ) {
		pitch = 0.0;
	}

	if ( yaw == 0.0 && pitch == 0.0 ) {
		return;
	}

	// rad/s into the range the joystick axis path expects. CL_JoystickMove
	// scales by frametime, which is exactly right for a rate.
	scale = in_touchGyroSens->value * 32767.0 / 4.0;

	IOSTouch_QueueAxis( AXIS_GYRO_YAW,
		(int)Com_Clamp( -32767.0f, 32767.0f, (float)( yaw * scale ) ) );
	IOSTouch_QueueAxis( AXIS_GYRO_PITCH,
		(int)Com_Clamp( -32767.0f, 32767.0f, (float)( pitch * scale ) ) );
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
}
