#version 150
#ifdef GL_ES
#if __VERSION__ == 300
#define varying in
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
precision highp sampler2D;
precision highp sampler3D;
#else
precision mediump float;
precision mediump sampler2D;
precision mediump sampler3D;
#endif
#define texelFetchBuffer texelFetch
#define texture1D texture
#define texture2D texture
#define texture3D texture
#endif // 300
#else  // GL_ES
#define highp
#define mediump
#define lowp
#if __VERSION__ == 150
#define varying in
#define texelFetchBuffer texelFetch
#define texture1D texture
#define texture2D texture
#define texture3D texture
#endif
#if __VERSION__ == 120
#extension GL_EXT_gpu_shader4 : require
#endif
#endif // GL_ES

/*=========================================================================

  Program:   Visualization Toolkit
  Module:    raycasterfs.glsl

  Copyright (c) Ken Martin, Will Schroeder, Bill Lorensen
  All rights reserved.
  See Copyright.txt or http://www.kitware.com/Copyright.htm for details.

     This software is distributed WITHOUT ANY WARRANTY; without even
     the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.  See the above copyright notice for more information.

=========================================================================*/

//////////////////////////////////////////////////////////////////////////////
///
/// Inputs
///
//////////////////////////////////////////////////////////////////////////////

/// 3D texture coordinates form vertex shader
varying vec3 ip_textureCoords;
varying vec3 ip_vertexPos;

//////////////////////////////////////////////////////////////////////////////
///
/// Outputs
///
//////////////////////////////////////////////////////////////////////////////

vec4 g_fragColor = vec4(0.0);

//////////////////////////////////////////////////////////////////////////////
///
/// Uniforms, attributes, and globals
///
//////////////////////////////////////////////////////////////////////////////
vec3 g_dataPos;
vec3 g_dirStep;
vec4 g_srcColor;
vec4 g_eyePosObj;
bool g_exit;
bool g_skip;
float g_currentT;
float g_terminatePointMax;

out vec4 fragOutput0;

uniform sampler3D in_volume[1];
uniform vec4 in_volume_scale[1];
uniform vec4 in_volume_bias[1];
uniform int in_noOfComponents;
uniform int in_independentComponents;

uniform sampler2D in_noiseSampler;
#ifndef GL_ES
uniform sampler2D in_depthSampler;
#endif

// Camera position
uniform vec3 in_cameraPos;
uniform mat4 in_volumeMatrix[1];
uniform mat4 in_inverseVolumeMatrix[1];
uniform mat4 in_textureDatasetMatrix[1];
uniform mat4 in_inverseTextureDatasetMatrix[1];
uniform mat4 in_textureToEye[1];
uniform vec3 in_texMin[1];
uniform vec3 in_texMax[1];
uniform mat4 in_cellToPoint[1];
// view and model matrices
uniform mat4 in_projectionMatrix;
uniform mat4 in_inverseProjectionMatrix;
uniform mat4 in_modelViewMatrix;
uniform mat4 in_inverseModelViewMatrix;
varying mat4 ip_inverseTextureDataAdjusted;

// Ray step size
uniform vec3 in_cellStep[1];
uniform vec2 in_scalarsRange[4];
uniform vec3 in_cellSpacing[1];

// Sample distance
uniform float in_sampleDistance;

// Scales
uniform vec2 in_windowLowerLeftCorner;
uniform vec2 in_inverseOriginalWindowSize;
uniform vec2 in_inverseWindowSize;
uniform vec3 in_textureExtentsMax;
uniform vec3 in_textureExtentsMin;

// Material and lighting
uniform vec3 in_diffuse[4];
uniform vec3 in_ambient[4];
uniform vec3 in_specular[4];
uniform float in_shininess[4];

// Others
uniform bool in_useJittering;
vec3 g_rayJitter = vec3(0.0);

uniform vec2 in_averageIPRange;
uniform bool in_twoSidedLighting;
uniform vec3 in_lightAmbientColor[1];
uniform vec3 in_lightDiffuseColor[1];
uniform vec3 in_lightSpecularColor[1];
vec4 g_lightPosObj;
vec3 g_ldir;
vec3 g_vdir;
vec3 g_h;

/// We support only 8 clipping planes for now
/// The first value is the size of the data array for clipping
/// planes (origin, normal)
uniform float in_clippingPlanes[49];
uniform float in_scale;
uniform float in_bias;

const float g_opacityThreshold = 1.0 - 1.0 / 255.0;

int clippingPlanesSize;
vec3 objRayDir;
mat4 textureToObjMat;

//VTK::GradientCache::Dec

