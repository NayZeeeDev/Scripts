--[[
  nayzeee-garages <-> rtx_housing (RTX Development).         Support: automatic, optional edits (both)

  Without any edit nayzeee-garages reads every rtx_housing garage (GetAllProperties: garage
  { enabled, coords, heading }, owner, players whose rtx permissions include "garage") and draws
  its own point there. The three EDIT_ files only make rtx_housing hand its garage actions to
  nayzeee-garages and push changes at once.

  WHERE IT GOES
    rtx_housing/config.lua: set the garage system (one line):
]]

Config.GarageSystem = "nayzeee-garages"

--[[
  Then apply EDIT_client_other.lua and EDIT_server_other.lua.

  Zero-edit alternative: leave Config.GarageSystem on a garage script you do not run (for example
  "qb-garages" with qb-garages stopped). rtx then draws no garage interaction of its own and
  nayzeee-garages' point is the only one.

  UNCONFIRMED
    That the escrowed part of rtx_housing accepts a garage system name it does not list (the config
    comment says you can add your own in the other.lua files, which is what these edits do).
]]
