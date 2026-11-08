--[[
  Headless test of the vehicle finance API (no FiveM needed).

  Runs the real server/db.lua, server/vehicles.lua, server/actions.lua (NZ.Finance) and
  server/exports.lua against the fake oxmysql of tools/smoke/vehfin_lib.lua, once per
  framework: QBCore (player_vehicles finance columns), Qbox (vehicle_financing table), ESX
  (our nz_finance column only). Traces: the nz_finance column added by the finance boot;
  SetFinance validation and storage; GetFinance; RecordFinancePayment (one instalment,
  several, too little / too much, paid off); the garage payment callback (money, refund-free
  path); the 'paid' / 'missed' / 'cleared' events and their arguments; the due-date check
  (missed once per due date, again after a further interval, never repeated); missedAction
  'block' / 'none' / 'impound' (canDrive, repossession, occupied vehicle waits); an export
  called from inside an event handler (no lock deadlock); ClearFinance; on QBCore a plan
  written by a vehicle shop (financetime countdown) and paid through that shop meanwhile.

  Usage (from the resource root):  lua5.4 tools/smoke/finance.lua [qb|qbx|esx]
  Without an argument it runs all three frameworks in separate processes.
]]

local framework = select(1, ...)
if framework == nil then
  local failed = false
  for _, fw in ipairs({ 'qb', 'qbx', 'esx' }) do
    local pipe = io.popen('lua5.4 tools/smoke/finance.lua ' .. fw .. ' 2>&1')
    local out = pipe:read('a')
    local okRun = pipe:close()
    io.write(out)
    if not okRun then failed = true end
  end
  if failed then os.exit(1) end
  return
end

local H = dofile('tools/smoke/vehfin_lib.lua')
local check = H.check
H.setup(framework, { financeColumn = false })

