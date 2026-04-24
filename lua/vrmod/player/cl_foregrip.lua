if SERVER then return end
-- ===================== CONFIG =====================
local GRIP_DISTANCE = 17 -- Units to start grip (hand proximity)
local GUIDE_BLEND = 0.18 -- 0 = pure right-hand (visual only), 0.15-0.25 = slight natural guiding
-- ==================================================
-- State (clean table, no polluting globals)
local state = {
    gripping = false,
    offsetPos = Vector(),
    offsetAng = Angle(),
    lastWep = nil,
    weaponBox = nil, -- {mins, maxs, reach, isMelee} from vrmod.utils
}

-- ===================== HELPERS =====================
local function IsValidForegripWeapon(wep)
    if not IsValid(wep) then return false end
    local class = wep:GetClass():lower()
    return not (string.find(class, "weapon_fists") or string.find(class, "arcticvr_") or class == "weapon_vrmod_empty" or class == "weapon_physgun")
end

-- Official viewmodel position updater (from vrmod.utils)
-- Updated for two-hand grip compatibility (forces update + uses guided pose)
local function UpdateViewModelPos(pos, ang, override)
    local ply = LocalPlayer()
    if vrmod.suppressViewModelUpdates and not override then
        if vrmod.utils and vrmod.utils.UpdateViewModel then vrmod.utils.UpdateViewModel() end
        return
    end

    pos, ang = vrmod.utils and vrmod.utils.CheckWeaponPushout and vrmod.utils.CheckWeaponPushout(pos, ang) or pos, ang
    if not IsValid(ply) or not g_VR.active then return end
    if not ply:Alive() then return end
    local currentvmi = g_VR.currentvmi
    if currentvmi then
        local modelPos = pos
        local collisionShape = vrmod._collisionShapeByHand and vrmod._collisionShapeByHand.right
        if collisionShape and collisionShape.isClipped and collisionShape.pushOutPos then
            modelPos = collisionShape.pushOutPos
            if vrmod.logger then vrmod.logger.Debug("[Foregrip] Applying collision-corrected pos for viewmodel: %s", tostring(modelPos)) end
        end

        local offsetPos, offsetAng = LocalToWorld(currentvmi.offsetPos or Vector(), currentvmi.offsetAng or Angle(), modelPos, ang)
        g_VR.viewModelPos = offsetPos
        g_VR.viewModelAng = offsetAng
        if vrmod.utils and vrmod.utils.UpdateViewModel then vrmod.utils.UpdateViewModel() end
    end
end

-- Core two-handed pose calculation with slight guiding
-- Uses REAL weapon collision box from vrmod.utils (no magic numbers)
local function GetGuidedWeaponPose(rightPos, rightAng, leftPos, leftAng, box)
    if GUIDE_BLEND <= 0 then return rightPos, rightAng end
    local toLeft = leftPos - rightPos
    local dist = toLeft:Length()
    -- Dynamic limits from actual weapon collision box (fallback to sensible defaults)
    local maxDist = box and box.reach and box.reach * 1.35 or 26
    if dist > maxDist then return rightPos, rightAng end
    -- Minimum sensible distance (based on weapon width, prevents weird close-hand blending)
    local minDist = box and box.mins and math.max(math.abs(box.mins.y), 4.5) or 5.5
    if dist < minDist then return rightPos, rightAng end
    local targetAng = toLeft:GetNormalized():Angle()
    -- Blend right-hand orientation with left-hand direction (foregrip pull)
    local newAng = LerpAngle(GUIDE_BLEND, rightAng, targetAng)
    -- Keep right-hand roll for natural weapon twist/feel
    newAng.r = rightAng.r
    return rightPos, newAng
end

