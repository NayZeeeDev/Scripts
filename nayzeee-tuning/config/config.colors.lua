--  ██████╗ ██████╗ ██╗      ██████╗ ██████╗ ███████╗
-- ██╔════╝██╔═══██╗██║     ██╔═══██╗██╔══██╗██╔════╝
-- ██║     ██║   ██║██║     ██║   ██║██████╔╝███████╗
-- ██║     ██║   ██║██║     ██║   ██║██╔══██╗╚════██║
-- ╚██████╗╚██████╔╝███████╗╚██████╔╝██║  ██║███████║
--  ╚═════╝ ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝

-- GTA paint indexes grouped by finish. { index, label, preview hex }
Config.Paints = {
    { id = 'metallic', label = 'Metallic', colors = {
        { 0, 'Black', '#0d1116' }, { 1, 'Graphite Black', '#1c1d21' }, { 2, 'Black Steel', '#32383d' }, { 3, 'Dark Silver', '#454b4f' },
        { 4, 'Silver', '#999da0' }, { 5, 'Blue Silver', '#c2c4c6' }, { 6, 'Steel Gray', '#979a97' }, { 7, 'Shadow Silver', '#637380' },
        { 8, 'Stone Silver', '#63625c' }, { 9, 'Midnight Silver', '#3c3f47' }, { 10, 'Gun Metal', '#444e54' }, { 11, 'Anthracite Grey', '#1d2129' },
        { 27, 'Red', '#c00e1a' }, { 28, 'Torino Red', '#da1918' }, { 29, 'Formula Red', '#b6111b' }, { 30, 'Blaze Red', '#a51e23' },
        { 31, 'Graceful Red', '#7b1a22' }, { 32, 'Garnet Red', '#8e1b1f' }, { 33, 'Desert Red', '#6f1818' }, { 34, 'Cabernet Red', '#49111d' },
        { 35, 'Candy Red', '#b60f25' }, { 150, 'Lava Red', '#bc1917' }, { 143, 'Black Red', '#0e0d14' }, { 36, 'Sunrise Orange', '#d44a17' },
        { 38, 'Orange', '#f78616' }, { 104, 'Choco Orange', '#752b19' }, { 37, 'Classic Gold', '#c2944f' }, { 88, 'Taxi Yellow', '#ffcf20' },
        { 89, 'Race Yellow', '#fbe212' }, { 91, 'Yellow Bird', '#e0e13d' }, { 92, 'Lime', '#98d223' }, { 125, 'Securicor Green', '#83c566' },
        { 49, 'Dark Green', '#132428' }, { 50, 'Racing Green', '#122e2b' }, { 51, 'Sea Green', '#12383c' }, { 52, 'Olive Green', '#31423f' },
        { 53, 'Green', '#155c2d' }, { 54, 'Gasoline Blue Green', '#1b6770' }, { 61, 'Midnight Blue', '#222e46' }, { 62, 'Dark Blue', '#233155' },
        { 63, 'Saxony Blue', '#304c7e' }, { 64, 'Blue', '#47578f' }, { 65, 'Mariner Blue', '#637ba7' }, { 66, 'Harbor Blue', '#394762' },
        { 67, 'Diamond Blue', '#d6e7f1' }, { 68, 'Surf Blue', '#76afbe' }, { 69, 'Nautical Blue', '#345e72' }, { 70, 'Bright Blue', '#0b9cf1' },
        { 73, 'Ultra Blue', '#2354a1' }, { 74, 'Light Blue', '#6ea3c6' }, { 71, 'Purple Blue', '#2f2d52' }, { 72, 'Spinnaker Blue', '#282c4d' },
        { 141, 'Black Blue', '#0a0c17' }, { 146, 'Very Dark Blue', '#0b1421' }, { 142, 'Black Purple', '#0c0d18' }, { 145, 'Purple', '#621276' },
        { 137, 'Vermillion Pink', '#df5891' }, { 90, 'Bronze', '#916532' }, { 93, 'Champagne', '#9b8c78' }, { 94, 'Pueblo Beige', '#503218' },
        { 95, 'Dark Ivory', '#473f2b' }, { 96, 'Choco Brown', '#221b19' }, { 97, 'Golden Brown', '#653f23' }, { 98, 'Light Brown', '#775c3e' },
        { 99, 'Straw Beige', '#ac9975' }, { 100, 'Moss Brown', '#6c6b4b' }, { 101, 'Biston Brown', '#402e2b' }, { 102, 'Beechwood', '#a4965f' },
        { 103, 'Dark Beechwood', '#46231a' }, { 105, 'Beach Sand', '#bfae7b' }, { 106, 'Sun Bleached Sand', '#dfd5b2' }, { 107, 'Cream', '#f7edd5' },
        { 111, 'White', '#fffff6' }, { 112, 'Frost White', '#eaeaea' }, { 144, 'Hunter Green', '#9f9e8a' }, { 157, 'Epsilon Blue', '#afd6e4' },
    } },
    { id = 'matte', label = 'Matte', colors = {
        { 12, 'Black', '#13181f' }, { 13, 'Gray', '#26282a' }, { 14, 'Light Grey', '#515554' }, { 131, 'White', '#fcf9f1' },
        { 39, 'Red', '#cf1f21' }, { 40, 'Dark Red', '#732021' }, { 41, 'Orange', '#f27d20' }, { 42, 'Yellow', '#ffc91f' },
        { 55, 'Lime Green', '#66b81f' }, { 128, 'Green', '#4e6443' }, { 151, 'Forest Green', '#2d362a' }, { 152, 'Olive Drab', '#696748' },
        { 155, 'Foliage Green', '#5a6352' }, { 82, 'Dark Blue', '#1f2852' }, { 83, 'Blue', '#253aa7' }, { 84, 'Midnight Blue', '#1c3551' },
        { 148, 'Purple', '#6b1f7b' }, { 149, 'Dark Purple', '#1e1d22' }, { 129, 'Brown', '#bcac8f' }, { 153, 'Desert Brown', '#7a6c55' },
        { 154, 'Desert Tan', '#c3b492' },
    } },
    { id = 'metals', label = 'Metals', colors = {
        { 117, 'Brushed Steel', '#6a747c' }, { 118, 'Brushed Black Steel', '#354158' }, { 119, 'Brushed Aluminium', '#9ba0a8' },
        { 120, 'Chrome', 'linear-gradient(135deg,#f1f3f4,#8b939c 45%,#e6e9ec 55%,#4b525a)' }, { 158, 'Pure Gold', '#7a6440' },
        { 159, 'Brushed Gold', '#7f6a48' }, { 160, 'Light Gold', '#d9de86' }, { 147, 'Carbon Black', '#11141a' }, { 156, 'Alloy', '#81827f' },
    } },
    { id = 'util', label = 'Utility', colors = {
        { 15, 'Black', '#151921' }, { 16, 'Black Poly', '#1e2429' }, { 17, 'Dark Silver', '#333a3c' }, { 18, 'Silver', '#8c9095' },
        { 19, 'Gun Metal', '#39434d' }, { 20, 'Shadow Silver', '#506272' }, { 43, 'Red', '#9c1016' }, { 44, 'Bright Red', '#de0f18' },
        { 45, 'Garnet Red', '#8f1e17' }, { 56, 'Dark Green', '#22383e' }, { 57, 'Green', '#1d5a3f' }, { 75, 'Dark Blue', '#112552' },
        { 76, 'Midnight Blue', '#1b203e' }, { 77, 'Blue', '#275190' }, { 78, 'Sea Foam Blue', '#608592' }, { 79, 'Lightning Blue', '#2446a8' },
        { 80, 'Maui Blue Poly', '#4271e1' }, { 81, 'Bright Blue', '#3b39e0' }, { 108, 'Brown', '#3a2a1b' }, { 109, 'Medium Brown', '#785f33' },
        { 110, 'Light Brown', '#b5a079' }, { 122, 'Off White', '#dfddd0' }, { 127, 'Police Blue', '#4cc3da' }, { 134, 'Pure White', '#ffffff' },
        { 135, 'Hot Pink', '#f21f99' }, { 136, 'Salmon Pink', '#fdd6cd' }, { 138, 'Orange', '#f6ae20' }, { 139, 'Green', '#b0ee6e' },
        { 140, 'Blue', '#08e9fa' },
    } },
    { id = 'worn', label = 'Worn', colors = {
        { 21, 'Black', '#1e232f' }, { 22, 'Graphite', '#363a3f' }, { 23, 'Silver Grey', '#a0a199' }, { 24, 'Silver', '#d3d3d3' },
        { 25, 'Blue Silver', '#b7bfca' }, { 26, 'Shadow Silver', '#778794' }, { 46, 'Red', '#a94744' }, { 47, 'Golden Red', '#b16c51' },
        { 48, 'Dark Red', '#371c25' }, { 58, 'Dark Green', '#2d423f' }, { 59, 'Green', '#45594b' }, { 60, 'Sea Wash', '#65867f' },
        { 85, 'Dark Blue', '#4c5f81' }, { 86, 'Blue', '#58688e' }, { 87, 'Light Blue', '#74b5d8' }, { 113, 'Honey Beige', '#b0ab94' },
        { 114, 'Brown', '#453831' }, { 115, 'Dark Brown', '#2a282b' }, { 116, 'Straw Beige', '#726c57' }, { 121, 'Off White', '#eae6de' },
        { 123, 'Orange', '#f2ad2e' }, { 124, 'Light Orange', '#f9a458' }, { 126, 'Taxi Yellow', '#f1cc40' }, { 130, 'Orange', '#f8b658' },
        { 132, 'White', '#fffffb' }, { 133, 'Olive Army Green', '#81844c' },
    } },
}