//VTK::Transfer2D::Dec

uniform sampler2D in_opacityTransferFunc_0[1];

float computeOpacity(vec4 scalar)
{
  return texture2D(in_opacityTransferFunc_0[0], vec2(scalar.w, 0)).r;
}

// c is short for component
vec4 computeGradient(in vec3 texPos,
                     in int c,
                     in sampler3D volume,
                     in int index)
{
  // Approximate Nabla(F) derivatives with central differences.
  vec3 g1; // F_front
  vec3 g2; // F_back
  vec3 xvec = vec3(in_cellStep[index].x, 0.0, 0.0);
  vec3 yvec = vec3(0.0, in_cellStep[index].y, 0.0);
  vec3 zvec = vec3(0.0, 0.0, in_cellStep[index].z);
  vec3 g1t = texPos + in_cellStep[index].xyz;
  vec3 g2t = texPos - in_cellStep[index].xyz;
  g1.x = texture3D(volume, vec3(texPos + xvec))[c];
  g1.y = texture3D(volume, vec3(texPos + yvec))[c];
  g1.z = texture3D(volume, vec3(texPos + zvec))[c];
  g2.x = texture3D(volume, vec3(texPos - xvec))[c];
  g2.y = texture3D(volume, vec3(texPos - yvec))[c];
  g2.z = texture3D(volume, vec3(texPos - zvec))[c];

  for (int i = 0; i < clippingPlanesSize && !g_skip; i = i + 6)
  {
    vec4 g1ObjDataPos = textureToObjMat * vec4(g1t, 1.0);
    vec4 g2ObjDataPos = textureToObjMat * vec4(g2t, 1.0);
    if (g1ObjDataPos.w != 0.0)
    {
      g1ObjDataPos /= g1ObjDataPos.w;
    }
    if (g2ObjDataPos.w != 0.0)
    {
      g2ObjDataPos /= g2ObjDataPos.w;
    }
    vec3 planeOrigin = vec3(in_clippingPlanes[i + 1],
                            in_clippingPlanes[i + 2],
                            in_clippingPlanes[i + 3]);
    vec3 planeNormal = vec3(in_clippingPlanes[i + 4],
                            in_clippingPlanes[i + 5],
                            in_clippingPlanes[i + 6]);
    if (dot(vec3(g1ObjDataPos.xyz - planeOrigin), planeNormal) < 0)
    {
      g1 = vec3(1000.0);
    }
    if (dot(vec3(g2ObjDataPos.xyz - planeOrigin), planeNormal) < 0)
    {
      g2 = vec3(-1000.0);
    }
  }

  // Apply scale and bias to the fetched values.
  g1 = g1 * in_volume_scale[index][c] + in_volume_bias[index][c];
  g2 = g2 * in_volume_scale[index][c] + in_volume_bias[index][c];

  // Central differences: (F_front - F_back) / 2h
  // This version of computeGradient() is only used for lighting
  // calculations (only direction matters), hence the difference is
  // not scaled by 2h and a dummy gradient mag is returned (-1.).
  return vec4((g1 - g2) / in_cellSpacing[index], -1.0);
}

uniform sampler2D[1];

vec4 computeLighting(vec4 color, int component)
{
  vec4 finalColor = vec4(0.0); // Compute gradient function only once
  vec4 gradient = computeGradient(g_dataPos, component, in_volume[0], 0);

  vec3 diffuse = vec3(0.0);
  vec3 specular = vec3(0.0);
  vec3 normal = gradient.xyz;
  float normalLength = length(normal);
  if (normalLength > 0.0)
  {
    normal = normalize(normal);
  }
  else
  {
    normal = vec3(0.0, 0.0, 0.0);
  }
  float nDotL = dot(normal, g_ldir);
  float nDotH = dot(normal, g_h);
  if (nDotL < 0.0 && in_twoSidedLighting)
  {
    nDotL = -nDotL;
  }
  if (nDotH < 0.0 && in_twoSidedLighting)
  {
    nDotH = -nDotH;
  }
  if (nDotL > 0.0)
  {
    diffuse =
      nDotL * in_diffuse[component] * in_lightDiffuseColor[0] * color.rgb;
  }
  specular = pow(nDotH, in_shininess[component]) * in_specular[component] *
    in_lightSpecularColor[0];
  // For the headlight, ignore the light's ambient color
  // for now as it is causing the old mapper tests to fail
  finalColor.xyz = in_ambient[component] * color.rgb + diffuse + specular;
  finalColor.a = color.a;
  return finalColor;
}

uniform sampler2D in_colorTransferFunc_0[1];

