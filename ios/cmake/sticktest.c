/* Checks the stick maths against the symptoms reported on device:
 *   - pushing forward also turned  (radial vs per-axis deadzone)
 *   - movement snapped to full speed (scaling into ClampChar)
 *   - look up did nothing            (pitch sign)
 *   - both sticks felt identical     (axis assignment)
 *
 * Mirrors IN_ApplyStickCurve and IN_GamepadSticks, then runs the values through
 * what CL_JoystickMove does with them.
 */
#include <stdio.h>
#include <math.h>

/* engine defaults */
static const float j_side = 0.25f, j_forward = -0.25f;
static const float j_yaw = -0.022f, j_pitch = 0.022f;

static float nonzero(float v, float fb) { float a = fabsf(v); return a > 0.0001f ? a : fb; }

static void curve(float *x, float *y, float dz, float expo)
{
    float mag = sqrtf((*x) * (*x) + (*y) * (*y)), scaled, curved;
    if (mag < dz) { *x = 0; *y = 0; return; }
    if (mag > 1.0f) mag = 1.0f;
    scaled = (mag - dz) / (1.0f - dz);
    curved = scaled * ((1.0f - expo) + expo * scaled * scaled);
    *x = (*x / mag) * curved;
    *y = (*y / mag) * curved;
}

static int clampchar(int v) { return v < -128 ? -128 : (v > 127 ? 127 : v); }

static void report(const char *what, float lx, float ly, float rx, float ry)
{
    const float dz = 0.15f, expo = 0.6f, moveExpo = 0.15f, yawSpeed = 180.0f, pitchSpeed = 130.0f;
    float axSide, axFwd, axYaw, axPitch;
    int rightmove, forwardmove;
    float degPerSecYaw, degPerSecPitch;

    curve(&lx, &ly, dz, moveExpo);
    curve(&rx, &ry, dz, expo);

    axSide  = lx * (127.0f / nonzero(j_side, 0.25f));
    axFwd   = ly * (127.0f / nonzero(j_forward, 0.25f));
    axYaw   = rx * (yawSpeed / nonzero(j_yaw, 0.022f));
    axPitch = ry * (pitchSpeed / nonzero(j_pitch, 0.022f));

    /* CL_JoystickMove */
    rightmove   = clampchar((int)(j_side * axSide));
    forwardmove = clampchar((int)(j_forward * axFwd));
    /* anglespeed sums to 1.0 over a second, so this is degrees per second */
    degPerSecYaw   = j_yaw * axYaw;
    degPerSecPitch = j_pitch * axPitch;

    printf("%-34s move fwd=%+4d side=%+4d   look yaw=%+7.1f/s pitch=%+7.1f/s\n",
           what, forwardmove, rightmove, degPerSecYaw, degPerSecPitch);
}

int main(void)
{
    puts("forward is +, right is +, yaw + turns left, pitch + looks down\n");

    report("left stick full up",        0.0f, -1.0f, 0, 0);
    report("left stick up, 3% x noise", 0.03f, -1.0f, 0, 0);
    report("left stick full right",     1.0f,  0.0f, 0, 0);
    report("left stick half up",        0.0f, -0.5f, 0, 0);
    report("left stick tiny nudge",     0.05f, -0.05f, 0, 0);
    report("left stick diagonal",       0.707f, -0.707f, 0, 0);
    puts("");
    report("right stick full up",       0, 0, 0.0f, -1.0f);
    report("right stick full down",     0, 0, 0.0f,  1.0f);
    report("right stick full right",    0, 0, 1.0f,  0.0f);
    report("right stick half right",    0, 0, 0.5f,  0.0f);
    return 0;
}
