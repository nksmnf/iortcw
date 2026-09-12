/*
===========================================================================

Return to Castle Wolfenstein single player GPL Source Code
Copyright (C) 1999-2010 id Software LLC, a ZeniMax Media company. 

This file is part of the Return to Castle Wolfenstein single player GPL Source Code (RTCW SP Source Code).  

RTCW SP Source Code is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

RTCW SP Source Code is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with RTCW SP Source Code.  If not, see <http://www.gnu.org/licenses/>.

In addition, the RTCW SP Source Code is also subject to certain additional terms. You should have received a copy of these additional terms immediately following the terms and conditions of the GNU General Public License which accompanied the RTCW SP Source Code.  If not, please request a copy in writing from id Software at the address below.

If you have questions concerning this license or the applicable additional terms, you may contact in writing id Software LLC, c/o ZeniMax Media Inc., Suite 120, Rockville, Maryland 20850 USA.

===========================================================================
*/

#include "tr_local.h"


/*

  for a projection shadow:

  point[x] += light vector * ( z - shadow plane )
  point[y] +=
  point[z] = shadow plane

  1 0 light[x] / light[z]

*/

typedef struct {
	int i2;
	int facing;
} edgeDef_t;

#define MAX_EDGE_DEFS   32

static edgeDef_t edgeDefs[SHADER_MAX_VERTEXES][MAX_EDGE_DEFS];
static int numEdgeDefs[SHADER_MAX_VERTEXES];
static int facing[SHADER_MAX_INDEXES / 3];
#ifdef USE_OPENGLES
// The ES path draws the whole volume in one indexed call straight out of
// tess.xyz, holding the extruded copy of vertex i at i + tess.numVertexes, so
// there is no separate array of projected positions for it to read.
static unsigned short indexes[6*MAX_EDGE_DEFS*SHADER_MAX_VERTEXES];
static int idx = 0;
#else
static vec3_t shadowXyz[SHADER_MAX_VERTEXES];
#endif

void R_AddEdgeDef( int i1, int i2, int facing ) {
	int c;

	c = numEdgeDefs[ i1 ];
	if ( c == MAX_EDGE_DEFS ) {
		return;     // overflow
	}
	edgeDefs[ i1 ][ c ].i2 = i2;
	edgeDefs[ i1 ][ c ].facing = facing;

	numEdgeDefs[ i1 ]++;
}

void R_RenderShadowEdges( void ) {
	int i;

#if 0
	int numTris;

	// dumb way -- render every triangle's edges
	numTris = tess.numIndexes / 3;

	for ( i = 0 ; i < numTris ; i++ ) {
		int i1, i2, i3;

		if ( !facing[i] ) {
			continue;
		}

		i1 = tess.indexes[ i * 3 + 0 ];
		i2 = tess.indexes[ i * 3 + 1 ];
		i3 = tess.indexes[ i * 3 + 2 ];

		qglBegin( GL_TRIANGLE_STRIP );
		qglVertex3fv( tess.xyz[ i1 ] );
		qglVertex3fv( shadowXyz[ i1 ] );
		qglVertex3fv( tess.xyz[ i2 ] );
		qglVertex3fv( shadowXyz[ i2 ] );
		qglVertex3fv( tess.xyz[ i3 ] );
		qglVertex3fv( shadowXyz[ i3 ] );
		qglVertex3fv( tess.xyz[ i1 ] );
		qglVertex3fv( shadowXyz[ i1 ] );
		qglEnd();
	}
#else
	int c, c2;
	int j, k;
	int i2;
	int c_edges, c_rejected;
	int hit[2];
#ifdef USE_OPENGLES
	idx = 0;
#endif

	// an edge is NOT a silhouette edge if its face doesn't face the light,
	// or if it has a reverse paired edge that also faces the light.
	// A well behaved polyhedron would have exactly two faces for each edge,
	// but lots of models have dangling edges or overfanned edges
	c_edges = 0;
	c_rejected = 0;

	for ( i = 0 ; i < tess.numVertexes ; i++ ) {
		c = numEdgeDefs[ i ];
		for ( j = 0 ; j < c ; j++ ) {
			if ( !edgeDefs[ i ][ j ].facing ) {
				continue;
			}

			hit[0] = 0;
			hit[1] = 0;

			i2 = edgeDefs[ i ][ j ].i2;
			c2 = numEdgeDefs[ i2 ];
			for ( k = 0 ; k < c2 ; k++ ) {
				if ( edgeDefs[ i2 ][ k ].i2 == i ) {
					hit[ edgeDefs[ i2 ][ k ].facing ]++;
				}
			}

			// if it doesn't share the edge with another front facing
			// triangle, it is a sil edge
			if ( hit[ 1 ] == 0 ) {
#ifdef USE_OPENGLES
				// A single drawing call is better than many. So I prefer a singe TRIANGLES call than many TRAINGLE_STRIP call
				// even if it seems less efficiant, it's faster on the PANDORA
				indexes[idx++] = i;
				indexes[idx++] = i + tess.numVertexes;
				indexes[idx++] = i2;
				indexes[idx++] = i2;
				indexes[idx++] = i + tess.numVertexes;
				indexes[idx++] = i2 + tess.numVertexes;
#else
				qglBegin( GL_TRIANGLE_STRIP );
				qglVertex3fv( tess.xyz[ i ] );
				qglVertex3fv( shadowXyz[ i ] );
				qglVertex3fv( tess.xyz[ i2 ] );
				qglVertex3fv( shadowXyz[ i2 ] );
				qglEnd();
#endif
				c_edges++;
			} else {
				c_rejected++;
			}
		}
	}

#ifdef USE_OPENGLES
	qglDrawElements(GL_TRIANGLES, idx, GL_UNSIGNED_SHORT, indexes);
#endif

#endif
}

