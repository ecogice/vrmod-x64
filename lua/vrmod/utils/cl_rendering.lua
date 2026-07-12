g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
function vrmod.utils.CalculateProjectionParams(projMatrix, worldScale)
    local xscale = projMatrix[1][1]
    local xoffset = projMatrix[1][3]
    local yscale = projMatrix[2][2]
    local yoffset = projMatrix[2][3]
    -- ** Normalize vertical sign: **
    if not system.IsWindows() then
        -- On Linux/OpenGL: invert the sign so + means “down” just like on Windows
        yoffset = -yoffset
    end

    -- now the rest is identical on both platforms:
    local tan_px = math.abs((1 - xoffset) / xscale)
    local tan_nx = math.abs((-1 - xoffset) / xscale)
    local tan_py = math.abs((1 - yoffset) / yscale)
    local tan_ny = math.abs((-1 - yoffset) / yscale)
    local w = (tan_px + tan_nx) / worldScale
    local h = (tan_py + tan_ny) / worldScale
    return {
        HorizontalFOV = math.deg(2 * math.atan(w / 2)),
        AspectRatio = w / h,
        HorizontalOffset = xoffset,
        VerticalOffset = yoffset,
        XScale = xscale,
        YScale = yscale,
        WorldScale = worldScale,
        Width = w,
        Height = h,
    }
end

function vrmod.utils.ComputeDesktopCrop(desktopView, w, h)
    local vmargin = (1 - ScrH() / ScrW() * w / 2 / h) / 2
    local hoffset = desktopView == 3 and 0.5 or 0
    return vmargin, hoffset
end

function vrmod.utils.ComputeSubmitBounds(leftCalc, rightCalc, hOffset, vOffset, scaleFactor, renderOffset)
    local isWindows = system.IsWindows()
    local hFactor, vFactor = 0, 0
    if renderOffset then
        local wAvg = (leftCalc.Width + rightCalc.Width) * 0.5
        local hAvg = (leftCalc.Height + rightCalc.Height) * 0.5
        hFactor = 0.5 / wAvg
        vFactor = 1.0 / hAvg
    else
        hFactor = 0.25
        vFactor = 0.5
    end

    hFactor = hFactor * scaleFactor
    vFactor = vFactor * scaleFactor
    local TEXTURE_INSET = 0.003
    local vMin, vMax = isWindows and 0 or 1, isWindows and 1 or 0
    local function calcVMinMax(offset)
        local adj = offset * vFactor
        if isWindows then
            return (vMin + TEXTURE_INSET) - adj, (vMax - TEXTURE_INSET) - adj
        else
            return (vMin - TEXTURE_INSET) - adj, (vMax + TEXTURE_INSET) - adj
        end
    end

    -- U: outer only
    local uMinLeft = 0.0 + TEXTURE_INSET + (leftCalc.HorizontalOffset + hOffset) * hFactor
    local uMaxLeft = 0.5 + (leftCalc.HorizontalOffset + hOffset) * hFactor -- inner untouched
    local uMinRight = 0.5 + (rightCalc.HorizontalOffset + hOffset) * hFactor -- inner untouched
    local uMaxRight = 1.0 - TEXTURE_INSET + (rightCalc.HorizontalOffset + hOffset) * hFactor
    -- V: symmetric top/bottom
    local vMinLeft, vMaxLeft = calcVMinMax(leftCalc.VerticalOffset + vOffset)
    local vMinRight, vMaxRight = calcVMinMax(rightCalc.VerticalOffset + vOffset)
    return uMinLeft, vMinLeft, uMaxLeft, vMaxLeft, uMinRight, vMinRight, uMaxRight, vMaxRight
end

-- Build an exact asymmetric projection using RenderView's symmetric FOV plus an
-- in-bounds off-center crop. A symmetric envelope contains all four headset
-- frustum planes, then offcenter selects only the requested eye frustum.
function vrmod.utils.ComputeOffCenterProjection(calc, viewportWidth, viewportHeight, hOffset, vOffset, scaleFactor)
    hOffset = hOffset or 0
    vOffset = vOffset or 0
    scaleFactor = scaleFactor or 1

    local xscale = math.abs(calc.XScale)
    local yscale = math.abs(calc.YScale)
    local worldScale = math.max(math.abs(calc.WorldScale or 1), 0.0001)
    -- Moving the projection center is the inverse of moving the legacy sampled
    -- texture window. OpenVR's horizontal matrix convention therefore needs the
    -- opposite sign when expressed through Source's offcenter crop; without
    -- this, the left and right asymmetric frusta appear exchanged.
    local xoffset = -(calc.HorizontalOffset + hOffset) * scaleFactor
    local yoffset = (calc.VerticalOffset + vOffset) * scaleFactor

    -- Tangents at NDC -1/+1, matching CalculateProjectionParams.
    local tanLeft = (-1 - xoffset) / xscale / worldScale
    local tanRight = (1 - xoffset) / xscale / worldScale
    local tanYMin = (-1 - yoffset) / yscale / worldScale
    local tanYMax = (1 - yoffset) / yscale / worldScale

    local halfX = math.max(math.abs(tanLeft), math.abs(tanRight), 0.0001)
    local halfY = math.max(math.abs(tanYMin), math.abs(tanYMax), 0.0001)
    local left = (tanLeft + halfX) / (2 * halfX) * viewportWidth
    local right = (tanRight + halfX) / (2 * halfX) * viewportWidth
    local top = (halfY - tanYMax) / (2 * halfY) * viewportHeight
    local bottom = (halfY - tanYMin) / (2 * halfY) * viewportHeight

    return {
        HorizontalFOV = math.deg(2 * math.atan(halfX)),
        AspectRatio = halfX / halfY,
        OffCenter = {
            left = left,
            right = right,
            top = top,
            bottom = bottom,
        },
    }
end

-- Normal side-by-side bounds. Projection offsets must not be applied here when
-- ComputeOffCenterProjection is active, otherwise the correction happens twice.
function vrmod.utils.ComputeFixedSubmitBounds()
    local inset = 0.003
    local vMin, vMax
    if system.IsWindows() then
        vMin, vMax = inset, 1.0 - inset
    else
        vMin, vMax = 1.0 - inset, inset
    end

    return inset, vMin, 0.5, vMax, 0.5, vMin, 1.0 - inset, vMax
end

function vrmod.utils.AdjustFOV(proj, fovScaleX, fovScaleY)
    local clone = {}
    for i = 1, 4 do
        clone[i] = {proj[i][1], proj[i][2], proj[i][3], proj[i][4]}
    end

    -- scale the FOV (diagonal terms)
    clone[1][1] = clone[1][1] * fovScaleX
    clone[2][2] = clone[2][2] * fovScaleY
    -- scale the center offset (asymmetry) terms
    clone[1][3] = clone[1][3] * fovScaleX
    clone[2][3] = clone[2][3] * fovScaleY
    return clone
end

function vrmod.utils.DrawDeathAnimation(rtWidth, rtHeight)
    if not g_VR.deathTime then g_VR.deathTime = CurTime() end
    local fadeAlpha = 0
    local fadeDuration = 3.5
    local maxAlpha = 200
    local progress = math.min((CurTime() - g_VR.deathTime) / fadeDuration, 1)
    fadeAlpha = math.min(progress * maxAlpha, maxAlpha)
    cam.Start2D()
    surface.SetDrawColor(120, 0, 0, fadeAlpha)
    surface.DrawRect(0, 0, rtWidth, rtHeight)
    cam.End2D()
end
