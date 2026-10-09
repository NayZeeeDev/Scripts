-- ═══════════════════════════════════════════════════════════
--  LOCALE
--
--  L('key', ...) looks a line up in Config.Locale, then in English,
--  then gives back the key itself — so a line missing from a
--  translation shows up as its key instead of breaking anything.
--
--  Only the Lua side reads these. The bank UI, the ATM screen and
--  the phone app keep their text in web/.
-- ═══════════════════════════════════════════════════════════

function L(key, ...)
    local all  = Locales or {}
    local lang = all[Config and Config.Locale or 'en'] or {}
    local text = lang[key] or (all.en and all.en[key]) or key

    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, text, ...)
        if ok then return out end
    end
    return text
end
