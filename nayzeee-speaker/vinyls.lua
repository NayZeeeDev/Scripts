--[[
    ██████╗ ███████╗ ██████╗ ██████╗ ██████╗ ██████╗ ███████╗
    ██╔══██╗██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝
    ██████╔╝█████╗  ██║     ██║   ██║██████╔╝██║  ██║███████╗
    ██╔══██╗██╔══╝  ██║     ██║   ██║██╔══██╗██║  ██║╚════██║
    ██║  ██║███████╗╚██████╗╚██████╔╝██║  ██║██████╔╝███████║
    ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚══════╝

    Records for the turntable. Each one is an inventory item holding a whole album.

    Tracks are found by SEARCH, not by link, so you never paste a video ID: the server looks up
    "<artist> <track title>" the first time a track is played and remembers what it found.

    ⚠️  The tracklists below were typed from memory. Most are right, but check any album you care
        about — a wrong title just finds the wrong song. The fastest way to get a perfect tracklist
        is to let the server fetch it:

            /vinylimport <spotify album link>        (needs Config.Spotify filled in)
            /vinylimport <youtube playlist link>

        That creates or overwrites a record with the real tracklist and cover art, live, no restart.
        Run /vinyllist to see every record, /vinyldelete <item> to remove an imported one.

    A track can also be { title = 'Song', link = '<youtube link or https audio link>' } to skip the search.

    cover: leave it nil and the server fetches the real album art (iTunes, then Spotify if configured),
           otherwise the record shows the plain NAYZEEE sleeve. Or paste any image link.

    Record shop (all optional):
      genre       = the shop's filter chip this record shows under ('Hip-Hop', 'R&B', ...)
      price       = what it costs in the shop (leave it out for Config.RecordShop.defaultPrice,
                    false = not sold in the shop)
      description = one short line under the album name in the shop
]]

