/*
===========================================================================
Performance readout for the iPad build.

A single thin line along the top of the screen, the way a console shooter shows
one: small, dim, and out of the way of anything you need to look at. It sits
inside the safe area, so the rounded corners and the camera housing never clip
it.

Everything it shows is also written to main/perf.csv when r_perfLog is on, a
row every half second, so a session can be looked at afterwards rather than
read off the screen while playing. Half a second, not one: anything periodic in
the engine wants a sampling window shorter than its own period, or it hides in
the average.

A word on each number, because a readout nobody can read is decoration:

  CPU  the whole process -- every thread together -- against wall clock time,
       which is top's convention: 100% is one core saturated, not the machine.
       The figure after the slash is what the machine has, so 140%/800% on an
       eight-core iPad reads as "one core and a bit", not as a tablet in
       trouble. Without that second figure the first one is unreadable: the
       engine runs its renderer on its own thread and passes 100% routinely.
  GPU  iOS exposes no GPU utilisation to ask for. What is reported is the time
       the frame spends waiting in the buffer swap -- where a GPU-bound frame
       waits -- and what share of the frame that is.
  RSS  the physical pages this process has resident right now.
  VM   the address space it has mapped. On a 64-bit process most of that is
       reserved rather than used, so it is worth watching for growth and not
       for its absolute size.

The number iOS actually kills a process over is neither of the two memory
figures above but the phys_footprint, which is what Xcode's gauge shows; it has
no room on the strip and goes to the log beside them.
===========================================================================
*/

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#include <stdatomic.h>

#include "ios_engine.h"
#ifdef IORTCW_MP_BUILD
#include "../../MP/code/client/client.h"
#else
#include "../../SP/code/client/client.h"
#endif

static UILabel   *perfLabel = nil;
static cvar_t    *r_perfHud = NULL;
static cvar_t    *r_perfLog = NULL;

// Frame timing, over a half second window.
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
static double    perfCpuPercent;      // 100% is one core, as in top
static int       perfCores;           // what that percentage is out of

static fileHandle_t perfLogFile;
static qboolean     perfLogOpen;
static int          perfLogRows;

// The display's actual cadence, measured rather than assumed.
static CADisplayLink *perfDisplayLink = nil;
static double         perfRefreshHz;

/*
==============
IORTCWDisplayLinkTarget

A running display link that asks for 120Hz and reports what it actually gets.
Two jobs in one object because they are the same fact from either side.

The asking matters: ProMotion is adaptive, and with nothing declaring a
preferred range CoreAnimation is free to settle the panel at 80Hz, which is
exactly what a 12.6ms frame at 30% CPU turns out to be -- the game waiting on a
slower display, not the game running out of time.
==============
*/
@interface IORTCWDisplayLinkTarget : NSObject
@end

@implementation IORTCWDisplayLinkTarget

- (void)tick:(CADisplayLink *)link
{
	double period = link.targetTimestamp - link.timestamp;

	if ( period > 0.0 ) {
		perfRefreshHz = 1.0 / period;
	}
}

@end

static IORTCWDisplayLinkTarget *perfLinkTarget = nil;

// Filled in by the renderer's backend, which is counting these anyway for
// r_speeds. Declared here rather than routed through refexport_t: the renderer
// is linked into this binary, and a readout that needs an ABI change is a
// readout nobody adds.
extern void R_GetPerfCounters( int *surfaces, int *tris, int *shaders );

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
IOSPerf_SampleMemory

Three numbers out of the one call: the resident pages, the mapped address
space, and the footprint this process is charged for -- what Xcode's memory
gauge shows and what the system counts before it kills anything.

Sampled on a background queue and published for the next window to read.
task_info( TASK_VM_INFO ) takes the task's virtual memory map lock, and a
readout that stops the frame thread to ask how the frame thread is doing is a
readout measuring itself. Being one window stale costs the numbers nothing.

They are published as three separate atomics rather than under a lock: a reader
that catches one sample's resident size beside the next sample's virtual size
is reading two numbers half a second apart, and at this refresh rate that is
not a difference anyone can see.
==============
*/
static _Atomic double perfFootprint;      // MB, written by the sampler
static _Atomic double perfRss;            // MB, resident pages
static _Atomic double perfVm;             // MB, mapped address space
static atomic_bool    perfMemoryBusy;

static void IOSPerf_SampleMemory( void )
{
	if ( atomic_exchange( &perfMemoryBusy, true ) ) {
		return;       // one is still in flight
	}

	dispatch_async( dispatch_get_global_queue( QOS_CLASS_UTILITY, 0 ), ^{
		task_vm_info_data_t info;
		mach_msg_type_number_t count = TASK_VM_INFO_COUNT;

		if ( task_info( mach_task_self(), TASK_VM_INFO,
				(task_info_t)&info, &count ) == KERN_SUCCESS ) {
			const double megabyte = 1024.0 * 1024.0;

			atomic_store( &perfFootprint, (double)info.phys_footprint / megabyte );
			atomic_store( &perfRss, (double)info.resident_size / megabyte );
			atomic_store( &perfVm, (double)info.virtual_size / megabyte );
		}

		atomic_store( &perfMemoryBusy, false );
	} );
}

