--[[
  nayzeee-garages — server-only configuration (never sent to clients).
]]

ServerConfig = {}

-- Players in these framework groups can open the admin panel (in addition to the ace
-- permission `nayzeee-garages.admin`, e.g. `add_ace group.admin nayzeee-garages.admin allow`).
ServerConfig.AdminGroups = { 'god', 'superadmin', 'admin' }

-- Discord webhooks. Leave empty to disable. One URL can be reused for several channels.
ServerConfig.Webhooks = {
  default = '',     -- fallback for any event without its own channel
  vehicles = '',    -- retrieve, store, transfer, share, sell, recover
  impound = '',     -- impound / release / retrieve from impound
  admin = '',       -- every admin panel change
  security = '',    -- duplication attempts, invalid requests, rate limits
}

-- Also write logs into the `nz_logs` table (searchable history).
ServerConfig.DatabaseLogs = true

-- Show the "Import" button sources in the admin panel.
ServerConfig.ImportSources = { 'qb-garages', 'qbx_garages', 'json' }
