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
// vm_static.c -- registry of natively linked game modules.
//
// Platforms such as iOS forbid dlopen()ing code that is not part of the signed
// application bundle, and arm64 has no QVM compiler, so the choices there are
// the bytecode interpreter or linking the game modules straight in. This file
// provides the latter.
//
// Each module is built into its own static library with -fvisibility=hidden
// and with its two exported entry points renamed (-DvmMain=<mod>_vmMain
// -DdllEntry=<mod>_dllEntry), then collapsed with `ld -r` so everything except
// those two symbols becomes local. That is what keeps the three copies of
// q_math.c, bg_*.c and ui_shared.c from colliding at link time.

#include "vm_local.h"

#ifdef USE_STATIC_VM

#define VM_STATIC_MODULE_DECL( mod ) \
	extern void QDECL mod##_dllEntry( intptr_t (QDECL *syscallptr)( intptr_t arg, ... ) ); \
	extern intptr_t mod##_vmMain( intptr_t command, intptr_t arg0, intptr_t arg1, \
		intptr_t arg2, intptr_t arg3, intptr_t arg4, intptr_t arg5, intptr_t arg6, \
		intptr_t arg7, intptr_t arg8, intptr_t arg9, intptr_t arg10, intptr_t arg11 )

VM_STATIC_MODULE_DECL( qagame );
#ifndef DEDICATED
VM_STATIC_MODULE_DECL( cgame );
VM_STATIC_MODULE_DECL( ui );
#endif

static const vmStaticModule_t vm_staticModules[] = {
	{ "qagame", qagame_dllEntry, qagame_vmMain },
#ifndef DEDICATED
	{ "cgame",  cgame_dllEntry,  cgame_vmMain  },
	{ "ui",     ui_dllEntry,     ui_vmMain     },
#endif
};

/*
==============
VM_FindStaticModule

Returns the statically linked module of that name, or NULL to let VM_Create
fall through to its normal dll/QVM search. Setting vm_static to 0 forces the
latter, which is how a build with static modules can still be A/B tested
against the interpreter.
==============
*/
const vmStaticModule_t *VM_FindStaticModule( const char *name ) {
	int i;

	if ( !Cvar_VariableIntegerValue( "vm_static" ) ) {
		return NULL;
	}

	for ( i = 0; i < ARRAY_LEN( vm_staticModules ); i++ ) {
		if ( !Q_stricmp( vm_staticModules[i].name, name ) ) {
			return &vm_staticModules[i];
		}
	}

	return NULL;
}

#endif // USE_STATIC_VM