-- Chameleon / flip paints need the gen9 paint ramp data streamed by another resource.
-- Turn this on only if your server already streams them (indexes 161 - 222).
Config.ChameleonPaints = {
    Enabled = false,
    PriceMultiplier = 3.0,
    colors = {
        { 161, 'Anodized Red', '#6b1414,#e06445' }, { 162, 'Anodized Wine', '#2d162d,#ba2065' }, { 163, 'Anodized Purple', '#181228,#6e0180' },
        { 164, 'Anodized Blue', '#110a55,#2d3ed4' }, { 165, 'Anodized Green', '#0b3c02,#2dd443' }, { 166, 'Anodized Lime', '#1e3c02,#85c846' },
        { 167, 'Anodized Copper', '#3c2802,#f3c889' }, { 168, 'Anodized Bronze', '#3c3502,#f3e789' }, { 169, 'Anodized Champagne', '#423b1f,#c6bda9' },
        { 170, 'Anodized Gold', '#614e01,#ddcf9e' }, { 171, 'Green Blue Flip', '#275909,#08232a' }, { 172, 'Green Red Flip', '#393a0e,#b7b901' },
        { 173, 'Green Brown Flip', '#572b4a,#746d25' }, { 174, 'Green Turquoise Flip', '#013701,#2b63a8' }, { 175, 'Green Purple Flip', '#334721,#4d358a' },
        { 176, 'Teal Purple Flip', '#00642e,#635398' }, { 177, 'Turquoise Red Flip', '#1e6a45,#630222' }, { 178, 'Turquoise Purple Flip', '#1e6a45,#3a153e' },
        { 179, 'Cyan Purple Flip', '#173f5f,#884da0' }, { 180, 'Blue Pink Flip', '#1e2e76,#7d507a' }, { 181, 'Blue Green Flip', '#13144f,#05282a' },
        { 182, 'Purple Red Flip', '#200073,#39028c' }, { 183, 'Purple Green Flip', '#6e0074,#001e25' }, { 184, 'Magenta Green Flip', '#594500,#71001a' },
        { 185, 'Magenta Yellow Flip', '#3a1f4c,#555819' }, { 186, 'Burgundy Green Flip', '#215718,#3b182b' }, { 187, 'Magenta Cyan Flip', '#382350,#0b526b' },
        { 188, 'Copper Purple Flip', '#23230b,#431358' }, { 189, 'Magenta Orange Flip', '#290419,#420f17' }, { 190, 'Red Orange Flip', '#c9291a,#db973d' },
        { 191, 'Orange Purple Flip', '#973601,#35003b' }, { 192, 'Orange Blue Flip', '#674e02,#150b2f' }, { 193, 'White Purple Flip', '#6f8887,#321256' },
        { 194, 'Red Rainbow Flip', '#330119,#004720' }, { 196, 'Dark Green Pearl', '#0d1f04,#001f19' }, { 197, 'Dark Teal Pearl', '#071f17,#052b5e' },
        { 198, 'Dark Blue Pearl', '#093832,#0c1c59' }, { 199, 'Dark Purple Pearl', '#4f165a,#1e5695' }, { 200, 'Oil Slick Pearl', '#160907,#0c1015' },
        { 201, 'Light Green Pearl', '#97c7f3,#66a09d' }, { 202, 'Light Blue Pearl', '#7196b9,#a8cae0' }, { 203, 'Light Purple Pearl', '#9ea2e2,#836fb2' },
        { 204, 'Light Pink Pearl', '#9d99b7,#a58aa8' }, { 205, 'Off White Pearl', '#83938f,#aec4c6' }, { 206, 'Pink Pearl', '#82568f,#943c67' },
        { 207, 'Yellow Pearl', '#877f6c,#89773d' }, { 208, 'Green Pearl', '#5b9291,#26acb7' }, { 209, 'Blue Pearl', '#578095,#43bfff' },
        { 210, 'Cream Pearl', '#86806d,#529b8f' }, { 211, 'White Prismatic', '#879dc6,#9fb4c5' }, { 212, 'Graphite Prismatic', '#4f6390,#343944' },
        { 213, 'Dark Blue Prismatic', '#132d65,#001023' }, { 214, 'Dark Purple Prismatic', '#222073,#120527' }, { 215, 'Hot Pink Prismatic', '#b214cc,#7b0161' },
        { 216, 'Dark Red Prismatic', '#8a1128,#550000' }, { 217, 'Dark Green Prismatic', '#09642e,#012c01' }, { 218, 'Black Prismatic', '#0f131e,#050505' },
        { 219, 'Black Oil Spill', '#5c2526,#136048' }, { 220, 'Black Rainbow', '#5a9300,#2c2a98' }, { 221, 'Black Holographic', '#469f69,#374a9a' },
        { 222, 'White Holographic', '#a17e95,#35a3c8' },
    },
}