// The stock extrusion: the ceiling, and what an entity with no known floor
// still gets.
#define SHADOW_EXTRUDE_MAX      512.0f

// How far past the shadow plane the far cap is put down. The floor has to be
// inside the volume, not level with its edge.
#define SHADOW_EXTRUDE_SLACK    16.0f

/*
=================
RB_ShadowExtrudeLength

How far the silhouette is pushed away from the light.

The stock figure is a flat 512 units, and that is what puts a character's
shadow in the next room. Nothing in this renderer occludes a shadow volume:
only entities cast and the world does not, so a prism 512 units long carries
straight on through the wall or the doorway and darkens whatever floor it meets
on the far side. The volume is doing exactly what it was told. It was told too
much.

The floor the caster is standing on is the only surface its shadow is meant to
land on, and cgame already knows where that floor is -- CG_PlayerShadow traces
straight down for it every frame and hands the answer over as e.shadowPlane,
for every value of cg_shadows and not only for the projection kind. So the
volume is cut to the length that just reaches past it. Every floor polygon
under the silhouette is still enclosed, and there is nothing left over to reach
the room next door.

It shortens the other stencil artefact by the same stroke. This is a z-pass
volume, which paints the whole screen when the camera ends up inside it, and a
volume three times shorter is one the player has to stand three times closer to
get inside.

Only for entities that have a plane. cgame leaves e.shadowPlane at zero when
the downward trace found no ground, and for models that are not characters it
is never set at all; those keep the length they have always had.
=================
*/
static float RB_ShadowExtrudeLength( const vec3_t lightDir ) {
	vec3_t  ground;
	float   groundDist, d, maxHeight, reach;
	int     i;

	if ( backEnd.currentEntity->e.shadowPlane == 0.0f ) {
		return SHADOW_EXTRUDE_MAX;
	}

	// World up, expressed in the model space that both tess.xyz and lightDir
	// are in -- the same vector RB_ProjectionShadowDeform builds, for the same
	// reason.
	ground[0] = backEnd.or.axis[0][2];
	ground[1] = backEnd.or.axis[1][2];
	ground[2] = backEnd.or.axis[2][2];

	// How much of the light is coming from above. One at or below the horizon
	// never reaches the floor at all, and dividing by it would ask for a volume
	// of any length whatsoever.
	d = DotProduct( lightDir, ground );
	if ( d < 0.1f ) {
		return SHADOW_EXTRUDE_MAX;
	}

	groundDist = backEnd.or.origin[2] - backEnd.currentEntity->e.shadowPlane;

	// The highest vertex sets the length: the volume has to clear the plane
	// starting from the top of the head, not from the origin.
	maxHeight = 0.0f;
	for ( i = 0 ; i < tess.numVertexes ; i++ ) {
		float h = DotProduct( tess.xyz[i], ground ) + groundDist;

		if ( h > maxHeight ) {
			maxHeight = h;
		}
	}

	if ( maxHeight <= 0.0f ) {
		return SHADOW_EXTRUDE_MAX;      // wholly below its own floor
	}

	reach = ( maxHeight + SHADOW_EXTRUDE_SLACK ) / d;

	return reach < SHADOW_EXTRUDE_MAX ? reach : SHADOW_EXTRUDE_MAX;
}

