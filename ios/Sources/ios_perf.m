/*
===========================================================================
Performance readout for the iPad build.

A single thin line along the top of the screen, the way a console shooter shows
one: small, dim, and out of the way of anything you need to look at. It sits
inside the safe area, so the rounded corners and the camera housing never clip
it.

Everything it shows is also written to main/perf.csv when r_perfLog is on, one
row a second, so a session can be looked at afterwards rather than read off the
screen while playing.

A word on GPU: iOS has no public API for GPU utilisation. What is reported here
is the time the frame spends in the buffer swap, which is where a
GPU-bound frame waits, so it is a usable signal for "the GPU is the problem"
without pretending to be a percentage.
===========================================================================
*/

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>

#include "../../SP/code/qcommon/q_shared.h"
#include "../../SP/code/qcommon/qcommon.h"
#include "../../SP/code/client/client.h"

static UILabel   *perfLabel = nil;
static cvar_t    *r_perfHud = NULL;
static cvar_t    *r_perfLog = NULL;

// Frame timing, over a one second window.
static double    perfWindowStart;
static int       perfFrames;
static double    perfFrameTotal;      // ms
static double    perfFrameWorst;      // ms
static double    perfLastFrameStart;

// Swap time, filled in by the renderer.
static double    perfSwapTotal;       // ms
static int       perfSwapCount;

// CPU, sampled as a delta of the process's own thread time.
static double    perfCpuLast;         // seconds of CPU consumed at the last sample
static double    perfCpuWallLast;
static double    perfCpuPercent;

static fileHandle_t perfLogFile;
static qboolean     perfLogOpen;

/*
==============
IOSPerf_CPUSeconds

Total CPU time this process has used, live threads and finished ones together.
==============
*/
static double IOSPerf_CPUSeconds( void )
{
	task_thread_times_info_data_t threads;
	task_basic_info_data_t basic;
	mach_msg_type_number_t count;
	double total = 0.0;

	count = TASK_THREAD_TIMES_INFO_COUNT;
	if ( task_info( mach_task_self(), TASK_THREAD_TIMES_INFO,
			(task_info_t)&threads, &count ) == KERN_SUCCESS ) {
		total += threads.user_time.seconds + threads.user_time.microseconds / 1.0e6;
		total += threads.system_time.seconds + threads.system_time.microseconds / 1.0e6;
	}

	count = TASK_BASIC_INFO_COUNT;
	if ( task_info( mach_task_self(), TASK_BASIC_INFO,
			(task_info_t)&basic, &count ) == KERN_SUCCESS ) {
		total += basic.user_time.seconds + basic.user_time.microseconds / 1.0e6;
		total += basic.system_time.seconds + basic.system_time.microseconds / 1.0e6;
	}

	return total;
}

/*
==============
IOSPerf_FootprintMB

What Xcode's memory gauge shows: the pages this process is actually charged for.
==============
*/
static double IOSPerf_FootprintMB( void )
{
	task_vm_info_data_t info;
	mach_msg_type_number_t count = TASK_VM_INFO_COUNT;

	if ( task_info( mach_task_self(), TASK_VM_INFO,
			(task_info_t)&info, &count ) != KERN_SUCCESS ) {
		return 0.0;
	}

	return (double)info.phys_footprint / ( 1024.0 * 1024.0 );
}

/*
==============
Sys_IOS_PerfInit

The strip is a child of the touch overlay's window, which already sits above
the game and already handles the safe area.
==============
*/
void Sys_IOS_PerfInit( void *parentView )
{
	UIView *parent = (__bridge UIView *)parentView;

	if ( perfLabel || !parent ) {
		return;
	}

	r_perfHud = Cvar_Get( "r_perfHud", "0", CVAR_ARCHIVE );
	r_perfLog = Cvar_Get( "r_perfLog", "0", CVAR_ARCHIVE );

	perfLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	perfLabel.font = [UIFont monospacedDigitSystemFontOfSize:13
													  weight:UIFontWeightMedium];
	perfLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
	perfLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
	perfLabel.textAlignment = NSTextAlignmentCenter;
	perfLabel.layer.cornerRadius = 7.0;
	perfLabel.layer.masksToBounds = YES;
	perfLabel.userInteractionEnabled = NO;
	perfLabel.hidden = YES;
	perfLabel.text = @"";

	[parent addSubview:perfLabel];

	perfWindowStart = CACurrentMediaTime();
	perfCpuLast = IOSPerf_CPUSeconds();
	perfCpuWallLast = perfWindowStart;
}