vec4 computeColor(vec4 scalar, float opacity)
{
  return computeLighting(
    vec4(texture2D(in_colorTransferFunc_0[0], vec2(scalar.w, 0.0)).xyz,
         opacity),
    0);
}

vec3 computeRayDirection()
{
  return normalize(ip_vertexPos.xyz - g_eyePosObj.xyz);
}

//VTK::Picking::Dec

//VTK::RenderToImage::Dec

//VTK::DepthPeeling::Dec

//////////////////////////////////////////////////////////////////////////////
///
/// Helper functions
///
//////////////////////////////////////////////////////////////////////////////

/**
 * Transform window coordinate to NDC.
 */
vec4 WindowToNDC(const float xCoord, const float yCoord, const float zCoord)
{
  vec4 NDCCoord = vec4(0.0, 0.0, 0.0, 1.0);

  NDCCoord.x =
    (xCoord - in_windowLowerLeftCorner.x) * 2.0 * in_inverseWindowSize.x - 1.0;
  NDCCoord.y =
    (yCoord - in_windowLowerLeftCorner.y) * 2.0 * in_inverseWindowSize.y - 1.0;
  NDCCoord.z = (2.0 * zCoord - (gl_DepthRange.near + gl_DepthRange.far)) /
    gl_DepthRange.diff;

  return NDCCoord;
}

/**
 * Transform NDC coordinate to window coordinates.
 */
vec4 NDCToWindow(const float xNDC, const float yNDC, const float zNDC)
{
  vec4 WinCoord = vec4(0.0, 0.0, 0.0, 1.0);

  WinCoord.x =
    (xNDC + 1.f) / (2.f * in_inverseWindowSize.x) + in_windowLowerLeftCorner.x;
  WinCoord.y =
    (yNDC + 1.f) / (2.f * in_inverseWindowSize.y) + in_windowLowerLeftCorner.y;
  WinCoord.z =
    (zNDC * gl_DepthRange.diff + (gl_DepthRange.near + gl_DepthRange.far)) /
    2.f;

  return WinCoord;
}

//////////////////////////////////////////////////////////////////////////////
///
/// Ray-casting
///
//////////////////////////////////////////////////////////////////////////////

/**
 * Global initialization. This method should only be called once per shader
 * invocation regardless of whether castRay() is called several times (e.g.
 * vtkDualDepthPeelingPass). Any castRay() specific initialization should be
 * placed within that function.
 */