local impounds = {}
NZ.Impound.impound = function(plate, opts, src)
  impounds[#impounds + 1] = { plate = plate, opts = opts, src = src }
  NZ.DB.updateVehicle(plate, { state = 'impounded', impound = { locationId = opts.locationId, reason = opts.reason, fee = opts.fee,
    at = os.time(), releaseAt = os.time(), retrievable = true } })
  return true, nil, H.locations[opts.locationId]
end

H.load('server/vehicles.lua')
H.load('server/actions.lua')
H.load('server/exports.lua')
NZ.Ready = true

local HOUR = 3600
local Finance = NZ.Finance

--- Events of one kind for one plate.
local function eventsFor(kind, plate)
  local out = {}
  for _, e in ipairs(H.events('nayzeee-garages:finance:' .. kind)) do
    if e.args[1] == plate then out[#out + 1] = e end
  end
  return out
end

---------------------------------------------------------------------------------------
H.scenario = 'boot'
check(type(Finance) == 'table' and type(Finance.set) == 'function', 'NZ.Finance loaded')
for _, name in ipairs({ 'SetFinance', 'ClearFinance', 'GetFinance', 'RecordFinancePayment' }) do
  check(type(H.exports[name]) == 'function', 'export ' .. name .. ' registered')
end
check(not H.db.columns.nz_finance, 'nz_finance missing before boot')
H.advance(2500)
check(H.db.columns.nz_finance == true, 'finance boot adds the nz_finance column')
check(NZ.DB.schema.columns.nz_finance == true, 'schema reloaded with nz_finance')
check(NZ.DB.financeSupported() == true, 'finance supported on ' .. framework)

H.addRow({ plate = 'TRUCK01', model = 'phantom' })
H.addRow({ plate = 'CAR0002', model = 'sultan' })
H.addRow({ plate = 'CAR0003', model = 'sultan' })
H.addRow({ plate = 'OTHER04', model = 'sultan', owner = 'CID002' })

---------------------------------------------------------------------------------------
H.scenario = 'validation'
local okSet, res = H.export('SetFinance', 'TRUCK01', { balance = -5, payment = 100, paymentsTotal = 10, intervalHours = 24 })
check(okSet == false and type(res) == 'string', 'negative balance refused')
okSet, res = H.export('SetFinance', 'TRUCK01', { balance = 1000, payment = 100, intervalHours = 24 })
check(okSet == false, 'missing paymentsTotal refused')
okSet = H.export('SetFinance', 'TRUCK01', { balance = 1000, payment = 100, paymentsTotal = 10, intervalHours = 0 })
check(okSet == false, 'interval 0 refused')
okSet = H.export('SetFinance', 'TRUCK01', { balance = 1000, payment = 100, paymentsTotal = 10, intervalHours = 24,
  nextPaymentAt = H.now() + 20 * 366 * 86400 })
check(okSet == false, 'due date 20 years ahead refused')
okSet = H.export('SetFinance', 'TRUCK01', { balance = 1000, payment = 100, paymentsTotal = 10, intervalHours = 24,
  nextPaymentAt = (H.now() + 3600) * 1000 })
check(okSet == false, 'due date in milliseconds refused')
okSet = H.export('SetFinance', 'NOPE999', { balance = 1000, payment = 100, paymentsTotal = 10, intervalHours = 24 })
check(okSet == false, 'unknown vehicle refused')
okSet = H.export('SetFinance', 'BAD PLATE !!', { balance = 1000, payment = 100, paymentsTotal = 10, intervalHours = 24 })
check(okSet == false, 'invalid plate refused')
okSet = H.export('SetFinance', 'TRUCK01', '{"balance":"x"}')
check(okSet == false, 'garbage JSON plan refused')
check(H.export('GetFinance', 'TRUCK01') == nil, 'nothing owed yet')

---------------------------------------------------------------------------------------
H.scenario = 'set'
local t0 = H.now()
okSet, res = H.export('SetFinance', 'TRUCK01', { balance = 12000, payment = 1000, paymentsTotal = 12, intervalHours = 24 })
check(okSet == true and type(res) == 'table', 'plan set')
check(res and res.balance == 12000 and res.payment == 1000 and res.paymentsLeft == 12 and res.paymentsTotal == 12,
  'plan values returned')
check(res and res.nextPaymentAt == t0 + 24 * HOUR, 'first payment due one interval from now')
check(res and res.overdue == false and res.missed == 0, 'not overdue')
local raw = H.raw('TRUCK01')
local meta = json.decode(raw.nz_finance or 'null')
check(type(meta) == 'table' and meta.nextPaymentAt == t0 + 24 * HOUR and meta.by == 'nz_dealership', 'nz_finance record stored with caller')
if framework == 'qb' then
  check(raw.balance == 12000 and raw.paymentamount == 1000 and raw.paymentsleft == 12 and raw.financetime == 1440,
    'qb columns mirrored (financetime in minutes)')
elseif framework == 'qbx' then
  local fin = H.db.financing[raw.id]
  check(fin and fin.balance == 12000 and fin.paymentamount == 1000 and fin.paymentsleft == 12 and fin.financetime == 1440,
    'qbx vehicle_financing row written')
else
  check(raw.balance == nil, 'esx: no framework columns touched')
end
local got = H.export('GetFinance', 'TRUCK01')
check(got and got.balance == 12000 and got.nextPaymentAt == t0 + 24 * HOUR and got.intervalHours == 24, 'GetFinance reads the plan')
local log = H.logs[#H.logs]
check(log and log.event == 'vehicle.finance' and log.data.action == 'set' and log.data.resource == 'nz_dealership', 'set logged')

-- paymentsLeft derived from the balance; payment capped at the balance
okSet, res = H.export('SetFinance', 'CAR0002', { balance = 250, payment = 1000, paymentsTotal = 5, intervalHours = 2000 })
check(okSet and res.payment == 250 and res.paymentsLeft == 1, 'payment capped at the balance, one payment left')

---------------------------------------------------------------------------------------
H.scenario = 'record payment'
H.skip(2 * HOUR * 1000)
local okPay, after = H.export('RecordFinancePayment', 'TRUCK01', 500, 1)
check(okPay == false and type(after) == 'string', 'less than one instalment refused')
okPay = H.export('RecordFinancePayment', 'TRUCK01', 99999, 1)
check(okPay == false, 'more than the balance refused')
okPay = H.export('RecordFinancePayment', 'TRUCK01', 0)
check(okPay == false, 'zero refused')
okPay = H.export('RecordFinancePayment', 'TRUCK01', 1.5)
check(okPay == false, 'fraction refused')
local before = #H.events('nayzeee-garages:finance:paid')
okPay, after = H.export('RecordFinancePayment', 'TRUCK01', 1000, 1)
check(okPay == true and after and after.balance == 11000 and after.paymentsLeft == 11, 'one instalment recorded')
check(after and after.nextPaymentAt == H.now() + 24 * HOUR, 'next payment one interval from the payment')
local paid = H.events('nayzeee-garages:finance:paid')
check(#paid == before + 1, 'paid event fired once')
local pe = paid[#paid]
check(pe and pe.args[1] == 'TRUCK01' and pe.args[2].amount == 1000 and pe.args[2].balance == 11000
  and pe.args[2].paidOff == false and pe.args[2].source == 1 and pe.args[2].identifier == 'CID001'
  and pe.args[2].origin == 'export' and pe.args[2].resource == 'nz_dealership' and pe.args[2].owner == 'CID001',
  'paid event arguments')
okPay, after = H.export('RecordFinancePayment', 'TRUCK01', 3000, 99)
check(okPay and after.balance == 8000 and after.paymentsLeft == 8, 'three instalments at once')
check(after and after.nextPaymentAt == H.now() + 3 * 24 * HOUR, 'three intervals ahead')
pe = H.events('nayzeee-garages:finance:paid')
pe = pe[#pe]
check(pe and pe.args[2].source == nil and pe.args[2].instalments == 3, 'unknown player id not passed on; instalments counted')

---------------------------------------------------------------------------------------
H.scenario = 'garage payment'
local loc = H.locations[1]
NZ.Access.openSession(1, 'L1', loc)
local bank = H.bank[1]
local r = H.cb('nz:garage:payFinance', 1, { plate = 'TRUCK01', full = false })
check(r.ok == true and r.data and r.data.balance == 7000, 'garage instalment paid')
check(H.bank[1] == bank - 1000, 'money taken once')
pe = H.events('nayzeee-garages:finance:paid')
pe = pe[#pe]
check(pe and pe.args[2].origin == 'garage' and pe.args[2].source == 1, 'garage payment event')
r = H.cb('nz:garage:payFinance', 2, { plate = 'TRUCK01', full = true })
check(r.ok == false, 'no session / not the owner refused')
r = H.cb('nz:garage:payFinance', 1, { plate = 'OTHER04', full = true })
check(r.ok == false, 'someone else\'s vehicle refused')

---------------------------------------------------------------------------------------
H.scenario = 'missed'
local row = NZ.DB.getVehicle('TRUCK01')
local due = row.finance.nextPaymentAt
check(row.finance.overdue == false, 'not overdue before the due date')
do
  local listed = false
  for _, r2 in ipairs(H.run(NZ.DB.getFinanced) or {}) do if r2.plate == 'TRUCK01' then listed = true end end
  check(not listed, 'getFinanced: a plan not yet due is not loaded')
end
local okDrive = NZ.Vehicles.canDrive(1, row, { location = loc, garageKey = 'L1' })
check(okDrive == true, 'drivable while paid up')
H.skip((due - H.now() + 60) * 1000)
local missedBefore = #eventsFor('missed', 'TRUCK01')
-- (the background check of the finance boot may find it first while this runs)
local n = H.run(Finance.check)
check(n == 0 or n == 1, 'the check reports what it found')
local missed = eventsFor('missed', 'TRUCK01')
check(#missed == missedBefore + 1, 'missed event fired')
local me = missed[#missed]
check(me and me.args[1] == 'TRUCK01' and me.args[2].dueAt == due and me.args[2].missed == 1 and me.args[2].balance == 7000
  and me.args[2].action == 'block' and me.args[2].owner == 'CID001', 'missed event arguments')
check(H.notified(1, 'You missed a finance payment'), 'online owner told')
H.run(Finance.check)
check(#eventsFor('missed', 'TRUCK01') == missedBefore + 1, 'never repeated for the same due date')
row = NZ.DB.getVehicle('TRUCK01')
check(row.finance.overdue == true and row.finance.missed == 1, 'overdue, one missed payment stored')
do
  local found = nil
  for _, r2 in ipairs(H.run(NZ.DB.getFinanced) or {}) do if r2.plate == 'TRUCK01' then found = r2 end end
  check(found and found.finance and found.finance.overdue == true and type(found.props) == 'table' and found.owner == 'CID001', 'getFinanced: the overdue plan, full row')
end
local okDrive2, why = NZ.Vehicles.canDrive(1, row, { location = loc, garageKey = 'L1' })
check(okDrive2 == false and why == 'Finance payment overdue', 'block: the garage refuses it')
check(NZ.Finance.blocks(row) == true, 'Finance.blocks true (block)')
Config.Finance.missedAction = 'none'
check(NZ.Finance.blocks(row) == false, 'none: not blocked')
check(NZ.Vehicles.canDrive(1, row, { location = loc, garageKey = 'L1' }) == true, 'none: drivable while overdue')
Config.Finance.missedAction = 'block'
H.skip(24 * HOUR * 1000)
H.run(Finance.check)
missed = eventsFor('missed', 'TRUCK01')
check(#missed == missedBefore + 2 and missed[#missed].args[2].missed == 2
  and missed[#missed].args[2].dueAt == due + 24 * HOUR, 'a further interval unpaid counts again')
H.run(Finance.check)
check(#eventsFor('missed', 'TRUCK01') == missedBefore + 2, 'still no repeat')

-- paying clears the overdue state; the next due date restarts from the payment
okPay, after = H.export('RecordFinancePayment', 'TRUCK01', 1000)
check(okPay and after.overdue == false and after.nextPaymentAt == H.now() + 24 * HOUR and after.missed == 2,
  'payment ends the overdue state, missed count kept')
check(NZ.Vehicles.canDrive(1, NZ.DB.getVehicle('TRUCK01'), { location = loc, garageKey = 'L1' }) == true, 'drivable again')

---------------------------------------------------------------------------------------
H.scenario = 'impound'
Config.Finance.missedAction = 'impound'
H.locations[5].vehicleType = 'car'
okSet = H.export('SetFinance', 'CAR0003', { balance = 5000, payment = 500, paymentsTotal = 10, intervalHours = 12,
  nextPaymentAt = H.now() - 60 })
check(okSet == true, 'imported plan already due')
-- the car is out and somebody sits in it: repossession waits
NZ.DB.updateVehicle('CAR0003', { state = 'out' })
local car = H.spawn('CAR0003', 'sultan')
NZ.Vehicles.setOut('CAR0003', { entity = car, netId = H.entities[car].netId, src = 1, identifier = 'CID001' })
H.seat(1, car)
H.run(Finance.check)
local count = 0
for _, i in ipairs(impounds) do if i.plate == 'CAR0003' then count = count + 1 end end
check(count == 0, 'occupied vehicle not taken')
missed = eventsFor('missed', 'CAR0003')
check(#missed == 1 and missed[#missed].args[1] == 'CAR0003' and missed[#missed].args[2].action == 'impound', 'missed event says impound')
H.seat(1, nil)
H.run(Finance.check)
local last = impounds[#impounds]
check(last and last.plate == 'CAR0003' and last.opts.locationId == 5 and last.opts.reason == 'Missed finance payment'
  and last.src == nil, 'repossessed to the impound once left alone')
check(NZ.DB.getVehicle('CAR0003').state == 'impounded', 'state impounded')
check(H.notified(1, 'repossessed'), 'owner told about the repossession')
local before2 = #impounds
H.run(Finance.check)
check(#impounds == before2, 'not impounded twice')
Config.Finance.missedAction = 'block'

---------------------------------------------------------------------------------------
H.scenario = 'reentrant handler'
local inner = nil
AddEventHandler('nayzeee-garages:finance:paid', function(plate, data)
  if plate == 'CAR0002' and data.paidOff then
    inner = table.pack(NZ.Finance.get(plate), NZ.Finance.clear(plate, 'handler'))
  end
end)
okPay, after = H.export('RecordFinancePayment', 'CAR0002', 250, 1)
check(okPay == true and after == nil, 'paid off: no finance returned')
check(inner and inner[1] == nil and inner[2] == true, 'an export inside the event handler is not blocked by the lock')
local cleared = H.events('nayzeee-garages:finance:cleared')
local ce = cleared[#cleared]
check(ce and ce.args[1] == 'CAR0002' and ce.args[2].reason == 'paid', 'cleared event (paid)')
pe = H.events('nayzeee-garages:finance:paid')
pe = pe[#pe]
check(pe and pe.args[2].paidOff == true and pe.args[2].balance == 0, 'paid event paidOff')
raw = H.raw('CAR0002')
check(raw.nz_finance == nil, 'record removed')
if framework == 'qb' then check(raw.balance == 0 and raw.paymentsleft == 0, 'qb columns zeroed') end
if framework == 'qbx' then check(H.db.financing[raw.id].balance == 0, 'qbx financing zeroed') end

---------------------------------------------------------------------------------------
H.scenario = 'clear'
local okClear = H.export('ClearFinance', 'TRUCK01', 'Written off')
check(okClear == true, 'cleared')
cleared = H.events('nayzeee-garages:finance:cleared')
ce = cleared[#cleared]
check(ce.args[1] == 'TRUCK01' and ce.args[2].reason == 'Written off' and ce.args[2].balance == 6000
  and ce.args[2].resource == 'nz_dealership', 'cleared event arguments')
check(H.export('GetFinance', 'TRUCK01') == nil, 'nothing owed')
local n2 = #H.events('nayzeee-garages:finance:cleared')
check(H.export('ClearFinance', 'TRUCK01') == true and #H.events('nayzeee-garages:finance:cleared') == n2,
  'clearing nothing is fine and silent')
check(H.export('ClearFinance', 'NOPE999') == false, 'unknown vehicle')

---------------------------------------------------------------------------------------
if framework == 'qb' then
  H.scenario = 'vehicle shop plan'
  -- qb-vehicleshop wrote a plan (no nz_finance record): its financetime countdown is the clock
  H.addRow({ plate = 'SHOP005', model = 'sultan', extra = { balance = 3000, paymentamount = 300, paymentsleft = 10, financetime = 90 } })
  local f = NZ.DB.getVehicle('SHOP005').finance
  check(f and f.managed == false and f.overdue == false and f.nextPaymentHours == 1.5, 'shop plan read from the columns')
  H.raw('SHOP005').financetime = 0
  f = NZ.DB.getVehicle('SHOP005').finance
  check(f.overdue == true, 'countdown at zero: overdue')
  H.run(Finance.check)
  H.run(Finance.check)
  check(#eventsFor('missed', 'SHOP005') == 1, 'shop plan missed once')
  f = NZ.DB.getVehicle('SHOP005').finance
  check(f.managed == true and f.missed == 1, 'recorded: our due date takes over')
  -- the player pays at the vehicle shop: balance and countdown change under us
  local shop = H.raw('SHOP005')
  shop.balance, shop.paymentsleft, shop.financetime = 2700, 9, 1440
  f = NZ.DB.getVehicle('SHOP005').finance
  check(f.managed == false and f.overdue == false and f.balance == 2700, 'payment at the shop is seen, not overdue')
end

H.finish('finance ' .. framework)
