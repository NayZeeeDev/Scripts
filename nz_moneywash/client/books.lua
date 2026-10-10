--[[ Front businesses — Cook the Books (declare) + Treasury inspection ]]

FrontDesk = {}

function FrontDesk.open(frontId)
    U.run(function()
        local data = lib.callback.await('nzmw:books:open', false, frontId)
        if not data or not data.ok then return UI.err(data) end
        data.labels = Config.ItemLabels
        data.finalItem = NZ.finalItem()
        data.heatPenaltyMax = Config.Heat.payoutPenaltyMax
        UI.await('books', data)
    end)
end

function FrontDesk.audit(frontId)
    U.run(function()
        local data = lib.callback.await('nzmw:audit:open', false, frontId)
        if not data or not data.ok then return UI.err(data) end
        data.flagAt = Config.Audit.flagAt
        UI.await('audit', data)
    end)
end

function FrontDesk.init()
    for _, f in ipairs(Config.Fronts) do
        Target.addZone('nzmw_front_' .. f.id, f.coords, f.radius or 1.0, {
            { name = 'books', label = 'Cook the books', icon = 'fas fa-book-open',
              canInteract = function() return not U.busy and not UI.isOpen() end,
              onSelect = function() FrontDesk.open(f.id) end },
            { name = 'audit', label = 'Inspect the books', icon = 'fas fa-file-invoice-dollar',
              canInteract = function() return not U.busy and not UI.isOpen() and CBridge.isAuditor() end,
              onSelect = function() FrontDesk.audit(f.id) end },
        })
    end
end