Config.Vinyls = {

    ['vinyl_takecare'] = {
        artist = 'Drake', album = 'Take Care', year = 2011,
        genre = 'Hip-Hop', price = 300,
        description = "Drake's moody second album: late nights, slow burners and Marvins Room.",
        tracks = {
            'Over My Dead Body', 'Shot For Me', 'Headlines', 'Crew Love', 'Take Care',
            "Marvins Room", 'Buried Alive Interlude', 'Under Ground Kings', "We'll Be Fine",
            'Make Me Proud', 'Lord Knows', 'Cameras', 'Doing It Wrong', 'The Real Her',
            "Look What You've Done", 'HYFR', 'Practice', 'The Ride',
        },
    },

    ['vinyl_21'] = {
        artist = 'Adele', album = '21', year = 2011,
        genre = 'Pop', price = 300,
        description = "Adele's breakup record. Rolling in the Deep, Someone Like You and that voice.",
        tracks = {
            'Rolling in the Deep', 'Rumour Has It', 'Turning Tables', "Don't You Remember",
            'Set Fire to the Rain', "He Won't Go", 'Take It All', "I'll Be Waiting",
            'One and Only', 'Lovesong', 'Someone Like You',
        },
    },

    ['vinyl_carter4'] = {
        artist = 'Lil Wayne', album = 'Tha Carter IV', year = 2011,
        genre = 'Hip-Hop', price = 250,
        description = "Weezy's fourth Carter: 6 Foot 7 Foot, How to Love and John.",
        tracks = {
            'Blunt Blowin', 'MegaMan', '6 Foot 7 Foot', 'Nightmares of the Bottom', 'She Will',
            'How to Love', 'John', 'Abortion', 'So Special', 'How to Hate', 'President Carter',
            "It's Good", 'Mirror', 'Up Up and Away', 'I Like The View',
        },
    },

    ['vinyl_aiyoungboy'] = {
        -- check this one: a few deep cuts may be named differently
        artist = 'YoungBoy Never Broke Again', album = 'AI YoungBoy', year = 2017,
        genre = 'Hip-Hop', price = 250,
        description = "YoungBoy's 2017 tape, raw and straight out of Baton Rouge.",
        tracks = {
            'Untouchable', 'GG', 'No. 9', 'Win or Lose', 'Dirty Iyanna', 'Kick Yo Door',
            'Hypnotized', 'Overdose', 'Permanent Scar', 'Through The Storm',
        },
    },

    ['vinyl_music'] = {
        -- MUSIC is a 30-track album; these are the ones worth having on a record
        artist = 'Playboi Carti', album = 'MUSIC', year = 2025,
        genre = 'Hip-Hop', price = 300,
        description = "Carti's long-awaited third album, cut down to the essentials.",
        tracks = {
            'POP OUT', 'CRUSH', 'K POP', 'EVIL J0RDAN', 'MOJO JOJO', 'PHILLY', 'RADAR',
            'RATHER LIE', 'FINE SHIT', 'BACKD00R', 'TOXIC', 'MUNYUN', 'CHARGE DEM HOES A FEE',
            'GOOD CREDIT', 'WAKE UP F1LTHY',
        },
    },

    ['vinyl_2014fhd'] = {
        artist = 'J. Cole', album = '2014 Forest Hills Drive', year = 2014,
        genre = 'Hip-Hop', price = 300,
        description = 'J. Cole goes home: No Role Modelz, Wet Dreamz and Love Yourz.',
        tracks = {
            'January 28th', 'Wet Dreamz', "03' Adolescence", 'A Tale of 2 Citiez', 'Fire Squad',
            'St. Tropez', 'G.O.M.D.', 'No Role Modelz', 'Hello', 'Apparently', 'Love Yourz',
            'Note to Self',
        },
    },

    ['vinyl_ghettogospel'] = {
        artist = 'Rod Wave', album = 'Ghetto Gospel', year = 2019,
        genre = 'Hip-Hop', price = 250,
        description = "Rod Wave's soulful tape: Heart on Ice and pain you can sing along to.",
        tracks = {
            'Heart on Ice', 'Through the Wire', 'Dark Clouds', 'Rags2Riches', 'Brace Face',
            'Thief in the Night', 'Sky Priority', 'Hunger Games', 'Close Enough to Hurt',
            'Letter From Houston',
        },
    },

    ['vinyl_ibarelyknowher'] = {
        -- recent album: only the singles are listed, run /vinylimport for the full tracklist
        artist = 'sombr', album = 'I Barely Know Her', year = 2025,
        genre = 'Pop', price = 300,
        description = "sombr's debut: back to friends, undressed and big heartbreak guitars.",
        tracks = {
            'back to friends', 'undressed', '12 to 12', 'we never dated',
        },
    },

    ['vinyl_artist'] = {
        -- check this one
        artist = 'A Boogie Wit da Hoodie', album = 'Artist', year = 2017,
        genre = 'Hip-Hop', price = 250,
        description = "A Boogie's breakout tape: Jungle, Timeless and melodic Bronx records.",
        tracks = {
            'Bedrock', 'Not a Regular Person', 'Timeless', 'Beast Mode', 'No Promises',
            "Say A'", 'Nonchalant', 'Jungle',
        },
    },

    ['vinyl_bigscoom'] = {
        -- I don't know this tracklist. Run: /vinylimport <spotify album link>  to fill it in.
        artist = 'MAF Teeski', album = 'BIG SCOOM (Vol. 1)',
        genre = 'Hip-Hop', price = 250,
        description = 'MAF Teeski, loud and unfiltered.',
        tracks = {
            'BIG SCOOM',
        },
    },

    ['vinyl_itoldyou'] = {
        artist = 'Tory Lanez', album = 'I Told You', year = 2016,
        genre = 'R&B', price = 250,
        description = "Tory Lanez's debut album, a story record built around Luv and Say It.",
        tracks = {
            'I Told You / Another One', 'Say It', 'Luv', 'To D.R.E.A.M.', 'Flex',
            'Cold Hard Love', 'All The Girls', 'Loners Blvd', 'Question Is', 'Priceless',
        },
    },

    ['vinyl_kehlani'] = {
        -- the 2024 self-titled album; check the order
        artist = 'Kehlani', album = 'Kehlani',
        genre = 'R&B', price = 250,
        description = 'Smooth, late-night R&B from Kehlani.',
        tracks = {
            'After Hours', 'Next 2 You', 'Crash', 'Sucia', 'Deep', 'Vegas', 'GrooveTheory',
            '8', 'What I Want',
        },
    },

    ['vinyl_forbrokenears'] = {
        artist = 'Tems', album = 'For Broken Ears', year = 2020,
        genre = 'R&B', price = 250,
        description = "Tems' debut EP: Damages, Free Mind and Higher.",
        tracks = {
            'Interference', 'Damages', 'Free Mind', 'Higher', 'Looku Looku', 'The Key',
            'Ice T',
        },
    },

    ['vinyl_thriller'] = {
        artist = 'Michael Jackson', album = 'Thriller', year = 1982,
        genre = 'Classics', price = 400,
        description = 'The best-selling album of all time. Billie Jean, Beat It, Thriller.',
        tracks = {
            "Wanna Be Startin' Somethin'", 'Baby Be Mine', 'The Girl Is Mine', 'Thriller',
            'Beat It', 'Billie Jean', 'Human Nature', 'P.Y.T. (Pretty Young Thing)',
            'The Lady in My Life',
        },
    },

    ['vinyl_heartbreak'] = {
        artist = 'New Edition', album = 'Heart Break', year = 1988,
        genre = 'Classics', price = 350,
        description = "New Edition's new jack swing classic: If It Isn't Love, Can You Stand the Rain.",
        tracks = {
            "That's The Way We're Livin'", "If It Isn't Love", 'Can You Stand the Rain',
            'N.E. Heart Break', 'Where It All Started', 'Crucial', "You're Not My Kind of Girl",
            'Superlady', 'Competition', 'Boys to Men',
        },
    },
}
