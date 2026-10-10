--[[
    Conversations: a close-up camera on the speaker and the NUI dialogue card.

    script = { start = 'a', nodes = { a = { text = '...', choices = { { label = '...', go = 'b' | false } } } } }
    A node without choices shows "Continue" and goes to `next` (or ends). `go = false` ends.
    play() returns the id of the last node shown, so callers can branch on how it ended.
]]

Dialogue = { active = false }

local pending

RegisterNUICallback('dialogue', function(data, cb)
    cb(1)
    if pending then pending:resolve(tonumber(data and data.i) or 0) end
end)

local function makeCam(ped)
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local fwd = GetEntityForwardVector(ped)
    local right = vec3(fwd.y, -fwd.x, 0.0)
    local pos = head + fwd * 1.15 + right * 0.35 + vec3(0.0, 0.0, 0.05)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 42.0, false, 0)
    PointCamAtCoord(cam, head.x, head.y, head.z - 0.05)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 600, true, false)
    return cam
end

---@param ped number speaker
---@param script table
---@param who { name: string, role?: string }
function Dialogue.play(ped, script, who)
    if Dialogue.active then return nil end
    Dialogue.active = true
    LocalPlayer.state:set('nzwlBusy', true, false)
    local cam = DoesEntityExist(ped) and makeCam(ped)
    if DoesEntityExist(ped) then TaskTurnPedToFaceEntity(cache.ped, ped, 1500) end
    DisplayRadar(false)
    UI.hud(false)
    UI.setFocus(true, true)

    local id, last = script.start, script.start
    while id do
        local node = script.nodes[id]
        if not node then break end
        last = id
        local labels = {}
        for i, c in ipairs(node.choices or {}) do labels[i] = c.label end
        pending = promise.new()
        UI.send('dialogue', { name = who.name, role = who.role, text = node.text, me = node.me, choices = labels })
        local pick = Citizen.Await(pending)
        pending = nil
        if pick < 0 then break end -- escape
        if node.choices and node.choices[pick] then
            local go = node.choices[pick].go
            if node.choices[pick].tag then last = node.choices[pick].tag end
            id = go or nil
        else
            id = node.next
        end
    end

    UI.send('dialogue', false)
    UI.setFocus(false)
    if cam then
        RenderScriptCams(false, true, 600, true, false)
        DestroyCam(cam, false)
    end
    DisplayRadar(true)
    LocalPlayer.state:set('nzwlBusy', false, false)
    Dialogue.active = false
    Main.refreshHud()
    return last
end