/*
==============
Sys_IOS_PerfNoteSwap

Called by the renderer with the milliseconds the buffer swap took.
==============
*/
void Sys_IOS_PerfNoteSwap( double ms )
{
	perfSwapTotal += ms;
	perfSwapCount++;
}

static void IOSPerf_WriteRow( double fps, double avg, double worst, double swap,
							  double cpu, double mem, int ents )
{
	char line[256];

	if ( !r_perfLog || !r_perfLog->integer ) {
		if ( perfLogOpen ) {
			FS_FCloseFile( perfLogFile );
			perfLogOpen = qfalse;
		}
		return;
	}

	if ( !perfLogOpen ) {
		perfLogFile = FS_FOpenFileWrite( "perf.csv" );

		if ( !perfLogFile ) {
			Cvar_Set( "r_perfLog", "0" );
			return;
		}

		perfLogOpen = qtrue;
		Q_strncpyz( line, "time,fps,frame_ms,worst_ms,swap_ms,cpu_pct,mem_mb,ents,map\n",
			sizeof( line ) );
		FS_Write( line, strlen( line ), perfLogFile );
	}

	Com_sprintf( line, sizeof( line ), "%.1f,%.1f,%.2f,%.2f,%.2f,%.0f,%.1f,%d,%s\n",
		(double)Sys_Milliseconds() / 1000.0, fps, avg, worst, swap, cpu, mem, ents,
		cl.mapname[0] ? cl.mapname : "-" );

	FS_Write( line, strlen( line ), perfLogFile );
	FS_Flush( perfLogFile );
}

/*
==============
Sys_IOS_PerfFrame

Once per client frame. Samples are averaged over a second: a number that changes
every frame cannot be read, and the worst frame in the second is the one that
tells you whether it stutters.
==============
*/
void Sys_IOS_PerfFrame( void )
{
	double now = CACurrentMediaTime();
	double elapsed;

	if ( !perfLabel ) {
		return;
	}

	if ( perfLastFrameStart > 0.0 ) {
		double ms = ( now - perfLastFrameStart ) * 1000.0;

		perfFrames++;
		perfFrameTotal += ms;

		if ( ms > perfFrameWorst ) {
			perfFrameWorst = ms;
		}
	}
	perfLastFrameStart = now;

	if ( r_perfHud && perfLabel.hidden == ( r_perfHud->integer ? YES : NO ) ) {
		perfLabel.hidden = r_perfHud->integer ? NO : YES;
	}

	elapsed = now - perfWindowStart;

	if ( elapsed < 0.5 ) {
		return;
	}

	{
		double fps   = perfFrames / elapsed;
		double avg   = perfFrames ? perfFrameTotal / perfFrames : 0.0;
		double worst = perfFrameWorst;
		double swap  = perfSwapCount ? perfSwapTotal / perfSwapCount : 0.0;
		double mem   = IOSPerf_FootprintMB();
		double cpuNow = IOSPerf_CPUSeconds();
		int    ents  = ( clc.state == CA_ACTIVE ) ? cl.snap.numEntities : 0;

		if ( now > perfCpuWallLast ) {
			perfCpuPercent = 100.0 * ( cpuNow - perfCpuLast ) / ( now - perfCpuWallLast );
		}
		perfCpuLast = cpuNow;
		perfCpuWallLast = now;

		if ( r_perfHud && r_perfHud->integer ) {
			UIView *parent = perfLabel.superview;
			CGFloat top = parent ? parent.safeAreaInsets.top : 0.0;
			CGFloat width = 420.0;

			perfLabel.text = [NSString stringWithFormat:
				@"%.0f FPS   %.1f/%.1f ms   swap %.1f   cpu %.0f%%   %.0f MB   ent %d",
				fps, avg, worst, swap, perfCpuPercent, mem, ents];

			// Under the safe area rather than at the very edge: on this iPad the
			// top inset is where the rounded corners eat into the screen.
			perfLabel.frame = CGRectMake(
				( parent.bounds.size.width - width ) * 0.5f,
				top + 4.0f, width, 22.0f );
		}

		IOSPerf_WriteRow( fps, avg, worst, swap, perfCpuPercent, mem, ents );

		perfWindowStart = now;
		perfFrames = 0;
		perfFrameTotal = 0.0;
		perfFrameWorst = 0.0;
		perfSwapTotal = 0.0;
		perfSwapCount = 0;
	}
}