void initializeRayCast()
{
  /// Initialize g_fragColor (output) to 0
  g_fragColor = vec4(0.0);
  g_dirStep = vec3(0.0);
  g_srcColor = vec4(0.0);
  g_exit = false;

  // Get the 3D texture coordinates for lookup into the in_volume dataset
  g_dataPos = ip_textureCoords.xyz;

  // Eye position in dataset space
  g_eyePosObj = in_inverseVolumeMatrix[0] * vec4(in_cameraPos, 1.0);

  // Getting the ray marching direction (in dataset space);
  vec3 rayDir = computeRayDirection();

  // Multiply the raymarching direction with the step size to get the
  // sub-step size we need to take at each raymarching step
  g_dirStep =
    (ip_inverseTextureDataAdjusted * vec4(rayDir, 0.0)).xyz * in_sampleDistance;

  // 2D Texture fragment coordinates [0,1] from fragment coordinates.
  // The frame buffer texture has the size of the plain buffer but
  // we use a fraction of it. The texture coordinate is less than 1 if
  // the reduction factor is less than 1.
  // Device coordinates are between -1 and 1. We need texture
  // coordinates between 0 and 1. The in_noiseSampler and in_depthSampler
  // buffers have the original size buffer.
  vec2 fragTexCoord =
    (gl_FragCoord.xy - in_windowLowerLeftCorner) * in_inverseWindowSize;

  if (in_useJittering)
  {
    float jitterValue = texture2D(in_noiseSampler, fragTexCoord).x;
    g_rayJitter = g_dirStep * jitterValue;
    g_dataPos += g_rayJitter;
  }
  else
  {
    g_dataPos += g_dirStep;
  }

  // Flag to deternmine if voxel should be considered for the rendering
  g_skip = false;
  // Light position in dataset space
  g_lightPosObj = (in_inverseVolumeMatrix[0] * vec4(in_cameraPos, 1.0));
  g_ldir = normalize(g_lightPosObj.xyz - ip_vertexPos);
  g_vdir = normalize(g_eyePosObj.xyz - ip_vertexPos);
  g_h = normalize(g_ldir + g_vdir);

  // Flag to indicate if the raymarch loop should terminate
  bool stop = false;

  g_terminatePointMax = 0.0;

#ifdef GL_ES
  vec4 l_depthValue = vec4(1.0, 1.0, 1.0, 1.0);
#else
  vec4 l_depthValue = texture2D(in_depthSampler, fragTexCoord);
#endif
  // Depth test
  if (gl_FragCoord.z >= l_depthValue.x)
  {
    discard;
  }

  // color buffer or max scalar buffer have a reduced size.
  fragTexCoord =
    (gl_FragCoord.xy - in_windowLowerLeftCorner) * in_inverseOriginalWindowSize;

  // Compute max number of iterations it will take before we hit
  // the termination point

  // Abscissa of the point on the depth buffer along the ray.
  // point in texture coordinates
  vec4 terminatePoint =
    WindowToNDC(gl_FragCoord.x, gl_FragCoord.y, l_depthValue.x);

  // From normalized device coordinates to eye coordinates.
  // in_projectionMatrix is inversed because of way VT
  // From eye coordinates to texture coordinates
  terminatePoint = ip_inverseTextureDataAdjusted * in_inverseVolumeMatrix[0] *
    in_inverseModelViewMatrix * in_inverseProjectionMatrix * terminatePoint;
  terminatePoint /= terminatePoint.w;

  g_terminatePointMax =
    length(terminatePoint.xyz - g_dataPos.xyz) / length(g_dirStep);
  g_currentT = 0.0;

  vec4 tempClip = in_volumeMatrix[0] * vec4(rayDir, 0.0);
  if (tempClip.w != 0.0)
  {
    tempClip = tempClip / tempClip.w;
    tempClip.w = 1.0;
  }
  objRayDir = tempClip.xyz;
  clippingPlanesSize = int(in_clippingPlanes[0]);
  vec4 objDataPos = vec4(0.0);
  textureToObjMat = in_volumeMatrix[0] * in_textureDatasetMatrix[0];

  vec4 terminatePointObj = textureToObjMat * terminatePoint;
  if (terminatePointObj.w != 0.0)
  {
    terminatePointObj = terminatePointObj / terminatePointObj.w;
    terminatePointObj.w = 1.0;
  }

  for (int i = 0; i < clippingPlanesSize; i = i + 6)
  {
    if (in_useJittering)
    {
      objDataPos = textureToObjMat * vec4(g_dataPos - g_rayJitter, 1.0);
    }
    else
    {
      objDataPos = textureToObjMat * vec4(g_dataPos - g_dirStep, 1.0);
    }
    if (objDataPos.w != 0.0)
    {
      objDataPos = objDataPos / objDataPos.w;
      objDataPos.w = 1.0;
    }
    vec3 planeOrigin = vec3(in_clippingPlanes[i + 1],
                            in_clippingPlanes[i + 2],
                            in_clippingPlanes[i + 3]);
    vec3 planeNormal = vec3(in_clippingPlanes[i + 4],
                            in_clippingPlanes[i + 5],
                            in_clippingPlanes[i + 6]);
    vec3 normalizedPlaneNormal = normalize(planeNormal);

    float rayDotNormal = dot(objRayDir, normalizedPlaneNormal);
    bool frontFace = rayDotNormal > 0;
    float distance = dot(normalizedPlaneNormal, planeOrigin - objDataPos.xyz);

    if (frontFace &&    // Observing from the clipped side (plane's front face)
        distance > 0.0) // Ray-entry lies on the clipped side.
    {
      // Scale the point-plane distance to the ray direction and update the
      // entry point.
      float rayScaledDist = distance / rayDotNormal;
      vec4 newObjDataPos =
        vec4(objDataPos.xyz + rayScaledDist * objRayDir, 1.0);
      newObjDataPos = in_inverseTextureDatasetMatrix[0] *
        in_inverseVolumeMatrix[0] * vec4(newObjDataPos.xyz, 1.0);
      if (newObjDataPos.w != 0.0)
      {
        newObjDataPos /= newObjDataPos.w;
      }
      if (in_useJittering)
      {
        g_dataPos = newObjDataPos.xyz + g_rayJitter;
      }
      else
      {
        g_dataPos = newObjDataPos.xyz + g_dirStep;
      }

      bool stop = any(greaterThan(g_dataPos, in_texMax[0])) ||
        any(lessThan(g_dataPos, in_texMin[0]));
      if (stop)
      {
        // The ray exits the bounding box before ever intersecting the plane
        // (only the clipped space is hit).
        discard;
      }

      bool behindGeometry = dot(terminatePointObj.xyz - planeOrigin.xyz,
                                normalizedPlaneNormal) < 0.0;
      if (behindGeometry)
      {
        // Geometry appears in front of the plane.
        discard;
      }

      // Update the number of ray marching steps to account for the clipped
      // entry point ( this is necessary in case the ray hits geometry after
      // marching behind the plane, given that the number of steps was assumed
      // to be from the not-clipped entry).
      g_terminatePointMax =
        length(terminatePoint.xyz - g_dataPos.xyz) / length(g_dirStep);
    }
  }

  //VTK::RenderToImage::Init

  //VTK::DepthPass::Init
}

