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
  g1.x = texture3D(volume, vec3(texPos + xvec))[c];
  g1.y = texture3D(volume, vec3(texPos + yvec))[c];
  g1.z = texture3D(volume, vec3(texPos + zvec))[c];
  g2.x = texture3D(volume, vec3(texPos - xvec))[c];
  g2.y = texture3D(volume, vec3(texPos - yvec))[c];
  g2.z = texture3D(volume, vec3(texPos - zvec))[c];

  // The following block is the code of interest that checks if the neighboring
  // voxels are within the clipping range.
  vec3 g1t = texPos + in_cellStep[index].xyz;
  vec3 g2t = texPos - in_cellStep[index].xyz;
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
      // Clipping required. Set the gradient to a high value
      g1 = vec3(1000.0);
    }
    if (dot(vec3(g2ObjDataPos.xyz - planeOrigin), planeNormal) < 0)
    {
      // Clipping required. Set the gradient to a high value
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
