# Requests from the checkin module

## 1. Lead: `sql/install.sql` — `nza_tickets`

The module creates it on start (`server/modules/checkin.lua`); please add it to the install file:

```sql
CREATE TABLE IF NOT EXISTS `nza_tickets` (
  `id` VARCHAR(24) NOT NULL,
  `hospital` VARCHAR(64) NOT NULL,
  `day` CHAR(10) NOT NULL,
  `prefix` VARCHAR(4) NOT NULL,
  `number` INT NOT NULL,
  `identifier` VARCHAR(80) NULL,
  `name` VARCHAR(80) NULL,
  `triage` TINYINT NOT NULL DEFAULT 3,
  `status` VARCHAR(16) NOT NULL DEFAULT 'waiting',
  `bed` INT NULL,
  `handled_by` VARCHAR(80) NULL,
  `issued` INT NOT NULL,
  `called` INT NULL,
  `closed` INT NULL,
  `data` LONGTEXT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_nza_tickets_day` (`hospital`, `day`, `prefix`),
  KEY `idx_nza_tickets_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Status: done. `sql/install.sql` has the table, and the module's own statement
(`server/modules/checkin.lua`, start thread) is the same one (InnoDB, utf8mb4).

## 2. Dispatch (server): pager line API `NZA.Dispatch.Page(src, msg)`

New check-ins should also show on the EMS pager. `notifyStaff` already calls (guarded)
`NZA.Dispatch.Page(src, { kind = 'checkin', priority = 1..3, title = 'CHECK-IN A-014',
text = 'New patient A-014 · P2 Urgent', hospital = 'Pillbox Medical' })` when the function exists.
Request: expose it (push one line to that medic's pager history / LCD, with the pager beep).
Until then staff get the toast + pager sound in the NUI and the phone notification when paired.

Status: done. `NZA.Dispatch.Page` (`server/modules/dispatch.lua`) sends `nza:dispatch:page`; the
pager (`client/modules/dispatch_pager.lua`) logs the line, shows it on the glass and beeps.

## 3. Dispatch (client/NUI): "Call next patient" on the board's Hospital queue page

The board already lists `NZA.Checkin.Queue()`. A button (and key) on that page should send
`TriggerServerEvent('nza:checkin:callNext', hospitalId?)` — the handler checks the
`Config.Checkin.desk.perm` permission, resolves the medic's department (or the given one for
admins), calls the next ticket to a free bed and answers with a toast. The radial already has
`checkin_next` / `checkin_queue` under Dispatch.

Status: done. The ER intake page has "Call next" (key N) for staff with `desk.perm`
(`html/apps/dispatch/app.js` → `dispatch:callNext` in `client/modules/dispatch_board.lua`).

## 4. Wounded (NUI, optional): hide the downed HUD during the AI doctor

While the AI doctor treats a downed patient, the bed app adds `nza-bed-ai` to `<body>` and its
own stylesheet fades `#app-wounded` (`body.nza-bed-ai #app-wounded { opacity: 0 }`). If the
wounded module prefers an explicit API (e.g. `NZA.Wounded.HideHud(name, on)`), the checkin
client will switch to it.