/**
 * March along the ray direction sampling the volume texture.  This function
 * takes a start and end point as arguments but it is up to the specific render
 * pass implementation to use these values (e.g. vtkDualDepthPeelingPass). The
 * mapper does not use these values by default, instead it uses the number of
 * steps defined by g_terminatePointMax.
 */
vec4 castRay(const float zStart, const float zEnd)
{
  //VTK::DepthPeeling::Ray::Init

  //VTK::DepthPeeling::Ray::PathCheck

  /// For all samples along the ray
  while (!g_exit)
  {

    g_skip = false;

    for (int i = 0; i < clippingPlanesSize && !g_skip; i = i + 6)
    {
      vec4 objDataPos = textureToObjMat * vec4(g_dataPos, 1.0);
      if (objDataPos.w != 0.0)
      {
        objDataPos /= objDataPos.w;
      }
      vec3 planeOrigin = vec3(in_clippingPlanes[i + 1],
                              in_clippingPlanes[i + 2],
                              in_clippingPlanes[i + 3]);
      vec3 planeNormal = vec3(in_clippingPlanes[i + 4],
                              in_clippingPlanes[i + 5],
                              in_clippingPlanes[i + 6]);
      if (dot(vec3(objDataPos.xyz - planeOrigin), planeNormal) < 0 &&
          dot(objRayDir, planeNormal) < 0)
      {
        g_skip = true;
        g_exit = true;
      }
    }

    //VTK::PreComputeGradients::Impl

    if (!g_skip)
    {
      vec4 scalar = texture3D(in_volume[0], g_dataPos);
      scalar.r = scalar.r * in_volume_scale[0].r + in_volume_bias[0].r;
      scalar = vec4(scalar.r);
      g_srcColor = vec4(0.0);
      g_srcColor.a = computeOpacity(scalar);
      if (g_srcColor.a > 0.0)
      {
        g_srcColor = computeColor(scalar, g_srcColor.a);
        // Opacity calculation using compositing:
        // Here we use front to back compositing scheme whereby
        // the current sample value is multiplied to the
        // currently accumulated alpha and then this product
        // is subtracted from the sample value to get the
        // alpha from the previous steps. Next, this alpha is
        // multiplied with the current sample colour
        // and accumulated to the composited colour. The alpha
        // value from the previous steps is then accumulated
        // to the composited colour alpha.
        g_srcColor.rgb *= g_srcColor.a;
        g_fragColor = (1.0f - g_fragColor.a) * g_srcColor + g_fragColor;
      }
    }

    //VTK::RenderToImage::Impl

    //VTK::DepthPass::Impl

    /// Advance ray
    g_dataPos += g_dirStep;

    if (any(greaterThan(g_dataPos, in_texMax[0])) ||
        any(lessThan(g_dataPos, in_texMin[0])))
    {
      break;
    }

    // Early ray termination
    // if the currently composited colour alpha is already fully saturated
    // we terminated the loop or if we have hit an obstacle in the
    // direction of they ray (using depth buffer) we terminate as well.
    if ((g_fragColor.a > g_opacityThreshold) ||
        g_currentT >= g_terminatePointMax)
    {
      break;
    }
    ++g_currentT;
  }

  return g_fragColor;
}

/**
 * Finalize specific modes and set output data.
 */
void finalizeRayCast()
{

  //VTK::Picking::Exit

  g_fragColor.r = g_fragColor.r * in_scale + in_bias * g_fragColor.a;
  g_fragColor.g = g_fragColor.g * in_scale + in_bias * g_fragColor.a;
  g_fragColor.b = g_fragColor.b * in_scale + in_bias * g_fragColor.a;
  fragOutput0 = g_fragColor;

  //VTK::RenderToImage::Exit

  //VTK::DepthPass::Exit
}

//////////////////////////////////////////////////////////////////////////////
///
/// Main
///
//////////////////////////////////////////////////////////////////////////////
void main()
{

  initializeRayCast();
  castRay(-1.0, -1.0);
  finalizeRayCast();
}
