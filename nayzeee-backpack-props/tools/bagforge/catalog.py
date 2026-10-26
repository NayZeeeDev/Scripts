"""
The bags bagforge builds, and their colours.

Each entry is one inventory item. Its models share a shape; every model
carries one normal map, so colours of different materials (velvet vs croc)
live in separate models. Colour 1 of a model is <model>, colour n is <model>_n.
"""

def leather(c, trim='#c98a4b', metal='gold'):
    return {'body': {'kind': 'leather', 'colour': c}, 'trim': trim, 'metal': metal}


def patent(c, trim='#c98a4b', metal='gold'):
    return {'body': {'kind': 'patent', 'colour': c}, 'trim': trim, 'metal': metal}


def printed(c, motif, trim='#c98a4b', metal='gold'):
    return {'body': {'kind': 'print', 'colour': c, 'motif': motif}, 'trim': trim, 'metal': metal}


def croc(c, trim=None, metal='gold'):
    return {'body': {'kind': 'croc', 'colour': c}, 'trim': trim or c, 'metal': metal}


def velvet(c, trim='#141414', metal='gunmetal'):
    return {'body': {'kind': 'velvet', 'colour': c}, 'trim': trim, 'metal': metal}


def crochet(colours, pattern='zigzag', trim=None):
    return {'body': {'kind': 'crochet', 'colours': colours, 'pattern': pattern},
            'trim': trim or colours[0], 'metal': 'silver'}


def tartan(c, lines, trim='#c98a4b'):
    return {'body': {'kind': 'tartan', 'colour': c, 'lines': lines}, 'trim': trim, 'metal': 'gold'}


CATALOG = {
    'barrel': {
        'item': 'nayzeee_bag_barrel', 'label': 'Barrel Bag', 'design': 'barrel',
        'models': {
            'nayzeee_bag_barrel': [
                ('Cherry', printed('#f6eee2', 'cherry')),
                ('Rose', printed('#f3e4e6', 'rose')),
                ('Butterfly', printed('#e9f0f7', 'butterfly')),
                ('Sky', patent('#9cc8ec', trim='#f3f0ea')),
                ('Cream', leather('#efe6d4')),
                ('Black', leather('#1c1c1e', trim='#1c1c1e')),
            ],
            'nayzeee_bag_barrel_plaid': [
                ('Rose Plaid', tartan('#f2b9c8', [('#ffffff', 0.25, 0.04), ('#c2456b', 0.7, 0.06), ('#ffffff', 0.85, 0.015)])),
                ('Red Plaid', tartan('#b3202c', [('#111111', 0.3, 0.07), ('#f0c84a', 0.6, 0.012), ('#13284f', 0.8, 0.05)], trim='#3a2416')),
            ],
        },
    },
    'dome': {
        'item': 'nayzeee_bag_dome', 'label': 'Dome Satchel', 'design': 'dome',
        'models': {
            'nayzeee_bag_dome': [
                ('Cream', leather('#efe4cf', trim='#efe4cf')),
                ('Cherry Red', patent('#a3121d', trim='#a3121d')),
                ('Blush', leather('#f0c3c9', trim='#f0c3c9')),
                ('Black', leather('#18181a', trim='#18181a')),
                ('Olive', leather('#5d6237', trim='#5d6237')),
            ],
        },
    },
    'tophandle': {
        'item': 'nayzeee_bag_croc', 'label': 'Croc Top-Handle', 'design': 'tophandle',
        'models': {
            'nayzeee_bag_croc': [
                ('Lavender', croc('#b9a6d6')),
                ('Black', croc('#161618')),
                ('Red', croc('#8f121c')),
                ('Blush', croc('#e8b4bd')),
                ('Cream', croc('#eee3cf')),
            ],
        },
    },
    'sweetheart': {
        'item': 'nayzeee_bag_sweetheart', 'label': 'Sweetheart Tote', 'design': 'sweetheart',
        'models': {
            'nayzeee_bag_sweetheart': [
                ('Red', patent('#b0101c', trim='#b0101c', metal='silver')),
                ('Pink', patent('#f29bbb', trim='#f29bbb', metal='silver')),
                ('White', leather('#f4f2ee', trim='#f4f2ee', metal='silver')),
                ('Black', patent('#141416', trim='#141416', metal='silver')),
            ],
        },
    },
    'crochet': {
        'item': 'nayzeee_bag_crochet', 'label': 'Crochet Hobo', 'design': 'crochet',
        'models': {
            'nayzeee_bag_crochet': [
                ('Red Zigzag', crochet(['#c3202b', '#1d2c5e', '#f4f1ea'])),
                ('Green Argyle', crochet(['#2f7a3d', '#e9e2c9'], 'argyle')),
                ('Pastel', crochet(['#f5b7c8', '#bfe3f0', '#fbe7a6', '#cbe8c0'])),
                ('Black White', crochet(['#151515', '#f2f0ea'], 'argyle')),
            ],
        },
    },
    'weekender': {
        'item': 'nayzeee_bag_weekender', 'label': 'Velvet Weekender', 'design': 'weekender',
        'models': {
            'nayzeee_bag_weekender': [
                ('Black', velvet('#111113')),
                ('Navy', velvet('#16203f')),
                ('Wine', velvet('#4a0f1d')),
                ('Forest', velvet('#16331f')),
            ],
            'nayzeee_bag_weekender_croc': [
                ('Black Croc', croc('#141416', trim='#141416', metal='gunmetal')),
                ('Brown Croc', croc('#3f2616', trim='#2a1a10', metal='gold')),
            ],
        },
    },
}