-- ===================== HOOKS =====================
hook.Add("VRMod_Input", "vrmod_foregrip", function(action, pressed)
    if not g_VR.active or not g_VR.tracking.pose_lefthand or not g_VR.tracking.pose_righthand then return end
    if action ~= "boolean_left_pickup" then return end
    local left = g_VR.tracking.pose_lefthand
    local right = g_VR.tracking.pose_righthand
    local wep = LocalPlayer():GetActiveWeapon()
    if pressed and left.pos:Distance(right.pos) <= GRIP_DISTANCE and IsValidForegripWeapon(wep) and g_VR.currentvmi then
        state.gripping = true
        state.lastWep = wep
        -- === USE ACTUAL WEAPON COLLISION BOX FROM vrmod.utils (no guessing) ===
        state.weaponBox = nil
        if vrmod.utils and IsValid(wep) then
            local model = wep:GetModel() or ""
            vrmod.utils.ComputePhysicsParams(model) -- trigger real AABB if not cached
            local radius, reach, actualMins, actualMaxs, _, isMelee = vrmod.utils.GetCachedWeaponParams(wep, LocalPlayer(), "right") or {}
            if actualMins and actualMaxs then
                state.weaponBox = {
                    mins = actualMins,
                    maxs = actualMaxs,
                    reach = reach or 20,
                    isMelee = isMelee or false
                }

                if vrmod.logger then vrmod.logger.Debug("Foregrip: Actual collision box for %s | Mins: %s, Maxs: %s | Melee: %s | Reach: %.1f", wep:GetClass(), tostring(actualMins), tostring(actualMaxs), tostring(isMelee), reach or 0) end
            end
        end

        -- Weapon world position at moment of grip (right hand + viewmodel offset)
        local wepWorldPos, wepWorldAng = LocalToWorld(g_VR.currentvmi.offsetPos or Vector(), g_VR.currentvmi.offsetAng or Angle(), right.pos, right.ang)
        -- Store left hand's relative position/angle to weapon
        state.offsetPos, state.offsetAng = WorldToLocal(left.pos, left.ang, wepWorldPos, wepWorldAng)
    else
        state.gripping = false
    end
end)

hook.Add("VRMod_PreRender", "vrmod_foregrip_x64", function()
    if not state.gripping or not g_VR.currentvmi then
        state.gripping = false
        return
    end

    local left = g_VR.tracking.pose_lefthand
    local right = g_VR.tracking.pose_righthand
    if not left or not right then
        state.gripping = false
        return
    end

    -- Safety: release if hands drift too far (uses real weapon reach from collision box)
    local maxDist = state.weaponBox and state.weaponBox.reach and state.weaponBox.reach * 1.35 or 26
    if left.pos:Distance(right.pos) > maxDist then
        state.gripping = false
        return
    end

    -- Calculate weapon pose with slight left-hand guiding influence (box-aware)
    local guidedPos, guidedAng = GetGuidedWeaponPose(right.pos, right.ang, left.pos, left.ang, state.weaponBox)
    -- Use the (local + utils) viewmodel updater for proper collision handling
    UpdateViewModelPos(guidedPos, guidedAng, true) -- override=true forces update during two-hand grip
    -- Where the left hand should visually attach (relative to the (possibly collision-corrected) viewmodel pose)
    local attachPos, attachAng = LocalToWorld(state.offsetPos, state.offsetAng, g_VR.viewModelPos, g_VR.viewModelAng)
    vrmod.SetLeftHandPose(attachPos, attachAng)
    -- Network sync (for other players to see your left hand on the gun)
    local netData = g_VR.net and g_VR.net[LocalPlayer():SteamID()]
    if netData and netData.lerpedFrame then
        netData.lerpedFrame.lefthandPos = attachPos
        netData.lerpedFrame.lefthandAng = attachAng
    end
end)

hook.Add("VRMod_Exit", "vrmod_foregrip", function() state.gripping = false end)
hook.Add("PlayerSwitchWeapon", "vrmod_foregrip", function(ply) if ply == LocalPlayer() then state.gripping = false end end)