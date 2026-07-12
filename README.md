GMod vrmod projection/stretching fix test. Please keep in mind I just coded this with gpt 5.6 and barely understand it but I made the fix just a toggle in the settings incase some of the fixes break something else (to my knowledge i dont believe it does). sorry about the broken diffs in commits

```
1. Preserve the complete headset projection
(cl_rendering.lua) 
- Horizontal projection scale
- Vertical projection scale
- Horizontal center offset
- Vertical center offset
- VRMod view scale
The upstream version retained only enough information to produce a symmetric FOV and aspect ratio. It discarded the data required to reconstruct the asymmetric frustum.

2. Reconstruct the exact asymmetric frustum
(cl_rendering.lua)
- Converts the headset projection matrix into left, right, top, and bottom tangent planes.
- Builds a symmetric Source-compatible FOV large enough to contain all four planes.
- Calculates an in-bounds offcenter rectangle selecting the exact headset frustum.
- Corrects the horizontal sign difference between moving a sampled UV window and moving the projection center.
This is the core rendering fix. It is necessary to prevent:
- Horizontal and vertical scale changes during head rotation
- Mirrored/swapped-looking asymmetric eye projections
- Missing outer scene content
- Reliance on out-of-range texture sampling
Checked that the generated rectangles remain inside the viewport and reconstruct the original tangent planes exactly.

3. Apply the projection separately to each eye
(cl_vrmod.lua)
- Original symmetric rendering when the fix is disabled
- Exact left/right asymmetric rendering when enabled
Each eye gets its own:
- Enclosing horizontal FOV
- Aspect ratio
- Off-center rectangle
Per-eye handling is necessary because the two projection matrices are mirrored and may have slightly different calibration.

4. Stop shifting compositor UVs
(cl_rendering.lua)
- Left eye from the left half
- Right eye from the right half
- Platform-correct vertical orientation
- Existing small seam inset preserved
This is necessary. Once asymmetry is applied during scene rendering, retaining the old UV offset would apply the correction twice and could again leave [0,1].

5. Keep the change opt-in
(sh_startup.lua and cl_settings.lua)
```

Please keep in mind I didnt write any of this I just wanted it fixed