# ---- backpacks (packtex layout) ---------------------------------------------------
# `loose`: also build <model>_loose, the bag with its straps lying flat, which
# the script shows whenever the bag isn't on someone's back.

def graffiti(base, inks, tag, trim='#141414', metal='gunmetal'):
    return {'style': 'graffiti', 'colour': base, 'inks': inks, 'tag': tag, 'trim': trim, 'metal': metal}


def check(dark, light, trim='#141414', metal='silver'):
    return {'style': 'check', 'colour': dark[0], 'dark': dark, 'light': light, 'trim': trim, 'metal': metal}


def drip(paint, base='#121212', metal='gunmetal'):
    return {'style': 'drip', 'colour': base, 'paint': paint, 'trim': base, 'metal': metal}


def mono(base, motif, trim='#161616', metal='gunmetal'):
    return {'style': 'mono', 'colour': base, 'motif': motif, 'trim': trim, 'metal': metal}


GREYS = ['#8c8c8c', '#b9b9b9', '#6a6a6a']

CATALOG.update({
    'graffiti': {
        'item': 'nayzeee_backpack_graffiti', 'label': 'Graffiti Backpack', 'design': 'backpack', 'loose': True,
        'models': {'nayzeee_backpack_graffiti': [
            ('Blackout', graffiti('#141414', GREYS, '#efe6cf')),
            ('Whiteout', graffiti('#ecebe6', ['#3a3a3a', '#5e5e5e', '#8a8a8a'], '#121212', trim='#ecebe6', metal='silver')),
            ('Blood Red', graffiti('#7d0d14', ['#1a1a1a', '#3a0508', '#d9d0c0'], '#f4efe4', trim='#1a1a1a')),
            ('Teal Tag', graffiti('#141414', ['#0b8c82', '#5b5b5b', '#2f6f6a'], '#08afa2')),
        ]},
    },
    'check': {
        'item': 'nayzeee_backpack_check', 'label': 'Split Check Backpack', 'design': 'backpack', 'loose': True,
        'models': {'nayzeee_backpack_check': [
            ('Black White', check(['#1d1d1d', '#303030'], ['#ececec', '#cfcfcf'])),
            ('Charcoal Grey', check(['#2b2b2d', '#3d3d40'], ['#a9a9ad', '#8f8f94'])),
            ('Black Pink', check(['#1d1d1d', '#303030'], ['#f6c6d6', '#ec9fbb'])),
            ('Black Teal', check(['#1d1d1d', '#303030'], ['#7fd8d0', '#08afa2'])),
        ]},
    },
    'drip': {
        'item': 'nayzeee_backpack_drip', 'label': 'Drip Backpack', 'design': 'backpack', 'loose': True,
        'models': {'nayzeee_backpack_drip': [
            ('Black Drip', drip('#060606')),
            ('Red Drip', drip('#c3121f')),
            ('Purple Drip', drip('#5d1d9e')),
            ('Teal Drip', drip('#08afa2')),
            ('Chrome Drip', drip('#c9ced4', metal='silver')),
        ]},
    },
    'mono': {
        'item': 'nayzeee_backpack_mono', 'label': 'Monogram Backpack', 'design': 'backpack', 'loose': True,
        'models': {'nayzeee_backpack_mono': [
            ('Charcoal', mono('#2a2c2e', '#3e4245')),
            ('Black', mono('#121212', '#262626')),
            ('Chocolate', mono('#3a2619', '#56392a', trim='#24170f', metal='gold')),
            ('Navy', mono('#141c33', '#25304f', trim='#0e1324')),
            ('Olive', mono('#3a3d26', '#53573a', trim='#262818')),
        ]},
    },
})
