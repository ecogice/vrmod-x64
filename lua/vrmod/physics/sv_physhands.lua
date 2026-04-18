if CLIENT then return end
local vrHands = {}
local function Log(msg, ...)
    vrmod.logger.Debug("[VRHand] " .. msg, ...)
end

-- ==================== YOUR ORIGINAL WEAPON LOGIC ====================
local function GetCachedWeaponParams(wep, ply, side)
    local radius, reach, mins, maxs, angles = vrmod.utils.GetWeaponMeleeParams(wep, ply, side)
    if radius == vrmod.DEFAULT_RADIUS and reach == vrmod.DEFAULT_REACH then return nil end
    return radius, reach, mins, maxs, angles
end

local function ApplySphere(hand, handData, radius)
    if not IsValid(hand) then return end
    Log("ApplySphere radius=%.2f", radius)
    hand:PhysicsInitSphere(radius, "metal")
    hand:SetSolid(SOLID_VPHYSICS)
    hand:SetCollisionBounds(Vector(-radius, -radius, -radius), Vector(radius, radius, radius))
    hand:Activate()
    local phys = hand:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(70)
        handData.phys = phys
        Log("ApplySphere SUCCESS")
    end
end

local function ApplyBox(hand, handData, mins, maxs, angles)
    if not IsValid(hand) then return end
    Log("ApplyBox mins=%s maxs=%s", tostring(mins), tostring(maxs))
    if angles then hand:SetAngles(angles) end
    hand:PhysicsInitBox(mins, maxs)
    hand:SetSolid(SOLID_VPHYSICS)
    hand:Activate()
    local phys = hand:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(70)
        handData.phys = phys
        Log("ApplyBox SUCCESS")
    end
end

local function UpdateWeaponCollisionShape(ply, wep)
    if not IsValid(ply) or not vrmod.IsPlayerInVR(ply) then return end
    Log("UpdateWeaponCollisionShape called for %s → %s", ply:Nick(), IsValid(wep) and wep:GetClass() or "nil")
    timer.Simple(0.1, function()
        if not IsValid(ply) or not vrmod.IsPlayerInVR(ply) then return end
        local hands = vrHands[ply]
        if not hands or not hands.right or not IsValid(hands.right.ent) then return end
        local right = hands.right
        local hand = right.ent
        if not vrmod.utils.IsValidWep(wep) then
            timer.Simple(0, function() ApplySphere(hand, right, vrmod.DEFAULT_RADIUS) end)
            return
        end

        local radius, reach, mins, maxs, angles = GetCachedWeaponParams(wep, ply, "right")
        if not radius or not mins or not maxs or not angles or radius == vrmod.DEFAULT_RADIUS then
            timer.Simple(0.5, function() UpdateWeaponCollisionShape(ply, wep) end)
            return
        end

        timer.Simple(0, function() ApplyBox(hand, right, mins, maxs, angles) end)
    end)
end

-- ==================== SPAWN ====================
local function SpawnVRHands(ply)
    if not IsValid(ply) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) then return end
    if not vrHands[ply] then vrHands[ply] = {} end
    local hands = vrHands[ply]
    Log("SpawnVRHands started for %s", ply:Nick())
    for _, side in ipairs({"right", "left"}) do
        timer.Simple(0, function()
            if hands[side] and IsValid(hands[side].ent) then return end
            local hand = ents.Create("prop_physics")
            if not IsValid(hand) then return end
            hand:SetModel("models/hunter/plates/plate.mdl")
            hand:SetPos(ply:GetPos())
            hand:Spawn()
            hand:SetNoDraw(true)
            hand:DrawShadow(false)
            hand:SetNWBool("isVRHand", true)
            hand:SetCollisionGroup(COLLISION_GROUP_WEAPON)
            local radius = 2.8
            hand:PhysicsInitSphere(radius, "metal")
            hand:SetCollisionBounds(Vector(-radius, -radius, -radius), Vector(radius, radius, radius))
            hand:Activate()
            local phys = hand:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetMass(70)
                hands[side] = {
                    ent = hand,
                    phys = phys
                }

                -- Realistic velocity push on actual collision
                hand:AddCallback("PhysicsCollide", function(ent, data)
                    local hit = data.HitEntity
                    if not IsValid(hit) or hit:GetClass() ~= "prop_physics" then return end
                    -- Safe real relative velocity
                    local speed = 80
                    if side == "right" then
                        local vel = vrmod.GetRightHandVelocityRelative and vrmod.GetRightHandVelocityRelative(ply)
                        if vel then speed = vel:Length() end
                    else
                        local vel = vrmod.GetLeftHandVelocityRelative and vrmod.GetLeftHandVelocityRelative(ply)
                        if vel then speed = vel:Length() end
                    end

                    if speed > 35 then
                        local physHit = hit:GetPhysicsObject()
                        if IsValid(physHit) then
                            local pushDir = data.HitNormal * -1
                            physHit:ApplyForceCenter(pushDir * speed * 14.0)
                            Log("PHYSICS PUSH %s → prop | Speed: %.1f", side, speed)
                        end
                    end
                end)

                Log("%s hand created", side)
            else
                hand:Remove()
            end
        end)
    end

    timer.Simple(0.2, function()
        if hands.right and IsValid(hands.right.ent) then
            local wep = ply:GetActiveWeapon()
            if vrmod.utils.IsValidWep(wep) then UpdateWeaponCollisionShape(ply, wep) end
        end
    end)
