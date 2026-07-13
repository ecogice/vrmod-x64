if SERVER then return end
local halos = {}
local haloCount = 0
local haloFrame = 0
local haloRT, haloMat
local haloAdd_orig
timer.Simple(0, function() haloAdd_orig = halo.Add end)
hook.Add("VRMod_Start", "halos", function(ply)
	if ply ~= LocalPlayer() then return end
	halo.Add = function(ents, color, blurX, blurY, passes, additive, ignoreZ)
		if FrameNumber() ~= haloFrame then
			if FrameNumber() > haloFrame + 1 then
				--LocalPlayer():ChatPrint("installed halo hook")
				hook.Add("PostDrawTranslucentRenderables", "vrmod_halos", function(depth, sky)
					if not haloRT then
						haloRT = GetRenderTarget("3dhalos" .. tostring(math.floor(SysTime())), g_VR.view.w, g_VR.view.h, false)
						haloMat = CreateMaterial("3dhalos" .. tostring(math.floor(SysTime())), "UnlitGeneric", {
							["$basetexture"] = haloRT:GetName()
						})
					end

					if depth or sky or EyePos() ~= g_VR.view.origin then return end
					if FrameNumber() > haloFrame + 1 then
						haloCount = 0
						hook.Remove("PostDrawTranslucentRenderables", "vrmod_halos")
						--LocalPlayer():ChatPrint("removed halo hook")
					end

					--
					render.PushRenderTarget(haloRT)
					render.Clear(0, 0, 0, 255, true, true)
					-- A pushed render target does not inherit a reliable 3D camera. Recreate
					-- the active eye exactly so the mask and world use the same projection.
					cam.Start({
						type = "3D",
						origin = g_VR.view.origin,
						angles = g_VR.view.angles,
						x = 0,
						y = 0,
						w = g_VR.view.w,
						h = g_VR.view.h,
						fov = g_VR.view.fov,
						aspect = g_VR.view.aspectratio,
						offcenter = g_VR.view.offcenter,
					})
					render.SetStencilEnable(true)
					render.SetStencilWriteMask(0xFF)
					render.SetStencilTestMask(0xFF)
					render.SetStencilPassOperation(STENCIL_REPLACE)
					render.SetStencilFailOperation(STENCIL_KEEP)
					render.SetStencilZFailOperation(STENCIL_KEEP)
					render.SetStencilReferenceValue(1)
					for i = 1, haloCount do
						for k, v in pairs(halos[i].ents) do
							if IsValid(v) then
								render.ClearStencil()
								render.SetStencilPassOperation(STENCIL_REPLACE)
								render.SetStencilCompareFunction(STENCIL_ALWAYS)
								v:DrawModel()
								render.SetStencilPassOperation(STENCIL_KEEP)
								render.SetStencilCompareFunction(STENCIL_EQUAL)
								local col = halos[i].color
								render.ClearBuffersObeyStencil(col.r, col.g, col.b, 255, false)
							end
						end
					end

					cam.End3D()
					render.SetStencilEnable(false)
					render.BlurRenderTarget(haloRT, 2, 2, 1)
					render.SetStencilEnable(true)
					render.ClearBuffersObeyStencil(0, 0, 0, 255, false)
					render.SetStencilEnable(false)
					render.PopRenderTarget()
					-- DrawScreenQuad targets the screen abstraction and can escape a per-eye
					-- viewport. Draw an explicit pixel rectangle into the shared VR target.
					render.PushRenderTarget(g_VR.rt)
					cam.Start2D()
					local oldClipping = DisableClipping(true)
					surface.SetDrawColor(255, 255, 255, 255)
					surface.SetMaterial(haloMat)
					render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_ADD, 0, 0, 0)
					render.OverrideDepthEnable(true, false)
					surface.DrawTexturedRect(g_VR.view.x, g_VR.view.y, g_VR.view.w, g_VR.view.h)
					surface.DrawTexturedRect(g_VR.view.x, g_VR.view.y, g_VR.view.w, g_VR.view.h)
					render.OverrideDepthEnable(false)
					render.OverrideBlend(false)
					DisableClipping(oldClipping)
					cam.End2D()
					render.PopRenderTarget()
					--
				end)
			end

			haloFrame = FrameNumber()
			haloCount = 0
		end

		haloEnts = ents
		halos[haloCount + 1] = {
			ents = ents,
			color = color
		}

		haloCount = haloCount + 1
	end
end)

hook.Add("VRMod_Exit", "halos", function(ply)
	if ply ~= LocalPlayer() then return end
	halo.Add = haloAdd_orig
	hook.Remove("PostDrawTranslucentRenderables", "vrmod_halos")
	haloCount = 0
	haloRT = nil
end)
