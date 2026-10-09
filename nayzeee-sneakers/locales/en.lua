--[[
    nayzeee-sneakers · English
    Copy this file to locales/<name>.lua, translate the right-hand side and set Config.Locale = '<name>'.
    Keep the %s / %d placeholders: they're filled in with names and numbers.
]]

Locales = Locales or {}

Locales.en = {
    -- boxes
    open = 'Open lid',
    close = 'Close lid',
    takeOut = 'Take shoes out',
    putIn = 'Put shoes in',
    pickUp = 'Pick up box',

    boxColour = 'Box colour',
    lastUsed = 'Last used',

    -- limited drops
    dropFrom = 'Plug Drops',
    dropAnnounce = 'DROP: %s. Only %d pairs at $%s. The raffle is open for %d minutes: enter in the Plug app or at the drop store.',
    dropWon = 'You won the %s raffle! Collect and pay at %s within %d minutes.',
    dropLost = 'No luck on the %s raffle this time.',
    dropWalkIn = '%d pair(s) of the %s are left: first come, first served at %s.',
    dropSoldOutAll = 'The %s drop is sold out.',
    dropOver = 'The %s drop is over.',
    dropEntered = 'You\'re in the %s raffle. Winners get a text when it closes.',
    dropAlready = 'You\'re already in this raffle',
    dropClosed = 'There\'s no drop on right now',
    dropGoStore = 'Collect it at %s',
    dropOnePer = 'One pair per person',
    dropSoldOut = 'Sold out',
    dropNoMoney = 'You need $%s',
    dropBought = 'Got the %s',
    dropEnter = 'Enter the raffle',
    dropCollect = 'Collect the drop',
    dropBuyLeft = 'Buy a pair',
    dropWhat = 'What\'s dropping',
    dropNone = 'Nothing is dropping right now. You\'ll get a text when something does.',
    dropSize = 'Your size',

    -- display cases
    dispOpen = 'Open door',
    dispClose = 'Close door',
    dispPut = 'Put a pair in',
    dispTake = 'Take the pair out',
    dispLook = 'Look at the pair',
    dispPickUp = 'Pick up case',
    dispLimit = 'You already have the max number of display cases out',
    dispNotYours = 'That is not your display case',
    dispNotEmpty = 'Take the pair out first',
    dispStacked = 'Take the cases on top off first',
    dispNoFit = 'None of your pairs fit in a %s',
    dispFull = 'There is already a pair in there',
    choosePair = 'Which pair?',
    noShoes = 'You have no shoes to put in',
    noEmptyBox = 'You need an empty %s',
    wrongBox = 'These need a %s',
    boxLimit = 'You already have the max number of boxes out',
    boxBusy = 'Hang on, the box is busy',
    notYours = 'That is not your box',
    modelMissing = 'Shoe box model is not streamed. Check nayzeee-sneakers/stream',

    -- a pair of shoes
    inspect = 'Inspect',
    inspectDesc = 'Turn them over and check the details',
    wear = 'Put them on',
    wearDesc = 'Swap them onto your feet',
    boxUp = 'Box them up',
    boxUpDesc = 'Put an empty box down and pack them',
    clean = 'Clean them',
    cleanDesc = 'Use a cleaning kit (%d%% dirty)',
    inspectHint = 'Hold LMB and drag to turn · Scroll to zoom · Backspace to put them away',

    -- wearing
    wrongGender = 'These are not made for your character',
    notFreemode = 'Only freemode characters can wear these',
    noClothing = 'This shoe has no clothing set up yet (config/shoes.lua)',
    noPack = 'The sneaker clothing pack is not running (nayzeee-sneakers-clothing)',
    putOn = 'Shoes on',
    tookOff = 'Shoes off',
    notWearing = 'You are not wearing any boxed shoes',
    noSpace = 'You have no room for that',

    -- dirt and cleaning
    gettingDirty = 'Your %s are getting dirty (%d%%)',
    wornDown = 'Your %s are now %s',
    alreadyClean = 'They\'re already clean',
    noKit = 'You need a cleaning kit',
    cleaned = 'Cleaned: %d%% dirty',
    cleanHint = 'X to stop',
    kitEmpty = 'Your cleaning kit is used up',
    kitUses = '%d uses left',

    -- crafting tables
    useTable = 'Use shoe table',
    pickUpTable = 'Pick up table',
    placeHint = 'Scroll to turn · E to place · Backspace to cancel',
    cantPlace = 'You can\'t put it there',
    tableTooClose = 'Too close to another table',
    tableLimit = 'You already have a table out',
    notYourTable = 'That is not your table',
    tableBusy = 'Someone is working at that table',
    noTableModel = 'Shoe table model not found. Install the Dragons Lab Shoe Table Pack',

    -- crafting
    craftHint = 'X to stop',
    craftHintView = 'X to stop · V to change view',
    viewThree = '3/4 view',
    viewFirst = 'First person',
    viewClose = 'Close-up',
    camera = 'Camera',
    levelTooLow = 'You need to be level %d',
    missingMaterial = 'You are missing %s',
    materialsGone = 'Your materials are gone',
    checkPassed = 'Clean work',
    checkFailed = 'Sloppy - that will show',
    craftCancelled = 'You stopped working',
    xpGained = '+%d XP',
    levelUp = 'Level up! You are now level %d',

    -- supplier
    browseSupplies = 'Browse supplies',
    bought = 'Paid $%d',
    noMoney = 'You can\'t afford that',

    -- selling
    plugTitle = 'Plug',
    offerIn = '%s wants your %s for $%s',
    dealSet = 'Meet %s at %s. GPS is set.',
    dealText = 'Bring the %s (US %s). %s. Don\'t be late.',
    dealGone = 'The deal is off',
    dealExpired = 'You took too long. %s left.',
    dealCancelled = 'You called off the deal',
    dealBusy = 'You already have a deal going',
    dealCooldown = 'Lay low for a bit before the next deal',
    pairGone = 'You don\'t have that pair any more',
    pairChanged = 'That\'s not the pair they were promised. They walked',
    makeDeal = 'Make the deal',
    buyerArrived = '%s is here',
    buyerOnWay = '%s is pulling up',
    tooFar = 'Get closer to the buyer',
    findCooldown = 'Give it a minute before you post that pair again',
    sold = 'Sold for $%s',
    caught = '%s caught the fake',
    copsCalled = 'They\'re calling the cops',
    walkUp = 'Walking up',
    driveUp = 'Pulling up',
    skip = 'Skip',

    -- police alert
    alertTitle = 'Counterfeit goods',
    alertFake = 'Caller reports someone selling fake sneakers',
    alertTip = 'Suspicious hand-to-hand deal in a parking lot',

    -- studio (/sneakerstudio)
    studioAlert = 'Sneaker studio: %d new shoes on the server, %d gone. Open /%s',
    studioOld = 'Your FiveM build can\'t list clothing packs. Update FiveM to use the studio scan',
    studioSaved = 'Saved',
    studioNoAccess = 'You don\'t have access to the sneaker studio',
    studioNoScreenshot = 'screenshot-basic is not running',
    studioNoProp = 'This shoe has no 3D prop yet. Build it in 3D props first',
    studioPhotoDone = 'Took %s photos. Restart ox_inventory to load the new icons',
    studioCancelled = 'Batch stopped',
    studioNothing = 'Every shoe already has a photo',
    studioPhotoSaved = 'Saved %s.png%s',
    studioPhotoFailed = 'Could not save %s',
    studioKeyFailed = 'The photo could not be keyed: %s',
    kitMissing = 'sneakerkit isn\'t installed for this server\'s OS (tools/sneakerkit)',
    kitBusy = 'sneakerkit is already running',
    kitDone = '3D props: built %s shoe(s)',

    -- results banner
    bnSold = 'Pair Sold',
    bnCaught = 'Deal Blown',
    bnOffer = 'Offer',
    bnPaid = 'Paid',
    bnRep = 'Rep',
    bnXP = 'XP',
}
