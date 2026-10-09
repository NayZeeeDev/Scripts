Locales = Locales or {}

Locales['en'] = {
    -- interface
    dashboard        = 'Dashboard',
    transactions     = 'Transactions',
    shared           = 'Shared accounts',
    society          = 'Society',
    savings          = 'Savings',
    loans            = 'Loans',
    bills            = 'Bills',
    scheduled        = 'Scheduled',
    settings         = 'Settings',

    deposit          = 'Deposit',
    withdraw         = 'Withdraw',
    transfer         = 'Transfer',
    close            = 'Close',

    -- notifications
    bank_title       = 'Bank',
    card_title       = 'Card',
    atm_title        = 'ATM',

    no_card          = 'You need an active bank card. Order one at any branch.',
    pin_prompt       = 'Enter your 4-digit PIN',
    pin_wrong        = 'Wrong PIN. %s attempts left.',
    pin_blocked      = 'Too many wrong PINs. The card is now blocked.',

    deposited        = 'Deposited %s.',
    withdrew         = 'Withdrew %s.',
    sent             = 'Sent %s to %s.',
    received         = '%s from %s',

    not_enough_cash  = 'You are not carrying that much cash.',
    not_enough_funds = 'Not enough in the account.',
    frozen           = 'This account is frozen.',
    no_rights        = 'You do not have rights for that here.',

    loan_approved    = '%s approved. %s is in your account.',
    loan_cleared     = 'The balance is settled and your credit improved.',
    loan_missed      = 'Payment %s of %s missed. Your credit took a hit.',
    loan_defaulted   = 'Your loan is in default and a penalty has been added.',

    bill_new         = '%s from %s',
    bill_overdue     = 'A late fee of %s was added to your %s bill.',
    interest_paid    = '%s added to your savings.',

    -- branches
    banking_title    = 'Banking',
    target_open      = 'Open banking',
    textui_open      = '[%s]  Open banking',
    branch_closed    = 'Bank closed',
    branch_opens     = 'The branch opens at %02d:00.',
    bank_no_answer   = 'The bank did not answer. Try again in a moment — if it keeps happening, the server console says why.',
    blocked_request  = 'Blocked request.',
    tellers_cleared  = 'Cleared %s teller%s within 60m. Restart the resource to respawn them.',

    -- card items
    card_blank       = 'This card has no details on it.',
    card_default     = 'Bank card',
    card_no_holder   = 'Unknown holder',

    -- phone
    phone_app_description = 'Balance, transfers, cards and bills',

    -- ATM
    atm_cant_now     = 'You can\'t do that right now.',
    atm_in_vehicle   = 'Get out of the vehicle first.',
    atm_no_card_on   = 'You don\'t have a bank card on you.',
    atm_no_answer    = 'The machine did not respond.',
    atm_moved        = 'You moved away from the machine.',
    atm_bank_silent  = 'The bank did not answer.',
    atm_busy         = 'That machine is still busy. Try again in a moment.',
    atm_which_card   = 'Which card?',
    atm_use          = 'Use ATM',
    atm_card_refused = 'The machine won\'t take that card.',
}