-- Finishes offered with the RGB picker (GTA paint types)
Config.PaintFinishes = {
    { 0, 'Gloss' }, { 1, 'Metallic' }, { 2, 'Pearl' }, { 3, 'Matte' }, { 4, 'Brushed' }, { 5, 'Chrome' },
}

Config.XenonColors = {
    { -1, 'Stock', '#dfe9ff' }, { 0, 'White', '#ffffff' }, { 1, 'Blue', '#2c6fff' }, { 2, 'Electric Blue', '#00b4ff' },
    { 3, 'Mint Green', '#5cffb0' }, { 4, 'Lime Green', '#a2ff00' }, { 5, 'Yellow', '#ffe600' }, { 6, 'Golden Shower', '#ffc400' },
    { 7, 'Orange', '#ff7b00' }, { 8, 'Red', '#ff1a1a' }, { 9, 'Pony Pink', '#ff6bd5' }, { 10, 'Hot Pink', '#ff1f8e' },
    { 11, 'Purple', '#a14dff' }, { 12, 'Blacklight', '#4b1bff' },
}
Config.XenonCustomRGB = true            -- allow any RGB headlight color

Config.WindowTints = {
    { 0, 'None' }, { 4, 'Stock' }, { 3, 'Light Smoke' }, { 2, 'Dark Smoke' }, { 1, 'Pure Black' }, { 5, 'Limo' }, { 6, 'Green' },
}

