-- luacheck config (global access is verified separately by tools/lua_globals.py)
std = 'lua54'
max_line_length = false
allow_defined_top = true
global = false
unused_args = false
ignore = {
  '212', -- unused argument
  '213', -- unused loop variable
  '431', -- shadowing upvalue (common with `source`, `data`)
  '432', -- shadowing upvalue argument
  '542', -- empty if branch
}
exclude_files = { 'web/**' }