/*
==============
IOSPerf_FormatBytes

Megabytes below a gigabyte and gigabytes above it. The mapped address space of
a 64-bit process runs into the tens of gigabytes, and five figures of megabytes
is not a number anyone reads at a glance.
==============
*/
static void IOSPerf_FormatBytes( double mb, char *out, size_t size )
{
	if ( mb >= 1024.0 ) {
		snprintf( out, size, "%.1f GB", mb / 1024.0 );
	} else {
		snprintf( out, size, "%.0f MB", mb );
	}
}

/*
==============
Sys_IOS_RefreshHz

The panel's measured cadence, or 0 before the display link has ticked.

The frame limiter in common.c needs it: com_maxfps is an integer, 1000/120 is
8, and an 8ms budget against an 8.33ms panel beats against it. ProMotion does
not announce a fixed rate, so the measured value is the only honest one.
==============
*/
double Sys_IOS_RefreshHz( void )
{
	return perfRefreshHz;
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
	// Fully monospaced, not just the digits: the fields are padded to a fixed
	// width, and padding only holds the line still if the space is a digit's
	// width too. Otherwise the strip shifts every time the frame time crosses
	// ten and gains a character.
	perfLabel.font = [UIFont monospacedSystemFontOfSize:12
												 weight:UIFontWeightMedium];
	perfLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
	perfLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
	perfLabel.textAlignment = NSTextAlignmentCenter;
	perfLabel.layer.cornerRadius = 7.0;
	perfLabel.layer.masksToBounds = YES;
	perfLabel.userInteractionEnabled = NO;
	// The strip carries four process figures now as well as the frame ones, so
	// it is sized to its text rather than to a fixed width. In portrait even
	// that can run past the screen, and a line that shrinks by a tenth is
	// readable where a truncated one is not.
	perfLabel.adjustsFontSizeToFitWidth = YES;
	perfLabel.minimumScaleFactor = 0.65;
	perfLabel.numberOfLines = 1;
	perfLabel.hidden = YES;
	perfLabel.text = @"";

	[parent addSubview:perfLabel];

	perfLinkTarget = [[IORTCWDisplayLinkTarget alloc] init];
	perfDisplayLink = [CADisplayLink displayLinkWithTarget:perfLinkTarget
												  selector:@selector(tick:)];

	if ( @available( iOS 15.0, * ) ) {
		// Ask for the panel's full rate. Without this the system is entitled to
		// pick something slower and usually does.
		perfDisplayLink.preferredFrameRateRange =
			CAFrameRateRangeMake( 80.0f, 120.0f, 120.0f );
	}

	[perfDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

	perfWindowStart = CACurrentMediaTime();
	perfCpuLast = IOSPerf_CPUSeconds();
	perfCpuWallLast = perfWindowStart;
	perfCores = (int)[NSProcessInfo processInfo].activeProcessorCount;
}

/*
==============
Sys_IOS_PerfSeconds

A monotonic clock with better than millisecond resolution, for the one caller
that needs one: the buffer swap. Sys_Milliseconds answers in whole
milliseconds, and a swap at 120Hz is a couple of them -- measured in integers
the GPU field reads 0, 1 or 2 and never says which way it is moving.
==============
*/
double Sys_IOS_PerfSeconds( void )
{
	return CACurrentMediaTime();
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

static void IOSPerf_WriteRow( double fps, double avg, double worst, double gpu,
							  double gpuPct, double cpu, int cores, double rss,
							  double vm, double footprint, int ents,
							  int surfs, int tris, int shaders )
{
	char line[320];

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
		perfLogRows = 0;
		Q_strncpyz( line, "time,fps,frame_ms,worst_ms,gpu_ms,gpu_pct,cpu_pct,cores,rss_mb,vm_mb,footprint_mb,ents,refresh_hz,maxfps,surfs,tris,shaders,map\n",
			sizeof( line ) );
		FS_Write( line, strlen( line ), perfLogFile );
	}

	Com_sprintf( line, sizeof( line ), "%.1f,%.1f,%.2f,%.2f,%.2f,%.1f,%.0f,%d,%.1f,%.1f,%.1f,%d,%.1f,%d,%d,%d,%d,%s\n",
		(double)Sys_Milliseconds() / 1000.0, fps, avg, worst, gpu, gpuPct,
		cpu, cores, rss, vm, footprint, ents,
		perfRefreshHz, Cvar_VariableIntegerValue( "com_maxfps" ),
		surfs, tris, shaders,
		cl.mapname[0] ? cl.mapname : "-" );

	FS_Write( line, strlen( line ), perfLogFile );

	// Flushed now and then rather than on every row. fflush is a write(2) on
	// the frame thread, and this runs at the end of a sampling window -- which
	// is exactly where the worst-frame column is looking for a stall, so a log
	// flushing every row ends up measuring its own syscall. Sixteen rows is
	// eight seconds lost if the app is killed outright, against a syscall per
	// window for the whole session.
	if ( ++perfLogRows >= 16 ) {
		perfLogRows = 0;
		FS_Flush( perfLogFile );
	}
}

/*
==============
Sys_IOS_PerfFrame

Once per client frame. Samples are averaged over a window: a number that changes
every frame cannot be read, and the worst frame in the window is the one that
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
		double gpu   = perfSwapCount ? perfSwapTotal / perfSwapCount : 0.0;
		// The swap as a share of the frame: 3ms out of 4 and the frame is the
		// GPU's, 3ms out of 16 and it is not. The ratio is the part that reads
		// at a glance; the milliseconds are there to size it.
		double gpuPct = avg > 0.0 ? 100.0 * gpu / avg : 0.0;
		double rss   = atomic_load( &perfRss );
		double vm    = atomic_load( &perfVm );
		double foot  = atomic_load( &perfFootprint );
		int    ents  = ( clc.state == CA_ACTIVE ) ? cl.snap.numEntities : 0;
		int    surfs = 0, tris = 0, shaders = 0;
		// None of the sampling below costs anything unless someone is looking.
		// The strip is off by default, and a sampler that runs regardless is a
		// tax every player pays for a number nobody reads.
		qboolean showing = ( r_perfHud && r_perfHud->integer ) ||
						   ( r_perfLog && r_perfLog->integer );

		if ( showing ) {
			double cpuNow = IOSPerf_CPUSeconds();

			if ( now > perfCpuWallLast ) {
				perfCpuPercent = 100.0 * ( cpuNow - perfCpuLast ) / ( now - perfCpuWallLast );
			}
			perfCpuLast = cpuNow;
			perfCpuWallLast = now;

			// Re-read rather than kept from startup: the system parks cores
			// under thermal pressure and on low power mode, and a percentage
			// out of eight cores while the process is being held to four is a
			// percentage out of the wrong number.
			perfCores = (int)[NSProcessInfo processInfo].activeProcessorCount;

			if ( perfCores < 1 ) {
				perfCores = 1;
			}

			// Asks for the next window's numbers; this window reads the last ones.
			IOSPerf_SampleMemory();
			R_GetPerfCounters( &surfs, &tris, &shaders );
		}

		if ( r_perfHud && r_perfHud->integer ) {
			UIView *parent = perfLabel.superview;
			CGFloat top = parent ? parent.safeAreaInsets.top : 0.0;
			CGFloat available = parent ? parent.bounds.size.width - 16.0f : 0.0f;
			CGFloat width;
			char rssText[16], vmText[16];

			IOSPerf_FormatBytes( rss, rssText, sizeof( rssText ) );
			IOSPerf_FormatBytes( vm, vmText, sizeof( vmText ) );

			// Every field is named and every percentage says what it is out of.
			// The previous line read "cpu 142%  512 MB", which raised the two
			// questions this one answers: per core or per machine, and which
			// megabytes.
			perfLabel.text = [NSString stringWithFormat:
				@"%3.0f FPS %5.1f/%5.1f ms %3.0f Hz  CPU %3.0f%%/%d%%  GPU %4.1f ms %3.0f%%  RSS %7s  VM %7s  %4d surf %5dk tri %3d ent",
				fps, avg, worst, perfRefreshHz,
				perfCpuPercent, perfCores * 100,
				gpu, gpuPct, rssText, vmText,
				surfs, tris / 1000, ents];

			// Sized to the line rather than to the 640pt it used to be fixed
			// at: the fields no longer fit that, and a fixed width either clips
			// the text or leaves a bar of empty background beside it.
			// A finite width to measure against, not CGFLOAT_MAX: the label
			// is set to shrink its font to fit, and the fitting pass divides
			// by the width it is given.
			width = ceilf( (float)[perfLabel sizeThatFits:
				CGSizeMake( 4096.0f, 22.0f )].width ) + 16.0f;

			if ( available > 0.0f && width > available ) {
				width = available;
			}

			// Under the safe area rather than at the very edge: on this iPad the
			// top inset is where the rounded corners eat into the screen.
			perfLabel.frame = CGRectMake(
				( parent.bounds.size.width - width ) * 0.5f,
				top + 4.0f, width, 22.0f );
		}

		IOSPerf_WriteRow( fps, avg, worst, gpu, gpuPct, perfCpuPercent,
			perfCores, rss, vm, foot, ents, surfs, tris, shaders );

		perfWindowStart = now;
		perfFrames = 0;
		perfFrameTotal = 0.0;
		perfFrameWorst = 0.0;
		perfSwapTotal = 0.0;
		perfSwapCount = 0;
	}
}