Config.PlateStyles = {
    { 0, 'Blue on White 1' }, { 3, 'Blue on White 2' }, { 4, 'Exempt' }, { 1, 'Yellow on Black' }, { 2, 'Yellow on Blue' },
    { 5, 'North Yankton' },
}

Config.NeonPresets = {
    '#ffffff', '#08afa2', '#00d9ff', '#2c6fff', '#7a3bff', '#ff1fae', '#ff2d2d', '#ff8a00', '#ffe600', '#39ff14',
}

Config.SmokePresets = {
    '#ffffff', '#111111', '#08afa2', '#2c6fff', '#7a3bff', '#ff1fae', '#ff2d2d', '#ff8a00', '#ffe600', '#39ff14',
}

-- GTA wheel categories (wheel type id -> label). Motorcycles use 6 only when MotorcycleWheelsOnly.
Config.WheelTypes = {
    { 0, 'Sport', 'fa-bolt' }, { 1, 'Muscle', 'fa-dumbbell' }, { 2, 'Lowrider', 'fa-arrow-down-long' }, { 3, 'SUV', 'fa-truck-pickup' },
    { 4, 'Offroad', 'fa-mountain' }, { 5, 'Tuner', 'fa-screwdriver' }, { 7, 'High End', 'fa-gem' }, { 8, "Benny's Originals", 'fa-crown' },
    { 9, "Benny's Bespoke", 'fa-wand-magic-sparkles' }, { 10, 'Open Wheel', 'fa-flag-checkered' }, { 11, 'Street', 'fa-road' },
    { 12, 'Track', 'fa-stopwatch' }, { 6, 'Motorcycle', 'fa-motorcycle' },
}

-- Underglow animation modes (applied client-side on every nearby client)
Config.NeonPatterns = {
    { 'static',  'Static' },
    { 'pulse',   'Breathe' },
    { 'strobe',  'Strobe' },
    { 'chase',   'Chase' },
    { 'rainbow', 'Rainbow Cycle' },
    { 'dual',    'Dual Tone' },
    { 'police',  'Emergency Flash' },
}