/*
=================
RB_ShadowTessEnd

triangleFromEdge[ v1 ][ v2 ]


  set triangle from edge( v1, v2, tri )
  if ( facing[ triangleFromEdge[ v1 ][ v2 ] ] && !facing[ triangleFromEdge[ v2 ][ v1 ] ) {
  }
=================
*/
void RB_ShadowTessEnd( void ) {
	int i;
	int numTris;
	vec3_t lightDir;
	float extrude;
	GLboolean rgba[4];

	if ( glConfig.stencilBits < 4 ) {
		return;
	}

#ifdef USE_OPENGLES
	// The extruded vertices are appended to tess.xyz, so the surface has to
	// have room for a second copy of itself -- and has to stay clear of the
	// last slot, which RB_EndSurface reads as its overflow sentinel.
	if ( tess.numVertexes * 2 >= SHADER_MAX_VERTEXES ) {
		return;
	}
#endif

	VectorCopy( backEnd.currentEntity->lightDir, lightDir );

	// Not a constant any more; see RB_ShadowExtrudeLength.
	extrude = RB_ShadowExtrudeLength( lightDir );

	// project vertexes away from light direction
	for ( i = 0 ; i < tess.numVertexes ; i++ ) {
#ifdef USE_OPENGLES
		// Where R_RenderShadowEdges' indexes expect to find it. Projecting
		// into a side array instead left the far cap of every volume reading
		// whatever the previous surface had put in those slots, which turned
		// the stencil pass into garbage and painted the darkening quad over
		// large slabs of the screen.
		VectorMA( tess.xyz[i], -extrude, lightDir, tess.xyz[i + tess.numVertexes] );
#else
		VectorMA( tess.xyz[i], -extrude, lightDir, shadowXyz[i] );
#endif
	}

	// decide which triangles face the light
	memset( numEdgeDefs, 0, 4 * tess.numVertexes );

	numTris = tess.numIndexes / 3;
	for ( i = 0 ; i < numTris ; i++ ) {
		int i1, i2, i3;
		vec3_t d1, d2, normal;
		float   *v1, *v2, *v3;
		float d;

		i1 = tess.indexes[ i * 3 + 0 ];
		i2 = tess.indexes[ i * 3 + 1 ];
		i3 = tess.indexes[ i * 3 + 2 ];

		v1 = tess.xyz[ i1 ];
		v2 = tess.xyz[ i2 ];
		v3 = tess.xyz[ i3 ];

		VectorSubtract( v2, v1, d1 );
		VectorSubtract( v3, v1, d2 );
		CrossProduct( d1, d2, normal );

		d = DotProduct( normal, lightDir );
		if ( d > 0 ) {
			facing[ i ] = 1;
		} else {
			facing[ i ] = 0;
		}

		// create the edges
		R_AddEdgeDef( i1, i2, facing[ i ] );
		R_AddEdgeDef( i2, i3, facing[ i ] );
		R_AddEdgeDef( i3, i1, facing[ i ] );
	}

	// draw the silhouette edges

	GL_Bind( tr.whiteImage );
	GL_State( GLS_SRCBLEND_ONE | GLS_DSTBLEND_ZERO );
	qglColor3f( 0.2f, 0.2f, 0.2f );

	// don't write to the color buffer
	qglGetBooleanv(GL_COLOR_WRITEMASK, rgba);
	qglColorMask( GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE );

	qglEnable( GL_STENCIL_TEST );
	qglStencilFunc( GL_ALWAYS, 1, 255 );

#ifdef USE_OPENGLES
	qglVertexPointer (3, GL_FLOAT, 16, tess.xyz);
	GLboolean text = qglIsEnabled(GL_TEXTURE_COORD_ARRAY);
	GLboolean glcol = qglIsEnabled(GL_COLOR_ARRAY);
	if (text)
		qglDisableClientState( GL_TEXTURE_COORD_ARRAY );
	if (glcol)
		qglDisableClientState( GL_COLOR_ARRAY );
#endif

	GL_Cull( CT_BACK_SIDED );
	qglStencilOp( GL_KEEP, GL_KEEP, GL_INCR );

	R_RenderShadowEdges();

	GL_Cull( CT_FRONT_SIDED );
	qglStencilOp( GL_KEEP, GL_KEEP, GL_DECR );

#ifdef USE_OPENGLES
	qglDrawElements(GL_TRIANGLES, idx, GL_UNSIGNED_SHORT, indexes);
#else
	R_RenderShadowEdges();
#endif

#ifdef USE_OPENGLES
	if (text)
		qglEnableClientState( GL_TEXTURE_COORD_ARRAY );
	if (glcol)
		qglEnableClientState( GL_COLOR_ARRAY );
#endif
	// reenable writing to the color buffer
	qglColorMask(rgba[0], rgba[1], rgba[2], rgba[3]);
}


