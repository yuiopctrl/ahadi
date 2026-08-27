import 'app_locale.dart';

/// UI translation table. Keys are dotted by feature area; each entry maps
/// [AppLanguage.sw] and [AppLanguage.en] to the display string.
const Map<String, Map<AppLanguage, String>> appTranslations = {
  // --- common ---
  'common.signOut': {AppLanguage.sw: 'Toka', AppLanguage.en: 'Sign out'},
  'common.cancel': {AppLanguage.sw: 'Ghairi', AppLanguage.en: 'Cancel'},
  'common.save': {AppLanguage.sw: 'Hifadhi', AppLanguage.en: 'Save'},
  'common.retry': {AppLanguage.sw: 'Jaribu tena', AppLanguage.en: 'Try again'},
  'common.create': {AppLanguage.sw: 'Unda', AppLanguage.en: 'Create'},
  'common.noEventSelected': {
    AppLanguage.sw: 'Hakuna tukio lililochaguliwa',
    AppLanguage.en: 'No event selected',
  },
  'common.pledged': {AppLanguage.sw: 'Ahadi', AppLanguage.en: 'Pledged'},

  // --- shell / navigation ---
  'shell.nav.home': {AppLanguage.sw: 'Nyumbani', AppLanguage.en: 'Home'},
  'shell.nav.events': {AppLanguage.sw: 'Matukio', AppLanguage.en: 'Events'},
  'shell.nav.payments': {AppLanguage.sw: 'Malipo', AppLanguage.en: 'Payments'},
  'shell.nav.more': {AppLanguage.sw: 'Zaidi', AppLanguage.en: 'More'},
  'shell.organizations': {
    AppLanguage.sw: 'Mashirika',
    AppLanguage.en: 'Organizations',
  },
  'shell.createAnotherOrganization': {
    AppLanguage.sw: 'Unda shirika lingine',
    AppLanguage.en: 'Create another organization',
  },
  'shell.events': {AppLanguage.sw: 'Matukio', AppLanguage.en: 'Events'},
  'shell.createEvent': {
    AppLanguage.sw: 'Unda Tukio',
    AppLanguage.en: 'Create Event',
  },
  'shell.createEventHint': {
    AppLanguage.sw: 'Unda tukio ili kuanza shughuli.',
    AppLanguage.en: 'Create an event to begin operations.',
  },
  'shell.changePin': {AppLanguage.sw: 'Badilisha PIN', AppLanguage.en: 'Change PIN'},
  'shell.ahadiUser': {AppLanguage.sw: 'Mtumiaji wa Ahadi', AppLanguage.en: 'Ahadi user'},
  'shell.invitationSingular': {
    AppLanguage.sw: 'Kuna mwaliko wa shirika',
    AppLanguage.en: 'Organization invitation available',
  },
  'shell.invitationPlural': {
    AppLanguage.sw: 'Mialiko {count} ya mashirika',
    AppLanguage.en: '{count} organization invitations',
  },
  'shell.more.messages': {AppLanguage.sw: 'Ujumbe', AppLanguage.en: 'Messages'},
  'shell.more.contacts': {AppLanguage.sw: 'Mawasiliano', AppLanguage.en: 'Contacts'},
  'shell.more.pledges': {AppLanguage.sw: 'Ahadi', AppLanguage.en: 'Pledges'},
  'shell.more.receipts': {AppLanguage.sw: 'Risiti', AppLanguage.en: 'Receipts'},
  'shell.more.outstanding': {AppLanguage.sw: 'Deni Lililobaki', AppLanguage.en: 'Outstanding'},
  'shell.more.shareList': {AppLanguage.sw: 'Shiriki Orodha', AppLanguage.en: 'Share List'},
  'shell.more.usersRoles': {AppLanguage.sw: 'Watumiaji na Majukumu', AppLanguage.en: 'Users & Roles'},
  'shell.more.reports': {AppLanguage.sw: 'Ripoti', AppLanguage.en: 'Reports'},
  'shell.more.activity': {AppLanguage.sw: 'Shughuli', AppLanguage.en: 'Activity'},
  'shell.more.subscription': {AppLanguage.sw: 'Usajili', AppLanguage.en: 'Subscription'},
  'shell.more.settings': {AppLanguage.sw: 'Mipangilio', AppLanguage.en: 'Settings'},
  'shell.more.profile': {AppLanguage.sw: 'Wasifu', AppLanguage.en: 'Profile'},

  // --- settings ---
  'settings.title': {AppLanguage.sw: 'Mipangilio', AppLanguage.en: 'Settings'},
  'settings.messaging': {AppLanguage.sw: 'Ujumbe', AppLanguage.en: 'Messaging'},
  'settings.language': {AppLanguage.sw: 'Lugha', AppLanguage.en: 'Language'},
  'settings.languageHint': {
    AppLanguage.sw: 'Chagua lugha ya maonyesho ya programu.',
    AppLanguage.en: 'Choose the app display language.',
  },
  'settings.language.sw': {AppLanguage.sw: 'Kiswahili', AppLanguage.en: 'Kiswahili'},
  'settings.language.en': {AppLanguage.sw: 'Kiingereza', AppLanguage.en: 'English'},

  // --- auth ---
  'auth.signIn': {AppLanguage.sw: 'Ingia', AppLanguage.en: 'Sign in'},
  'auth.signInHint': {
    AppLanguage.sw: 'Tumia namba yako ya simu iliyothibitishwa na PIN ya tarakimu 4.',
    AppLanguage.en: 'Use your verified phone number and 4 digit PIN.',
  },
  'auth.phoneNumber': {AppLanguage.sw: 'Namba ya simu', AppLanguage.en: 'Phone number'},
  'auth.login': {AppLanguage.sw: 'Ingia', AppLanguage.en: 'Login'},
  'auth.forgotPin': {AppLanguage.sw: 'Umesahau PIN?', AppLanguage.en: 'Forgot PIN?'},
  'auth.newToAhadi': {AppLanguage.sw: 'Mgeni kwa Ahadi?', AppLanguage.en: 'New to Ahadi?'},
  'auth.createAccount': {AppLanguage.sw: 'Fungua Akaunti', AppLanguage.en: 'Create Account'},
  'auth.checking': {AppLanguage.sw: 'Inaangalia...', AppLanguage.en: 'Checking...'},
  'auth.continue': {AppLanguage.sw: 'Endelea', AppLanguage.en: 'Continue'},
  'auth.backToLogin': {AppLanguage.sw: 'Rudi Kuingia', AppLanguage.en: 'Back to Login'},
  'auth.existingAccountMessage': {
    AppLanguage.sw: 'Namba hii ya simu tayari ina akaunti ya Ahadi.\nIngia kwa kutumia PIN yako.',
    AppLanguage.en: 'This phone number already has an Ahadi account.\nLog in using your PIN.',
  },
  'auth.codeSentTo': {AppLanguage.sw: 'Msimbo umetumwa kwa', AppLanguage.en: 'Code sent to'},
  'auth.sixDigitCode': {AppLanguage.sw: 'Msimbo wa tarakimu sita', AppLanguage.en: 'Six-digit code'},
  'auth.verifying': {AppLanguage.sw: 'Inathibitisha...', AppLanguage.en: 'Verifying...'},
  'auth.verifyCode': {AppLanguage.sw: 'Thibitisha Msimbo', AppLanguage.en: 'Verify code'},
  'auth.confirmPin': {AppLanguage.sw: 'Thibitisha PIN', AppLanguage.en: 'Confirm PIN'},
  'auth.saving': {AppLanguage.sw: 'Inahifadhi...', AppLanguage.en: 'Saving...'},
  'auth.fullName': {AppLanguage.sw: 'Jina Kamili', AppLanguage.en: 'Full Name'},
  'auth.email': {AppLanguage.sw: 'Barua Pepe', AppLanguage.en: 'Email'},
  'auth.notAMemberYet': {
    AppLanguage.sw: 'Kwa sasa wewe si mwanachama wa shirika lolote.',
    AppLanguage.en: 'You are not currently a member of an organization.',
  },
  'auth.createOrganization': {AppLanguage.sw: 'Unda Shirika', AppLanguage.en: 'Create Organization'},
  'auth.accountExists': {AppLanguage.sw: 'Akaunti ipo', AppLanguage.en: 'Account exists'},
  'auth.verifyPhone': {AppLanguage.sw: 'Thibitisha simu', AppLanguage.en: 'Verify phone'},
  'auth.setPin': {AppLanguage.sw: 'Weka PIN', AppLanguage.en: 'Set PIN'},
  'auth.completeProfile': {AppLanguage.sw: 'Kamilisha Wasifu', AppLanguage.en: 'Complete Profile'},
  'auth.youreInvited': {AppLanguage.sw: 'Umealikwa', AppLanguage.en: "You're Invited"},
  'auth.welcomeToAhadi': {AppLanguage.sw: 'Karibu Ahadi', AppLanguage.en: 'Welcome to Ahadi'},
  'auth.phoneStepHint': {
    AppLanguage.sw: 'Weka namba yako ya simu kuanza uthibitishaji wa akaunti.',
    AppLanguage.en: 'Enter your phone number to start account verification.',
  },
  'auth.existingStepHint': {
    AppLanguage.sw: 'Tumia kuingia kwa kawaida kwa akaunti za Ahadi zilizopo.',
    AppLanguage.en: 'Use normal login for returning Ahadi accounts.',
  },
  'auth.otpStepHint': {
    AppLanguage.sw: 'Weka msimbo uliotumwa kwa SMS.',
    AppLanguage.en: 'Enter the code sent by SMS.',
  },
  'auth.pinStepHint': {
    AppLanguage.sw: 'Unda PIN salama ya tarakimu 4.',
    AppLanguage.en: 'Create a secure 4-digit PIN.',
  },
  'auth.profileStepHint': {
    AppLanguage.sw: 'Jina hili linatumika katika akaunti yako yote ya Ahadi.',
    AppLanguage.en: 'This name is used across your Ahadi account.',
  },
  'auth.invitationsStepHint': {
    AppLanguage.sw: 'Angalia mialiko ya mashirika kwa namba yako ya simu iliyothibitishwa.',
    AppLanguage.en: 'Review organization invitations for your verified phone.',
  },
  'auth.welcomeStepHint': {
    AppLanguage.sw: 'Unda shirika baada tu ya akaunti yako kuwa tayari.',
    AppLanguage.en: 'Create an organization only after your account is ready.',
  },
  'auth.forgotPinTitle': {AppLanguage.sw: 'Umesahau PIN', AppLanguage.en: 'Forgot PIN'},
  'auth.sendCode': {AppLanguage.sw: 'Tuma Msimbo', AppLanguage.en: 'Send code'},
  'auth.verificationCode': {AppLanguage.sw: 'Msimbo wa Uthibitisho', AppLanguage.en: 'Verification code'},
  'auth.newPin': {AppLanguage.sw: 'PIN Mpya', AppLanguage.en: 'New PIN'},
  'auth.confirmNewPin': {AppLanguage.sw: 'Thibitisha PIN Mpya', AppLanguage.en: 'Confirm new PIN'},
  'auth.recoverPin': {AppLanguage.sw: 'Rejesha PIN yako', AppLanguage.en: 'Recover your PIN'},
  'auth.enterTheCode': {AppLanguage.sw: 'Weka msimbo', AppLanguage.en: 'Enter the code'},
  'auth.setNewPin': {AppLanguage.sw: 'Weka PIN mpya', AppLanguage.en: 'Set a new PIN'},
  'auth.recoverPinHint': {
    AppLanguage.sw: 'Tutathibitisha simu yako kabla ya kuruhusu kubadilisha PIN.',
    AppLanguage.en: 'We will verify your phone before allowing a PIN reset.',
  },
  'auth.enterCodeHint': {
    AppLanguage.sw: 'Tumia msimbo wa SMS uliotumwa na Ahadi.',
    AppLanguage.en: 'Use the SMS code sent by Ahadi.',
  },
  'auth.setNewPinHint': {
    AppLanguage.sw: 'Chagua PIN ya tarakimu 4 usiyoitumia mahali pengine.',
    AppLanguage.en: 'Choose a 4 digit PIN you have not used elsewhere.',
  },
  'auth.invitedToJoin': {
    AppLanguage.sw: 'Umealikwa kujiunga na shirika hili.',
    AppLanguage.en: 'You have been invited to join this organization.',
  },
  'auth.role': {AppLanguage.sw: 'Jukumu', AppLanguage.en: 'Role'},
  'auth.name': {AppLanguage.sw: 'Jina', AppLanguage.en: 'Name'},
  'auth.decline': {AppLanguage.sw: 'Kataa', AppLanguage.en: 'Decline'},
  'auth.joining': {AppLanguage.sw: 'Inajiunga...', AppLanguage.en: 'Joining...'},
  'auth.joinOrganization': {AppLanguage.sw: 'Jiunge na Shirika', AppLanguage.en: 'Join Organization'},

  // --- dashboard ---
  'dashboard.title': {AppLanguage.sw: 'Dashibodi', AppLanguage.en: 'Dashboard'},
  'dashboard.loadError': {
    AppLanguage.sw: 'Imeshindwa kupakia dashibodi. Tafadhali jaribu tena.',
    AppLanguage.en: 'Unable to load dashboard. Please try again.',
  },
  'dashboard.chooseEventHint': {
    AppLanguage.sw: 'Chagua tukio kuona takwimu za dashibodi.',
    AppLanguage.en: 'Choose an event to view operational dashboard figures.',
  },
  'dashboard.totalPledged': {AppLanguage.sw: 'Jumla ya Ahadi', AppLanguage.en: 'Total Pledged'},
  'dashboard.received': {AppLanguage.sw: 'Zilizopokelewa', AppLanguage.en: 'Received'},
  'dashboard.outstanding': {AppLanguage.sw: 'Deni Lililobaki', AppLanguage.en: 'Outstanding'},
  'dashboard.members': {AppLanguage.sw: 'Wanachama', AppLanguage.en: 'Members'},
  'dashboard.noEventsYet': {
    AppLanguage.sw: 'Hakuna matukio yaliyoundwa bado.',
    AppLanguage.en: 'No events have been created yet.',
  },

  // --- common (filters) ---
  'common.all': {AppLanguage.sw: 'Yote', AppLanguage.en: 'All'},
  'common.active': {AppLanguage.sw: 'Hai', AppLanguage.en: 'Active'},
  'common.draft': {AppLanguage.sw: 'Rasimu', AppLanguage.en: 'Draft'},
  'common.closed': {AppLanguage.sw: 'Imefungwa', AppLanguage.en: 'Closed'},

  // --- events ---
  'events.newEvent': {AppLanguage.sw: 'Tukio Jipya', AppLanguage.en: 'New Event'},
  'events.noCreatePermission': {
    AppLanguage.sw: 'Jukumu lako halina ruhusa ya kuunda matukio.',
    AppLanguage.en: 'Your role does not include permission to create events.',
  },
  'events.noneMatchFilter': {
    AppLanguage.sw: 'Hakuna matukio yanayolingana na kichujio hiki.',
    AppLanguage.en: 'No events match this filter.',
  },
  'events.eventName': {AppLanguage.sw: 'Jina la Tukio', AppLanguage.en: 'Event Name'},
  'events.eventType': {AppLanguage.sw: 'Aina ya Tukio', AppLanguage.en: 'Event Type'},
  'events.customEventType': {AppLanguage.sw: 'Aina Nyingine ya Tukio', AppLanguage.en: 'Custom Event Type'},
  'events.eventDate': {AppLanguage.sw: 'Tarehe ya Tukio MWAKA-MWEZI-SIKU', AppLanguage.en: 'Event Date YYYY-MM-DD'},
  'events.venue': {AppLanguage.sw: 'Mahali', AppLanguage.en: 'Venue'},
  'events.targetAmount': {AppLanguage.sw: 'Kiasi Kinacholengwa', AppLanguage.en: 'Target Amount'},
  'events.pledgeDeadline': {
    AppLanguage.sw: 'Mwisho wa Ahadi MWAKA-MWEZI-SIKU',
    AppLanguage.en: 'Pledge Deadline YYYY-MM-DD',
  },
  'events.creating': {AppLanguage.sw: 'Inaunda...', AppLanguage.en: 'Creating...'},
  'events.type.WEDDING': {AppLanguage.sw: 'Harusi', AppLanguage.en: 'Wedding'},
  'events.type.SENDOFF': {AppLanguage.sw: 'Send Off', AppLanguage.en: 'Send Off'},
  'events.type.FUNERAL': {AppLanguage.sw: 'Msiba', AppLanguage.en: 'Funeral'},
  'events.type.FUNDRAISER': {AppLanguage.sw: 'Uchangishaji', AppLanguage.en: 'Fundraiser'},
  'events.type.BIRTHDAY': {AppLanguage.sw: 'Siku ya Kuzaliwa', AppLanguage.en: 'Birthday'},
  'events.type.GRADUATION': {AppLanguage.sw: 'Mahafali', AppLanguage.en: 'Graduation'},
  'events.type.RELIGIOUS': {AppLanguage.sw: 'Kidini', AppLanguage.en: 'Religious'},
  'events.type.OTHER': {AppLanguage.sw: 'Nyingine', AppLanguage.en: 'Other'},
  'events.currentEvent': {AppLanguage.sw: 'Tukio la Sasa', AppLanguage.en: 'Current event'},
  'events.setCurrent': {AppLanguage.sw: 'Weka kama la sasa', AppLanguage.en: 'Set current'},
};
