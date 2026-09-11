/*
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
*/
// ios_engine.h -- reaches the engine headers of whichever tree is being built.
//
// The platform layer in this directory is shared by both applications, but SP/
// and MP/ are separate copies of the engine with their own headers. They are
// alike enough that the same sources compile against either, and different
// enough that including one from the other silently mismatches structures.
//
// So every file here includes this, and nothing here names a tree directly.
// IORTCW_MP_BUILD comes from ios/CMakeLists.txt.
//
// The relative paths look fragile but are checked at compile time: build the MP
// target with the define missing and the link fails on the first engine symbol
// rather than producing something subtly wrong.

#ifndef IOS_ENGINE_H
#define IOS_ENGINE_H

#ifdef IORTCW_MP_BUILD

#include "../../MP/code/qcommon/q_shared.h"
#include "../../MP/code/qcommon/qcommon.h"
#include "../../MP/code/sys/sys_local.h"

#else

#include "../../SP/code/qcommon/q_shared.h"
#include "../../SP/code/qcommon/qcommon.h"
#include "../../SP/code/sys/sys_local.h"

#endif

#endif // IOS_ENGINE_H