/*
=================
RB_ShadowFinish

Darken everything that is is a shadow volume.
We have to delay this until everything has been shadowed,
because otherwise shadows from different body parts would
overlap and double darken.
=================
*/
void RB_ShadowFinish( void ) {
	if ( r_shadows->integer != 2 ) {
		return;
	}
	if ( glConfig.stencilBits < 4 ) {
		return;
	}
	qglEnable( GL_STENCIL_TEST );
	qglStencilFunc( GL_NOTEQUAL, 0, 255 );

	qglDisable( GL_CLIP_PLANE0 );
	GL_Cull( CT_TWO_SIDED );

	GL_Bind( tr.whiteImage );

	qglLoadIdentity();

	qglColor3f( 0.6f, 0.6f, 0.6f );
	GL_State( GLS_DEPTHMASK_TRUE | GLS_SRCBLEND_DST_COLOR | GLS_DSTBLEND_ZERO );

//	qglColor3f( 1, 0, 0 );
//	GL_State( GLS_DEPTHMASK_TRUE | GLS_SRCBLEND_ONE | GLS_DSTBLEND_ZERO );

#ifdef USE_OPENGLES
	GLboolean text = qglIsEnabled(GL_TEXTURE_COORD_ARRAY);
	GLboolean glcol = qglIsEnabled(GL_COLOR_ARRAY);
	if (text)
		qglDisableClientState( GL_TEXTURE_COORD_ARRAY );
	if (glcol)
		qglDisableClientState( GL_COLOR_ARRAY );
	GLfloat vtx[] = {
	 -100,  100, -10,
	  100,  100, -10,
	  100, -100, -10,
	 -100, -100, -10
	};
	qglVertexPointer  ( 3, GL_FLOAT, 0, vtx );
	qglDrawArrays( GL_TRIANGLE_FAN, 0, 4 );
	if (text)
		qglEnableClientState( GL_TEXTURE_COORD_ARRAY );
	if (glcol)
		qglEnableClientState( GL_COLOR_ARRAY );
#else
	qglBegin( GL_QUADS );
	qglVertex3f( -100, 100, -10 );
	qglVertex3f( 100, 100, -10 );
	qglVertex3f( 100, -100, -10 );
	qglVertex3f( -100, -100, -10 );
	qglEnd();
#endif

	qglColor4f( 1,1,1,1 );
	qglDisable( GL_STENCIL_TEST );
}


/*
=================
RB_ProjectionShadowDeform

=================
*/
void RB_ProjectionShadowDeform( void ) {
	float   *xyz;
	int i;
	float h;
	vec3_t ground;
	vec3_t light;
	float groundDist;
	float d;
	vec3_t lightDir;

	xyz = ( float * ) tess.xyz;

	ground[0] = backEnd.or.axis[0][2];
	ground[1] = backEnd.or.axis[1][2];
	ground[2] = backEnd.or.axis[2][2];

	groundDist = backEnd.or.origin[2] - backEnd.currentEntity->e.shadowPlane;

	VectorCopy( backEnd.currentEntity->lightDir, lightDir );
	d = DotProduct( lightDir, ground );
	// don't let the shadows get too long or go negative
	if ( d < 0.5 ) {
		VectorMA( lightDir, ( 0.5 - d ), ground, lightDir );
		d = DotProduct( lightDir, ground );
	}
	d = 1.0 / d;

	light[0] = lightDir[0] * d;
	light[1] = lightDir[1] * d;
	light[2] = lightDir[2] * d;

	for ( i = 0; i < tess.numVertexes; i++, xyz += 4 ) {
		h = DotProduct( xyz, ground ) + groundDist;

		xyz[0] -= light[0] * h;
		xyz[1] -= light[1] * h;
		xyz[2] -= light[2] * h;
	}
}
