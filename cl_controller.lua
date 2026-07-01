-- cl_controller.lua
-- Place this file in your garrysmod/lua/autorun/client/ folder.
if CLIENT then

    -- =======================
    -- STATE & VALUES
    -- =======================

    local aimAssistEnabled = false
    local triggerEnabled   = false -- Added Triggerbot state
    local crosshairEnabled = false
    local espEnabled       = false

    local FIXED_STRENGTH = 11.0
    local FIXED_RANGE    = 0.4
    local FIXED_MAX_DIST = 2500

    local aimOffset     = 21.0
    local aimFalloffEnd = 5000

    local Aimbot = {}
    Aimbot.DeathSequences = {
        ["models/barnacle.mdl"]      = {4,15},
        ["models/antlion_guard.mdl"] = {44},
        ["models/hunter.mdl"]        = {124,125,126,127,128},
    }

    -- =======================
    -- TARGETING
    -- =======================

    local function GetTargetPos(ent, verticalOffset)
        if not IsValid(ent) then return Vector(0,0,0) end
        local pos = ent:LocalToWorld(ent:OBBCenter())
        pos.z = pos.z + verticalOffset
        return pos
    end

    local function CheckTarget(ent)
        if not IsValid(ent) then return false end
        local ply = LocalPlayer()
        if ent:IsPlayer() then
            if ent:Health() < 1 or ent == ply then return false end
            return true
        elseif ent:IsNPC() then
            if ent:GetMoveType() == MOVETYPE_NOCLIP then return false end
            if table.HasValue(Aimbot.DeathSequences[string.lower(ent:GetModel() or "")] or {}, ent:GetSequence()) then
                return false
            end
            return true
        end
        return false
    end

    local function GetClosestTarget()
        local ply = LocalPlayer()
        if not IsValid(ply) then return nil end
        local eyePos = ply:EyePos()
        local ang = ply:EyeAngles():Forward()
        local closestDist = math.huge
        local bestEnt = nil
        for _, ent in ipairs(ents.GetAll()) do
            if not CheckTarget(ent) then continue end
            local targetCenter = GetTargetPos(ent, 0)
            if eyePos:Distance(targetCenter) >= aimFalloffEnd then continue end
            local trace = util.TraceLine({ start = eyePos, endpos = targetCenter, filter = ply })
            if trace.Hit and trace.Entity ~= ent then continue end
            local diff = (targetCenter - eyePos):GetNormalized() - ang
            local dist = diff:Length()
            if dist < closestDist then
                closestDist = dist
                bestEnt = ent
            end
        end
        return bestEnt
    end

    -- =======================
    -- ESP & SKELETON LOGIC
    -- =======================
    local function GetCoordinates(ent)
        local min,max = ent:OBBMins(),ent:OBBMaxs()
        local corners = {
            Vector(min.x,min.y,min.z),
            Vector(min.x,min.y,max.z),
            Vector(min.x,max.y,min.z),
            Vector(min.x,max.y,max.z),
            Vector(max.x,min.y,min.z),
            Vector(max.x,min.y,max.z),
            Vector(max.x,max.y,min.z),
            Vector(max.x,max.y,max.z)
        }

        local minx,miny,maxx,maxy = ScrW()*2,ScrH()*2,0,0
        for _,corner in ipairs(corners) do
            local screen = ent:LocalToWorld(corner):ToScreen()
            minx,miny = math.min(minx,screen.x),math.min(miny,screen.y)
            maxx,maxy = math.max(maxx,screen.x),math.max(maxy,screen.y)
        end
        return minx,miny,maxx,maxy
    end

    local function FixName(ent)
        if ent:IsPlayer() then return ent:Nick() end
        if ent:IsNPC() then return ent:GetClass():sub(5) end
        return ""
    end

    local boneConnections = {
        {"ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Neck1"},
        {"ValveBiped.Bip01_Neck1", "ValveBiped.Bip01_Spine4"},
        {"ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Spine2"},
        {"ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine"},
        {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Pelvis"},
        -- Arms
        {"ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_R_UpperArm"},
        {"ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm"},
        {"ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand"},
        {"ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_L_UpperArm"},
        {"ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm"},
        {"ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Hand"},
        -- Legs
        {"ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_R_Thigh"},
        {"ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_R_Calf"},
        {"ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_R_Foot"},
        {"ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_L_Thigh"},
        {"ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_L_Calf"},
        {"ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_L_Foot"}
    }

    local function DrawSkeleton(ent)
        surface.SetDrawColor(255, 0, 255, 200) -- Red lines
        for _, link in ipairs(boneConnections) do
            local bone1 = ent:LookupBone(link[1])
            local bone2 = ent:LookupBone(link[2])
            
            if bone1 and bone2 then
                local pos1 = ent:GetBonePosition(bone1)
                local pos2 = ent:GetBonePosition(bone2)
                
                if pos1 and pos2 then
                    local screen1 = pos1:ToScreen()
                    local screen2 = pos2:ToScreen()
                    
                    if screen1.visible and screen2.visible then
                        surface.DrawLine(screen1.x, screen1.y, screen2.x, screen2.y)
                    end
                end
            end
        end
    end

    hook.Add("HUDPaint", "ControllerESPDraw", function()
        if not espEnabled then return end
        for _,ent in ipairs(ents.GetAll()) do
            if not IsValid(ent) then continue end
            if (ent:IsPlayer() or ent:IsNPC()) and ent:Health() > 0 then
                if ent == LocalPlayer() and not LocalPlayer():ShouldDrawLocalPlayer() then continue end
                
                local x1,y1,x2,y2 = GetCoordinates(ent)
                local name = FixName(ent)

                -- 1. Draw Yellow Low Opacity Overlay
                surface.SetDrawColor(255, 255, 0, 0)
                surface.DrawRect(x1, y1, x2 - x1, y2 - y1)

                -- 2. Draw Lime Green Corners
                surface.SetDrawColor(50, 255, 50, 255)
                local edge = 8
                surface.DrawLine(x1,y1,math.min(x1+edge,x2),y1)
                surface.DrawLine(x1,y1,x1,math.min(y1+edge,y2))
                surface.DrawLine(x2,y1,math.max(x2-edge,x1),y1)
                surface.DrawLine(x2,y1,x2,math.min(y1+edge,y2))
                surface.DrawLine(x1,y2,math.min(x1+edge,x2),y2)
                surface.DrawLine(x1,y2,x1,math.max(y2-edge,y1))
                surface.DrawLine(x2,y2,math.max(x2-edge,x1),y2)
                surface.DrawLine(x2,y2,x2,math.max(y2-edge,y1))

                -- Draw Lime Green Text
                draw.SimpleText(name,"Trebuchet18", (x1+x2)/2, y1-15, Color(50, 255, 50), TEXT_ALIGN_CENTER)

                -- 3. Draw Red Stick Figure
                DrawSkeleton(ent)
            end
        end
    end)


    -- =======================
    -- CROSSHAIR RING
    -- =======================
    hook.Add("HUDPaint", "ControllerCrosshairRing", function()
        if not crosshairEnabled then return end
        local cx, cy   = ScrW() / 2, ScrH() / 2
        local radius   = 156
        local segments = 64
        surface.SetDrawColor(255, 255, 255, 200)
        for i = 0, segments - 1 do
            local a1 = math.rad((i     / segments) * 360)
            local a2 = math.rad(((i+1) / segments) * 360)
            surface.DrawLine(
                cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
                cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
            )
        end
        surface.DrawRect(cx - 1, cy - 1, 3, 3)
    end)

    -- =======================
    -- AIM ASSIST LOGIC
    -- =======================
    hook.Add("Think", "ControllerAimAssistThink", function()
        if not aimAssistEnabled then return end
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local target = GetClosestTarget()
        if not IsValid(target) then return end
        local targetPos = GetTargetPos(target, aimOffset)
        local worldDist = ply:EyePos():Distance(targetPos)
        local falloff = 1.0
        if worldDist >= aimFalloffEnd then return
        elseif worldDist > FIXED_MAX_DIST then
            falloff = 1.0 - ((worldDist - FIXED_MAX_DIST) / (aimFalloffEnd - FIXED_MAX_DIST))
        end
        local view        = ply:EyeAngles()
        local targetAngle = (targetPos - ply:EyePos()):Angle()
        local diffPitch   = math.AngleDifference(targetAngle.p, view.p)
        local diffYaw     = math.AngleDifference(targetAngle.y, view.y)
        local currentDist = ((targetPos - ply:EyePos()):GetNormalized() - view:Forward()):Length()
        if currentDist > FIXED_RANGE then return end
        local strength   = FIXED_STRENGTH * falloff * FrameTime()
        ply:SetEyeAngles(Angle(
            view.p + math.Clamp(diffPitch, -strength, strength),
            view.y + math.Clamp(diffYaw,   -strength, strength),
            view.r
        ))
    end)

    -- =======================
    -- TRIGGER BOT
    -- =======================
    local lastTriggerTime = 0
    local triggerDelay = 0 -- Forced to 0 per your request

    local function GetEntityUnderCrosshair()
        local ply = LocalPlayer()
        if not IsValid(ply) then return nil end
        local trace = util.TraceLine({
            start = ply:EyePos(),
            endpos = ply:EyePos() + ply:EyeAngles():Forward()*5000,
            filter = ply
        })
        local ent = trace.Entity
        if IsValid(ent) and (ent:IsPlayer() or ent:IsNPC()) then return ent end
        return nil
    end

    hook.Add("Think", "ControllerTriggerBot", function()
        if not triggerEnabled then return end

        local ent = GetEntityUnderCrosshair()

        if not IsValid(ent) then
            lastTriggerTime = CurTime()
            return 
        end

        if CurTime() - lastTriggerTime < triggerDelay then return end

        if not input.IsMouseDown(MOUSE_LEFT) then
            RunConsoleCommand("+attack")
            timer.Simple(0.01, function() RunConsoleCommand("-attack") end)
            lastTriggerTime = CurTime() 
        end
    end)

    -- =======================
    -- FONTS
    -- =======================
    local F_HEADER = "AimAssist_Header"
    local F_LABEL  = "AimAssist_Label"
    local F_SUB    = "AimAssist_Sub"
    local F_VAL    = "AimAssist_Val"
    local F_CLOSE  = "AimAssist_Close"

    surface.CreateFont(F_HEADER, { font = "Roboto", size = 15, weight = 700, antialias = true })
    surface.CreateFont(F_LABEL,  { font = "Roboto", size = 14, weight = 600, antialias = true })
    surface.CreateFont(F_SUB,    { font = "Roboto", size = 11, weight = 400, antialias = true })
    surface.CreateFont(F_VAL,    { font = "Roboto", size = 13, weight = 700, antialias = true })
    surface.CreateFont(F_CLOSE,  { font = "Roboto", size = 14, weight = 400, antialias = true })

    -- =======================
    -- MENU UI
    -- =======================
    local ControllerFrame

    local function ShowControllerPopup()
        if IsValid(ControllerFrame) then ControllerFrame:Remove() end

        local W      = 360
        local HDR_H  = 42    
        local CORNER = 10
        local PAD    = 18

        local C_BG       = Color(14,  14,  14,  255)
        local C_HDR_BG   = Color(255, 255, 255, 255)
        local C_HDR_TEXT = Color(10,  10,  10,  255)
        local C_DIVIDER  = Color(40,  40,  40,  255)
        local C_WHITE    = Color(255, 255, 255, 255)
        local C_MUTED    = Color(120, 120, 120, 255)
        local C_PILL_ON  = Color(255, 255, 255, 255)
        local C_PILL_OFF = Color(45,  45,  45,  255)
        local C_BTN      = Color(32,  32,  32,  255)
        local C_BTN_HOV  = Color(52,  52,  52,  255)
        local C_TRACK    = Color(35,  35,  35,  255)
        local C_FILL     = Color(200, 200, 200, 255)

        local frame = vgui.Create("DFrame")
        frame:SetTitle("")
        frame:SetSize(W, 10)  
        frame:Center()
        frame:MakePopup()
        frame:SetDraggable(true)
        frame:ShowCloseButton(false)
        ControllerFrame = frame

        local curY = HDR_H

        frame.Paint = function(self, w, h)
            draw.RoundedBox(CORNER, 0, 0, w, h, C_BG)
            draw.RoundedBoxEx(CORNER, 0, 0, w, HDR_H, C_HDR_BG, true, true, false, false)
            draw.SimpleText("phantomware menu", F_HEADER, w/2, HDR_H/2, C_HDR_TEXT,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        local closeBtn = vgui.Create("DButton", frame)
        closeBtn:SetText("")
        closeBtn:SetSize(28, 28)
        closeBtn:SetPos(W - 36, (HDR_H - 28)/2)
        closeBtn.Paint = function(self, bw, bh)
            local bg = self:IsHovered() and Color(220,220,220,255) or Color(0,0,0,0)
            draw.RoundedBox(6, 0, 0, bw, bh, bg)
            draw.SimpleText("✕", F_CLOSE, bw/2, bh/2, C_HDR_TEXT,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        closeBtn.DoClick = function() frame:Close() end

        local function Divider(y)
            local d = vgui.Create("DPanel", frame)
            d:SetSize(W - PAD*2, 1)
            d:SetPos(PAD, y)
            d.Paint = function(self, w, h)
                surface.SetDrawColor(C_DIVIDER)
                surface.DrawRect(0, 0, w, h)
            end
        end

        local function SectionLabel(text, y)
            local lbl = vgui.Create("DLabel", frame)
            lbl:SetText(text)
            lbl:SetFont(F_SUB)
            lbl:SetTextColor(C_MUTED)
            lbl:SetPos(PAD, y)
            lbl:SizeToContents()
        end

        local ROW_H = 56
        local function MakeToggleRow(label, sublabel, yPos, getState, onToggle)
            local row = vgui.Create("DPanel", frame)
            row:SetSize(W - PAD*2, ROW_H)
            row:SetPos(PAD, yPos)
            row.Paint = function(self, w, h)
                if self:IsHovered() then
                    draw.RoundedBox(7, 0, 0, w, h, Color(255,255,255,4))
                end
            end

            local lbl = vgui.Create("DLabel", row)
            lbl:SetText(label)
            lbl:SetFont(F_LABEL)
            lbl:SetTextColor(C_WHITE)
            lbl:SetPos(0, 10)
            lbl:SizeToContents()

            local sub = vgui.Create("DLabel", row)
            sub:SetText(sublabel)
            sub:SetFont(F_SUB)
            sub:SetTextColor(C_MUTED)
            sub:SetPos(0, 30)
            sub:SizeToContents()

            local pillW, pillH = 44, 22
            local pill = vgui.Create("DButton", row)
            pill:SetText("")
            pill:SetSize(pillW, pillH)
            pill:SetPos(W - PAD*2 - pillW, (ROW_H - pillH)/2)
            pill.Paint = function(self, pw, ph)
                local on = getState()
                draw.RoundedBox(ph/2, 0, 0, pw, ph, on and C_PILL_ON or C_PILL_OFF)
                local kr = ph/2 - 3
                local kx = on and (pw - kr*2 - 4) or 4
                draw.RoundedBox(kr, kx, 3, kr*2, kr*2,
                    on and Color(14,14,14,255) or Color(100,100,100,255))
            end
            pill.DoClick = onToggle
            row.OnMouseReleased = function() onToggle() end
        end

        local SROW_H = 68
        local function MakeScrollRow(label, sublabel, yPos, getVal, setVal, step, minVal, maxVal, fmt)
            local row = vgui.Create("DPanel", frame)
            row:SetSize(W - PAD*2, SROW_H)
            row:SetPos(PAD, yPos)
            row.Paint = function(self, w, h) end

            local lbl = vgui.Create("DLabel", row)
            lbl:SetText(label)
            lbl:SetFont(F_LABEL)
            lbl:SetTextColor(C_WHITE)
            lbl:SetPos(0, 8)
            lbl:SizeToContents()

            local sub = vgui.Create("DLabel", row)
            sub:SetText(sublabel)
            sub:SetFont(F_SUB)
            sub:SetTextColor(C_MUTED)
            sub:SetPos(0, 26)
            sub:SizeToContents()

            local trackH = 2
            local track = vgui.Create("DPanel", row)
            track:SetSize(W - PAD*2, trackH)
            track:SetPos(0, SROW_H - 10)
            track.Paint = function(self, tw, th)
                draw.RoundedBox(1, 0, 0, tw, th, C_TRACK)
                local frac = math.Clamp((getVal() - minVal) / (maxVal - minVal), 0, 1)
                draw.RoundedBox(1, 0, 0, tw * frac, th, C_FILL)
            end

            local btnSz = 22
            local valW  = 80
            local clusterW = btnSz + 6 + valW + 6 + btnSz
            local clusterX = W - PAD*2 - clusterW
            local clusterY = 4

            local function clamp(v) return math.Clamp(v, minVal, maxVal) end

            local valLbl = vgui.Create("DLabel", row)
            valLbl:SetSize(valW, btnSz)
            valLbl:SetPos(clusterX + btnSz + 6, clusterY)
            valLbl:SetFont(F_VAL)
            valLbl:SetTextColor(C_WHITE)
            valLbl:SetContentAlignment(5)

            local function Refresh()
                valLbl:SetText(string.format(fmt, getVal()))
            end
            Refresh()

            local function MakeStepBtn(symbol, xPos, delta)
                local btn = vgui.Create("DButton", row)
                btn:SetText("")
                btn:SetSize(btnSz, btnSz)
                btn:SetPos(xPos, clusterY)
                btn.Paint = function(self, bw, bh)
                    draw.RoundedBox(6, 0, 0, bw, bh, self:IsHovered() and C_BTN_HOV or C_BTN)
                    draw.SimpleText(symbol, F_VAL, bw/2, bh/2, C_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                btn.DoClick = function()
                    setVal(clamp(getVal() + delta))
                    Refresh()
                end
                return btn
            end

            MakeStepBtn("−", clusterX, -step)
            MakeStepBtn("+", clusterX + btnSz + 6 + valW + 6, step)

            row.OnMouseWheeled = function(self, delta)
                setVal(clamp(getVal() + delta * step))
                Refresh()
                return true
            end
        end

        curY = curY + 8
        SectionLabel("CONTROLS", curY)
        curY = curY + 16

        MakeToggleRow("Aimbot", "Pull toward nearest player",
            curY,
            function() return aimAssistEnabled end,
            function() aimAssistEnabled = not aimAssistEnabled end)
        curY = curY + ROW_H

        Divider(curY)
        curY = curY + 1

        -- NEW TRIGGERBOT TOGGLE ROW
        MakeToggleRow("Triggerbot", "Auto-fires when target in crosshair",
            curY,
            function() return triggerEnabled end,
            function() triggerEnabled = not triggerEnabled end)
        curY = curY + ROW_H

        Divider(curY)
        curY = curY + 1

        MakeToggleRow("Box & Skeleton ESP", "Visual overlays for players",
            curY,
            function() return espEnabled end,
            function() espEnabled = not espEnabled end)
        curY = curY + ROW_H

        Divider(curY)
        curY = curY + 1

        MakeToggleRow("Crosshair Ring", "Shows aimbot zone on screen",
            curY,
            function() return crosshairEnabled end,
            function() crosshairEnabled = not crosshairEnabled end)
        curY = curY + ROW_H + 6

        Divider(curY)
        curY = curY + 12

        SectionLabel("ADJUSTMENTS", curY)
        curY = curY + 16

        MakeScrollRow("Vertical Offset", "Scroll · height on target body  (-50 → 100)",
            curY,
            function() return aimOffset end,
            function(v) aimOffset = v end,
            1, -50, 100, "%.0f")
        curY = curY + SROW_H + 8

        Divider(curY)
        curY = curY + 8

        MakeScrollRow("Falloff Distance", "Scroll · range where assist fades out (hu)",
            curY,
            function() return aimFalloffEnd end,
            function(v) aimFalloffEnd = v end,
            100, 500, 15000, "%.0f hu")
        curY = curY + SROW_H + 14

        local footerLbl = vgui.Create("DLabel", frame)
        footerLbl:SetText("Open with  F + J + K + M")
        footerLbl:SetFont(F_SUB)
        footerLbl:SetTextColor(Color(55, 55, 55, 255))
        footerLbl:SizeToContents()
        footerLbl:SetPos(W/2 - footerLbl:GetWide()/2, curY)
        curY = curY + 20

        frame:SetSize(W, curY)
        frame:Center()
    end

   -- =======================
    -- KEYBIND (L + O + P + 0)
    -- =======================
    local lastMenuOpenTime = 0

    hook.Add("Think", "ControllerMenuKeybind", function()
        if input.IsKeyDown(KEY_L)
        and input.IsKeyDown(KEY_O)
        and input.IsKeyDown(KEY_P)
        and input.IsKeyDown(KEY_0)
        and CurTime() - lastMenuOpenTime > 0.5 then
            ShowControllerPopup()
            lastMenuOpenTime = CurTime()
        end
    end)

end