end

local function RemoveVRHands(ply)
    if not IsValid(ply) then return end
    local hands = vrHands[ply]
    if not hands then return end
    for _, data in pairs(hands) do
        if IsValid(data.ent) then data.ent:Remove() end
    end
end

-- ==================== SHADOW CONTROL IN THINK ====================
hook.Add("Think", "VRHand_PhysicsSync", function()
    for _, ply in ipairs(player.GetHumans()) do
        if not vrmod.IsPlayerInVR(ply) then continue end
        local hands = vrHands[ply]
        if not hands or not hands.right or not hands.left then
            if not ply:InVehicle() then
                RemoveVRHands(ply)
                timer.Simple(1, function() SpawnVRHands(ply) end)
            end

            continue
        end

        if ply:InVehicle() then
            RemoveVRHands(ply)
            continue
        end

        local function UpdateHand(side)
            local handData = hands[side]
            if not handData or not IsValid(handData.ent) or not IsValid(handData.phys) then return end
            local pos = side == "right" and vrmod.GetRightHandPos(ply) or vrmod.GetLeftHandPos(ply)
            local ang = side == "right" and vrmod.GetRightHandAng(ply) or vrmod.GetLeftHandAng(ply)
            local targetPos = pos + ang:Forward() * (vrmod.DEFAULT_OFFSET or 0)
            local phys = handData.phys
            phys:Wake()
            phys:ComputeShadowControl({
                secondstoarrive = engine.TickInterval() * 3.5,
                pos = targetPos,
                angle = ang,
                maxangular = 750,
                maxangulardamp = 750,
                maxspeed = 14500,
                maxspeeddamp = 1700,
                dampfactor = 0.83,
                teleportdistance = 250,
                deltatime = 0,
            })
        end

        UpdateHand("right")
        UpdateHand("left")
    end
end)

-- ==================== HOOKS ====================
hook.Add("PlayerSwitchWeapon", "VRHand_UpdateCollisionOnWeaponSwitch", function(ply, oldWep, newWep) UpdateWeaponCollisionShape(ply, newWep) end)
hook.Add("VRMod_Pickup", "VRHand_BlockPickup", function(ply, ent)
    local hands = vrHands[ply]
    if hands and (ent == hands.right.ent or ent == hands.left.ent) then return false end
end)

hook.Add("VRMod_Start", "VRHand_VRStart", SpawnVRHands)
hook.Add("PlayerSpawn", "VRHand_PlayerSpawn", function(ply) if vrmod.IsPlayerInVR(ply) then timer.Simple(0.1, function() SpawnVRHands(ply) end) end end)
hook.Add("PlayerDeath", "VRHand_PlayerDeath", RemoveVRHands)
hook.Add("VRMod_Exit", "VRHand_VREnd", RemoveVRHands)
hook.Add("PlayerDisconnected", "VRHand_Disconnect", function(ply)
    if vrHands[ply] then
        for _, side in pairs(vrHands[ply]) do
            if IsValid(side.ent) then side.ent:Remove() end
        end

        vrHands[ply] = nil
    end
end)

hook.Add("PreCleanupMap", "VRHand_PreCleanup", function()
    for ply in pairs(vrHands) do
        RemoveVRHands(ply)
    end
end)

hook.Add("PostCleanupMap", "VRHand_PostCleanup", function()
    for _, ply in ipairs(player.GetHumans()) do
        if IsValid(ply) and vrmod.IsPlayerInVR(ply) then SpawnVRHands(ply) end
    end
end)

hook.Add("Think", "VRHand_ThinkRespawn", function()
    for ply, hands in pairs(vrHands) do
        if not IsValid(ply) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) then continue end
        local repair = false
        for _, side in ipairs({"right", "left"}) do
            if not hands[side] or not IsValid(hands[side].ent) then
                repair = true
                break
            end
        end

        if repair then SpawnVRHands(ply) end
    end
end)

-- AVR mag hooks
hook.Add("VRMod_Pickup", "VRHand_AVRMagPickup", function(ply, ent)
    if not IsValid(ent) or not string.match(ent:GetClass(), "avrmag_") then return end
    local hands = vrHands[ply]
    if hands and hands.left and IsValid(hands.left.ent) then hands.left.ent:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE) end
end)

hook.Add("VRMod_Drop", "VRHand_AVRMagDrop", function(ply, ent)
    if not IsValid(ent) or not string.match(ent:GetClass(), "avrmag_") then return end
    local hands = vrHands[ply]
    if hands and hands.left and IsValid(hands.left.ent) then hands.left.ent:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR) end
end)