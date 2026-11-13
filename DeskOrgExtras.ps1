
# ==========================================================
# DeskOrg Control Center - extra features
# Preview, undo, history, rules editor, duplicates, tray icon,
# first-run welcome, languages, appearance, update check.
# Loaded (dot-sourced) by DeskOrgControlCenter.ps1.
# Credits: Nivesh Sahayak | https://www.niveshsahayak.in
# ==========================================================

$script:AppVersion = '1.2.0'
$script:UpdateUrl = 'https://deskorg.niveshsahayak.in/version.json'
$script:OrganizerScript = Join-Path $AppFolder 'DeskOrgOrganizer.ps1'
$script:PauseFile = Join-Path $DataFolder 'paused.flag'
$script:PreviewFile = Join-Path $DataFolder 'preview.json'
$script:LastRunFile = Join-Path $DataFolder 'lastrun.json'
$script:ProgressFile = Join-Path $DataFolder 'progress.json'
$script:DupFile = Join-Path $DataFolder 'duplicates.json'
$script:SettingsFile = Join-Path $DataFolder 'settings.json'
$script:RunsFolder = Join-Path $DataFolder 'Runs'
$script:RealExit = $false
$script:JobProc = $null
$script:JobTimer = $null
$script:JobDone = $null
$script:ProgressBar = $null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Data
Add-Type -AssemblyName Microsoft.VisualBasic

# One taskbar button with the DeskOrg icon (not PowerShell's).
try {
    Add-Type -Namespace DeskOrgNative -Name Shell -MemberDefinition '[System.Runtime.InteropServices.DllImport("shell32.dll")] public static extern int SetCurrentProcessExplicitAppUserModelID([System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPWStr)] string id);'
    [void][DeskOrgNative.Shell]::SetCurrentProcessExplicitAppUserModelID('NiveshSahayak.DeskOrg')
} catch { }

function Read-JsonSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

# ---------------- SETTINGS ----------------

function Get-Settings {
    $d = @{ Language = 'en'; TextScale = 100; HighContrast = $false; FirstRunDone = $false; LastSeenVersion = '' }
    $j = Read-JsonSafe $script:SettingsFile
    if ($j) { foreach ($k in @($d.Keys)) { if ($null -ne $j.$k) { $d[$k] = $j.$k } } }
    return $d
}

function Update-Setting {
    param([string]$Key, $Value)
    $script:Settings[$Key] = $Value
    try { ($script:Settings | ConvertTo-Json) | Set-Content -LiteralPath $script:SettingsFile -Encoding UTF8 } catch { }
}

$script:Settings = Get-Settings
$script:Lang = [string]$script:Settings.Language

# ---------------- WORDS (English, Hindi, Punjabi) ----------------

$script:Str = @{
    'yes' = @('Yes', 'हाँ', 'ਹਾਂ')
    'no' = @('No', 'नहीं', 'ਨਹੀਂ')
    'ok' = @('OK', 'ठीक है', 'ਠੀਕ ਹੈ')
    'cancel' = @('Cancel', 'रद्द करें', 'ਰੱਦ ਕਰੋ')
    'close' = @('Close', 'बंद करें', 'ਬੰਦ ਕਰੋ')
    'nav.Home' = @('Home', 'होम', 'ਹੋਮ')
    'nav.Organize' = @('Tidy up now', 'अभी व्यवस्थित करें', 'ਹੁਣ ਸੰਭਾਲੋ')
    'nav.Automation' = @('Keep it tidy automatically', 'अपने-आप व्यवस्थित रखें', 'ਆਪਣੇ-ਆਪ ਸੰਭਾਲ ਰੱਖੋ')
    'nav.Settings' = @('Where files go', 'फ़ाइलें कहाँ जाएँ', 'ਫ਼ਾਈਲਾਂ ਕਿੱਥੇ ਜਾਣ')
    'nav.Activity' = @('History', 'इतिहास', 'ਇਤਿਹਾਸ')
    'home.org.d' = @('Preview, tidy and undo.', 'पहले देखें, व्यवस्थित करें, वापस करें।', 'ਪਹਿਲਾਂ ਵੇਖੋ, ਸੰਭਾਲੋ, ਵਾਪਸ ਕਰੋ।')
    'home.auto.d' = @('Watch your folders and tidy them for you.', 'आपके फ़ोल्डर देखें और अपने-आप व्यवस्थित करें।', 'ਤੁਹਾਡੇ ਫ਼ੋਲਡਰ ਵੇਖੋ ਅਤੇ ਆਪਣੇ-ਆਪ ਸੰਭਾਲੋ।')
    'home.set.d' = @('Folders, file types, language and text size.', 'फ़ोल्डर, फ़ाइल प्रकार, भाषा और लिखावट का आकार।', 'ਫ਼ੋਲਡਰ, ਫ਼ਾਈਲ ਕਿਸਮਾਂ, ਭਾਸ਼ਾ ਅਤੇ ਲਿਖਤ ਦਾ ਆਕਾਰ।')
    'home.hist.d' = @('See what was tidied and put anything back.', 'देखें क्या व्यवस्थित हुआ और कुछ भी वापस रखें।', 'ਵੇਖੋ ਕੀ ਸੰਭਾਲਿਆ ਗਿਆ ਅਤੇ ਕੁਝ ਵੀ ਵਾਪਸ ਰੱਖੋ।')
    'title.Home' = @('Welcome back.', 'वापसी पर स्वागत है।', 'ਜੀ ਆਇਆਂ ਨੂੰ।')
    'sub.Home' = @('Your desktop. Your flow. Everything in its place.', 'आपका डेस्कटॉप। आपका तरीका। हर चीज़ अपनी जगह।', 'ਤੁਹਾਡਾ ਡੈਸਕਟਾਪ। ਤੁਹਾਡਾ ਤਰੀਕਾ। ਹਰ ਚੀਜ਼ ਆਪਣੀ ਥਾਂ।')
    'title.Organize' = @('Tidy up now', 'अभी व्यवस्थित करें', 'ਹੁਣ ਸੰਭਾਲੋ')
    'sub.Organize' = @('Preview, tidy and undo, all in one place.', 'पहले देखें, व्यवस्थित करें और वापस भी करें।', 'ਪਹਿਲਾਂ ਵੇਖੋ, ਸੰਭਾਲੋ ਅਤੇ ਵਾਪਸ ਵੀ ਕਰੋ।')
    'title.Automation' = @('Keep it tidy automatically', 'अपने-आप व्यवस्थित रखें', 'ਆਪਣੇ-ਆਪ ਸੰਭਾਲ ਰੱਖੋ')
    'sub.Automation' = @('Choose how DeskOrg watches and maintains your folders.', 'चुनें कि DeskOrg आपके फ़ोल्डर कैसे देखे और सँभाले।', 'ਚੁਣੋ ਕਿ DeskOrg ਤੁਹਾਡੇ ਫ਼ੋਲਡਰ ਕਿਵੇਂ ਵੇਖੇ ਅਤੇ ਸੰਭਾਲੇ।')
    'title.Settings' = @('Where files go', 'फ़ाइलें कहाँ जाएँ', 'ਫ਼ਾਈਲਾਂ ਕਿੱਥੇ ਜਾਣ')
    'sub.Settings' = @('Your rules, language and appearance.', 'आपके नियम, भाषा और रूप-रंग।', 'ਤੁਹਾਡੇ ਨਿਯਮ, ਭਾਸ਼ਾ ਅਤੇ ਦਿੱਖ।')
    'title.Activity' = @('History', 'इतिहास', 'ਇਤਿਹਾਸ')
    'sub.Activity' = @('See what was tidied, and put anything back.', 'देखें क्या व्यवस्थित हुआ, और कुछ भी वापस रखें।', 'ਵੇਖੋ ਕੀ ਸੰਭਾਲਿਆ ਗਿਆ, ਅਤੇ ਕੁਝ ਵੀ ਵਾਪਸ ਰੱਖੋ।')
    'org.card' = @('Tidy your folders', 'अपने फ़ोल्डर व्यवस्थित करें', 'ਆਪਣੇ ਫ਼ੋਲਡਰ ਸੰਭਾਲੋ')
    'org.card.desc' = @('Look first, then tidy. Everything can be undone.', 'पहले देखें, फिर व्यवस्थित करें। सब कुछ वापस हो सकता है।', 'ਪਹਿਲਾਂ ਵੇਖੋ, ਫਿਰ ਸੰਭਾਲੋ। ਸਭ ਕੁਝ ਵਾਪਸ ਹੋ ਸਕਦਾ ਹੈ।')
    'org.preview' = @('Preview first', 'पहले पूर्वावलोकन', 'ਪਹਿਲਾਂ ਝਲਕ ਵੇਖੋ')
    'org.preview.d' = @('See which files would move and where. Nothing is moved.', 'देखें कौन-सी फ़ाइलें कहाँ जाएँगी। कुछ भी नहीं हिलता।', 'ਵੇਖੋ ਕਿਹੜੀਆਂ ਫ਼ਾਈਲਾਂ ਕਿੱਥੇ ਜਾਣਗੀਆਂ। ਕੁਝ ਵੀ ਨਹੀਂ ਹਿੱਲਦਾ।')
    'org.now' = @('Organize now', 'अभी व्यवस्थित करें', 'ਹੁਣੇ ਸੰਭਾਲੋ')
    'org.now.d' = @('Tidy your folders using your rules. You can undo it.', 'आपके नियमों से फ़ोल्डर व्यवस्थित करें। इसे वापस किया जा सकता है।', 'ਤੁਹਾਡੇ ਨਿਯਮਾਂ ਨਾਲ ਫ਼ੋਲਡਰ ਸੰਭਾਲੋ। ਇਹ ਵਾਪਸ ਹੋ ਸਕਦਾ ਹੈ।')
    'org.undo' = @('Undo last organize', 'पिछला व्यवस्थित करना वापस करें', 'ਪਿਛਲਾ ਸੰਭਾਲਣਾ ਵਾਪਸ ਕਰੋ')
    'org.undo.d' = @('Put the files from the last organize back where they were.', 'पिछली बार की फ़ाइलें वहीं वापस रखें जहाँ से आई थीं।', 'ਪਿਛਲੀ ਵਾਰ ਦੀਆਂ ਫ਼ਾਈਲਾਂ ਉਥੇ ਹੀ ਵਾਪਸ ਰੱਖੋ ਜਿੱਥੋਂ ਆਈਆਂ ਸਨ।')
    'org.dups' = @('Find duplicate files', 'एक जैसी फ़ाइलें खोजें', 'ਇੱਕ ਵਰਗੀਆਂ ਫ਼ਾਈਲਾਂ ਲੱਭੋ')
    'org.dups.d' = @('Find identical copies and move the extras to the Recycle Bin. Nothing is deleted without your choice.', 'एक जैसी प्रतियाँ खोजें और अतिरिक्त को रीसायकल बिन में भेजें। आपकी पसंद के बिना कुछ नहीं हटता।', 'ਇੱਕੋ ਜਿਹੀਆਂ ਕਾਪੀਆਂ ਲੱਭੋ ਅਤੇ ਵਾਧੂ ਰੀਸਾਈਕਲ ਬਿਨ ਵਿੱਚ ਭੇਜੋ। ਤੁਹਾਡੀ ਚੋਣ ਬਿਨਾਂ ਕੁਝ ਨਹੀਂ ਹਟਦਾ।')
    'tray.open' = @('Open DeskOrg', 'DeskOrg खोलें', 'DeskOrg ਖੋਲ੍ਹੋ')
    'tray.now' = @('Organize now', 'अभी व्यवस्थित करें', 'ਹੁਣੇ ਸੰਭਾਲੋ')
    'tray.undo' = @('Undo last organize', 'पिछला वापस करें', 'ਪਿਛਲਾ ਵਾਪਸ ਕਰੋ')
    'tray.pause' = @('Pause automatic tidying', 'अपने-आप व्यवस्थित करना रोकें', 'ਆਪਣੇ-ਆਪ ਸੰਭਾਲਣਾ ਰੋਕੋ')
    'tray.resume' = @('Resume automatic tidying', 'अपने-आप व्यवस्थित करना फिर शुरू करें', 'ਆਪਣੇ-ਆਪ ਸੰਭਾਲਣਾ ਫਿਰ ਚਾਲੂ ਕਰੋ')
    'tray.exit' = @('Exit DeskOrg', 'DeskOrg बंद करें', 'DeskOrg ਬੰਦ ਕਰੋ')
    'run.none' = @('Nothing needed moving. {0} file(s) were left where they are.', 'कुछ भी हिलाने की ज़रूरत नहीं थी। {0} फ़ाइलें वहीं रहीं।', 'ਕੁਝ ਵੀ ਹਿਲਾਉਣ ਦੀ ਲੋੜ ਨਹੀਂ ਸੀ। {0} ਫ਼ਾਈਲਾਂ ਉਥੇ ਹੀ ਰਹੀਆਂ।')
    'run.done' = @('{0} file(s) tidied. {1} left where they are.', '{0} फ़ाइलें व्यवस्थित हुईं। {1} वहीं रहीं।', '{0} ਫ਼ਾਈਲਾਂ ਸੰਭਾਲੀਆਂ ਗਈਆਂ। {1} ਉਥੇ ਹੀ ਰਹੀਆਂ।')
    'run.undohint' = @('Changed your mind? Use Undo last organize.', 'मन बदल गया? "पिछला व्यवस्थित करना वापस करें" दबाएँ।', 'ਮਨ ਬਦਲ ਗਿਆ? "ਪਿਛਲਾ ਸੰਭਾਲਣਾ ਵਾਪਸ ਕਰੋ" ਦਬਾਓ।')
    'run.undone' = @('{0} file(s) put back.', '{0} फ़ाइलें वापस रखी गईं।', '{0} ਫ਼ਾਈਲਾਂ ਵਾਪਸ ਰੱਖੀਆਂ ਗਈਆਂ।')
    'run.nothing' = @('There is nothing to undo.', 'वापस करने के लिए कुछ नहीं है।', 'ਵਾਪਸ ਕਰਨ ਲਈ ਕੁਝ ਨਹੀਂ ਹੈ।')
    'undo.ask' = @("Put back the files moved by the last organize?`n`nThey go back to the folder they came from.", "पिछली बार हटाई गई फ़ाइलें वापस रखें?`n`nवे उसी फ़ोल्डर में लौटेंगी जहाँ से आई थीं।", "ਪਿਛਲੀ ਵਾਰ ਹਟਾਈਆਂ ਫ਼ਾਈਲਾਂ ਵਾਪਸ ਰੱਖੀਆਂ ਜਾਣ?`n`nਉਹ ਉਸੇ ਫ਼ੋਲਡਰ ਵਿੱਚ ਮੁੜਨਗੀਆਂ ਜਿੱਥੋਂ ਆਈਆਂ ਸਨ।")
    'prog.Checking' = @('Checking', 'जाँच', 'ਜਾਂਚ')
    'prog.Moving' = @('Organizing', 'व्यवस्थित हो रहा है', 'ਸੰਭਾਲਿਆ ਜਾ ਰਿਹਾ ਹੈ')
    'prog.Comparing' = @('Comparing', 'तुलना', 'ਤੁਲਨਾ')
    'hist.title' = @('Recent tidy-ups', 'हाल की व्यवस्थाएँ', 'ਹਾਲੀਆ ਸੰਭਾਲਾਂ')
    'hist.desc' = @('Every time DeskOrg tidies, it is listed here. Open one to see each file and why it moved.', 'हर बार DeskOrg के व्यवस्थित करने पर यहाँ सूची बनती है। खोलकर देखें हर फ़ाइल क्यों हिली।', 'ਹਰ ਵਾਰ DeskOrg ਸੰਭਾਲਦਾ ਹੈ ਤਾਂ ਇੱਥੇ ਸੂਚੀ ਬਣਦੀ ਹੈ। ਖੋਲ੍ਹ ਕੇ ਵੇਖੋ ਹਰ ਫ਼ਾਈਲ ਕਿਉਂ ਹਿੱਲੀ।')
    'hist.empty' = @("Nothing has been tidied yet.`nPress Preview first to see what DeskOrg would do. Your files never move until you say so.", "अभी तक कुछ व्यवस्थित नहीं हुआ।`nDeskOrg क्या करेगा यह देखने के लिए पहले पूर्वावलोकन दबाएँ। आपके कहे बिना फ़ाइलें नहीं हिलतीं।", "ਹੁਣ ਤੱਕ ਕੁਝ ਨਹੀਂ ਸੰਭਾਲਿਆ ਗਿਆ।`nDeskOrg ਕੀ ਕਰੇਗਾ ਇਹ ਵੇਖਣ ਲਈ ਪਹਿਲਾਂ ਝਲਕ ਦਬਾਓ। ਤੁਹਾਡੇ ਕਹੇ ਬਿਨਾਂ ਫ਼ਾਈਲਾਂ ਨਹੀਂ ਹਿੱਲਦੀਆਂ।")
    'hist.details' = @('Details', 'ब्योरा', 'ਵੇਰਵਾ')
    'hist.undo' = @('Undo', 'वापस', 'ਵਾਪਸ')
    'hist.putback' = @('Put back', 'वापस रखें', 'ਵਾਪਸ ਰੱਖੋ')
    'hist.undone' = @('undone', 'वापस किया गया', 'ਵਾਪਸ ਕੀਤਾ')
    'hist.auto' = @('automatic', 'अपने-आप', 'ਆਪਣੇ-ਆਪ')
    'hist.files' = @('{0} file(s) tidied', '{0} फ़ाइलें व्यवस्थित', '{0} ਫ਼ਾਈਲਾਂ ਸੰਭਾਲੀਆਂ')
    'hist.whatsnew' = @("What's new", 'नया क्या है', 'ਨਵਾਂ ਕੀ ਹੈ')
    'set.lang' = @('Language', 'भाषा', 'ਭਾਸ਼ਾ')
    'set.lang.d' = @('Choose the language of the DeskOrg window. Hindi and Punjabi cover the main screens.', 'DeskOrg विंडो की भाषा चुनें। हिंदी और पंजाबी मुख्य स्क्रीन को कवर करती हैं।', 'DeskOrg ਵਿੰਡੋ ਦੀ ਭਾਸ਼ਾ ਚੁਣੋ। ਹਿੰਦੀ ਅਤੇ ਪੰਜਾਬੀ ਮੁੱਖ ਸਕਰੀਨਾਂ ਨੂੰ ਕਵਰ ਕਰਦੀਆਂ ਹਨ।')
    'set.look' = @('Appearance', 'रूप-रंग', 'ਦਿੱਖ')
    'set.look.d' = @('Make the text bigger or easier to read. Contrast applies fully after you restart DeskOrg.', 'लिखावट बड़ी या पढ़ने में आसान करें। कंट्रास्ट पूरी तरह DeskOrg दोबारा चालू करने पर लागू होता है।', 'ਲਿਖਤ ਵੱਡੀ ਜਾਂ ਪੜ੍ਹਨ ਵਿੱਚ ਸੌਖੀ ਕਰੋ। ਕੰਟ੍ਰਾਸਟ ਪੂਰੀ ਤਰ੍ਹਾਂ DeskOrg ਦੁਬਾਰਾ ਚਾਲੂ ਕਰਨ ਤੇ ਲਾਗੂ ਹੁੰਦਾ ਹੈ।')
    'set.size' = @('Text size', 'लिखावट का आकार', 'ਲਿਖਤ ਦਾ ਆਕਾਰ')
    'set.contrast' = @('High contrast text', 'ज़्यादा कंट्रास्ट वाली लिखावट', 'ਵੱਧ ਕੰਟ੍ਰਾਸਟ ਵਾਲੀ ਲਿਖਤ')
    'priv.title' = @('Private by design', 'डिज़ाइन से ही निजी', 'ਡਿਜ਼ਾਈਨ ਤੋਂ ਹੀ ਨਿੱਜੀ')
    'priv.text' = @('DeskOrg works only on this PC. It never uploads your files or their names. The only thing it asks the internet is whether a newer version exists.', 'DeskOrg केवल इसी पीसी पर काम करता है। यह आपकी फ़ाइलें या उनके नाम कभी अपलोड नहीं करता। यह इंटरनेट से केवल इतना पूछता है कि नया संस्करण है या नहीं।', 'DeskOrg ਸਿਰਫ਼ ਇਸੇ ਪੀਸੀ ਤੇ ਕੰਮ ਕਰਦਾ ਹੈ। ਇਹ ਤੁਹਾਡੀਆਂ ਫ਼ਾਈਲਾਂ ਜਾਂ ਉਨ੍ਹਾਂ ਦੇ ਨਾਂ ਕਦੇ ਅਪਲੋਡ ਨਹੀਂ ਕਰਦਾ। ਇਹ ਇੰਟਰਨੈੱਟ ਤੋਂ ਸਿਰਫ਼ ਇਹ ਪੁੱਛਦਾ ਹੈ ਕਿ ਨਵਾਂ ਵਰਜਨ ਹੈ ਜਾਂ ਨਹੀਂ।')
    'first.title' = @('Welcome to DeskOrg', 'DeskOrg में आपका स्वागत है', 'DeskOrg ਵਿੱਚ ਜੀ ਆਇਆਂ ਨੂੰ')
    'first.text' = @("DeskOrg keeps your folders tidy. Nothing moves until you press a button, and every tidy-up can be undone.`n`nWhich folders should it look after?", "DeskOrg आपके फ़ोल्डर व्यवस्थित रखता है। जब तक आप बटन नहीं दबाते कुछ नहीं हिलता, और हर व्यवस्था वापस की जा सकती है।`n`nयह कौन-से फ़ोल्डर सँभाले?", "DeskOrg ਤੁਹਾਡੇ ਫ਼ੋਲਡਰ ਸੰਭਾਲ ਕੇ ਰੱਖਦਾ ਹੈ। ਜਦੋਂ ਤੱਕ ਤੁਸੀਂ ਬਟਨ ਨਹੀਂ ਦਬਾਉਂਦੇ ਕੁਝ ਨਹੀਂ ਹਿੱਲਦਾ, ਅਤੇ ਹਰ ਸੰਭਾਲ ਵਾਪਸ ਹੋ ਸਕਦੀ ਹੈ।`n`nਇਹ ਕਿਹੜੇ ਫ਼ੋਲਡਰ ਸੰਭਾਲੇ?")
    'first.desktop' = @('My Desktop', 'मेरा डेस्कटॉप', 'ਮੇਰਾ ਡੈਸਕਟਾਪ')
    'first.downloads' = @('My Downloads folder too', 'मेरा डाउनलोड फ़ोल्डर भी', 'ਮੇਰਾ ਡਾਊਨਲੋਡ ਫ਼ੋਲਡਰ ਵੀ')
    'first.lang' = @('Language', 'भाषा', 'ਭਾਸ਼ਾ')
    'first.preview' = @('Preview what would move', 'देखें क्या हिलेगा', 'ਵੇਖੋ ਕੀ ਹਿੱਲੇਗਾ')
    'first.skip' = @('Start with the defaults', 'डिफ़ॉल्ट से शुरू करें', 'ਡਿਫ਼ਾਲਟ ਨਾਲ ਸ਼ੁਰੂ ਕਰੋ')
}

function T {
    param([string]$Key)
    $i = switch ($script:Lang) { 'hi' { 1 } 'pa' { 2 } default { 0 } }
    $row = $script:Str[$Key]
    if ($null -eq $row) { return $Key }
    $v = $row[$i]
    if ([string]::IsNullOrEmpty($v)) { $v = $row[0] }
    return $v
}

# ---------------- WHAT'S NEW ----------------

$script:Changes = @(
    @{ Version = '1.2.0'; Items = @(
        'First-run welcome: choose Desktop and/or Downloads and see a preview before anything moves.',
        'History page: every tidy-up listed, with Undo for a whole run or for one single file, and the reason each file moved.',
        'Rules by file name (for example Screenshot*), by size, and for files not touched for many days.',
        'Quiet hours: no automatic tidying between the times you choose.',
        'Downloads and other folders are now watched live, each with its own options.',
        'Find duplicate files and send the extra copies to the Recycle Bin.',
        'Drag files onto the rules editor to add their types. Import and export your rules.',
        'Hindi and Punjabi screens, bigger text, high contrast, keyboard shortcuts (press F1).',
        'Progress while tidying, friendlier dark message boxes, plain-language menu names.') },
    @{ Version = '1.1.0'; Items = @(
        'Preview, Undo, rules editor, Downloads folder, tray icon, update check, no .exe.') }
)

# ---------------- ONLY ONE CONTROL CENTER ----------------

function Enter-SingleInstance {
    # Returns $false (after asking the running one to come forward) when DeskOrg is already open.
    $created = $false
    $script:InstanceMutex = New-Object System.Threading.Mutex($true, 'Local\DeskOrgControlCenter', [ref]$created)
    $script:ShowEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\DeskOrgShowWindow')
    if (-not $created) {
        [void]$script:ShowEvent.Set()
        return $false
    }
    return $true
}

# ---------------- APPEARANCE ----------------

function Apply-Appearance {
    # Called once, right after the colour table exists (before the window is built).
    if ($script:Settings.HighContrast) {
        $script:C.Muted = '#CDD5EE'
        $script:C.Border = '#3C4D70'
    }
}

function Set-TextScale {
    param([int]$Percent)
    Update-Setting 'TextScale' $Percent
    if ($script:Window -and $script:Window.Content) {
        $s = $Percent / 100.0
        $script:Window.Content.LayoutTransform = New-Object System.Windows.Media.ScaleTransform($s, $s)
    }
}

# ---------------- DARK DIALOGS ----------------

function Show-Dialog {
    # A message box in DeskOrg's own look. Returns the text of the button pressed.
    param([string]$Message, [string]$Title = 'DeskOrg', [string[]]$Buttons = @(), [switch]$Warn)
    if ($Buttons.Count -eq 0) { $Buttons = @((T 'ok')) }
    $w = New-Object System.Windows.Window
    $w.Title = $Title
    $w.Width = 480
    $w.SizeToContent = 'Height'
    $w.ResizeMode = 'NoResize'
    $w.ShowInTaskbar = $false
    $w.Background = $script:C.Panel
    $w.Foreground = $script:C.Text
    $w.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
    if ($script:Window -and $script:Window.IsVisible) { $w.Owner = $script:Window; $w.WindowStartupLocation = 'CenterOwner' }
    else { $w.WindowStartupLocation = 'CenterScreen' }

    $outer = New-Object System.Windows.Controls.Border
    $outer.BorderThickness = '1'
    $outer.BorderBrush = if ($Warn) { $script:C.Amber } else { $script:C.Teal }
    $outer.Padding = '22'
    $s = New-Stack
    $head = New-Text $Title 15 ($(if ($Warn) { $script:C.Amber } else { $script:C.Teal })) -Bold
    $head.Margin = '0,0,0,10'
    [void]$s.Children.Add($head)
    $msg = New-Text $Message 13 $script:C.Text -Wrap
    $msg.Margin = '0,0,0,20'
    [void]$s.Children.Add($msg)
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.HorizontalAlignment = 'Right'
    # Note: code inside .GetNewClosure() blocks cannot see $script: variables, so shared
    # state goes in a local hashtable that the closures capture.
    $state = @{ Result = $Buttons[$Buttons.Count - 1] }
    foreach ($label in $Buttons) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $label
        $b.Padding = '20,8'
        $b.Margin = '10,0,0,0'
        $b.MinWidth = 84
        Set-DeskOrgButtonStyle -Button $b -NormalBackground $script:C.Panel2 -NormalBorder $script:C.Border
        $text = $label
        $b.Add_Click({ $state.Result = $text; $w.Close() }.GetNewClosure())
        [void]$row.Children.Add($b)
    }
    [void]$s.Children.Add($row)
    $outer.Child = $s
    $w.Content = $outer
    [void]$w.ShowDialog()
    return $state.Result
}

function Confirm-Dialog {
    param([string]$Message, [string]$Title = 'DeskOrg')
    $yes = T 'yes'
    return ((Show-Dialog -Message $Message -Title $Title -Buttons @($yes, (T 'no'))) -eq $yes)
}

# ---------------- RUN THE ORGANIZER IN THE BACKGROUND ----------------

function Update-ProgressDisplay {
    $p = Read-JsonSafe $script:ProgressFile
    if ($p -and [int]$p.Total -gt 0) {
        $pct = [int](100 * [int]$p.Done / [int]$p.Total)
        Set-Status ("{0}: {1} / {2} ({3}%)  {4}" -f (T ('prog.' + [string]$p.Phase)), $p.Done, $p.Total, $pct, $p.Current)
        if ($script:ProgressBar) { $script:ProgressBar.Visibility = 'Visible'; $script:ProgressBar.Value = $pct }
    }
}

function Start-OrganizerJob {
    param([string[]]$Switches = @(), [scriptblock]$OnDone)

    if ($script:JobProc -and -not $script:JobProc.HasExited) {
        [void](Show-Dialog 'DeskOrg is already working. Please wait a moment.')
        return
    }
    foreach ($f in @($script:PreviewFile, $script:LastRunFile, $script:ProgressFile)) {
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    }

    $argList = @(
        '--headless', 'powershell.exe', '-NoLogo', '-NoProfile',
        '-ExecutionPolicy', 'AllSigned',
        '-File', "`"$script:OrganizerScript`""
    ) + $Switches

    $script:JobProc = Start-Process -FilePath 'conhost.exe' -ArgumentList $argList `
        -WorkingDirectory $AppFolder -PassThru -ErrorAction Stop
    $script:JobDone = $OnDone

    if ($null -eq $script:JobTimer) {
        $script:JobTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:JobTimer.Interval = [TimeSpan]::FromMilliseconds(400)
        $script:JobTimer.Add_Tick({
            if ($script:JobProc -and $script:JobProc.HasExited) {
                $script:JobTimer.Stop()
                if ($script:ProgressBar) { $script:ProgressBar.Visibility = 'Collapsed' }
                $cb = $script:JobDone
                $script:JobDone = $null
                if ($cb) { & $cb }
            }
            else { Update-ProgressDisplay }
        })
    }
    $script:JobTimer.Start()
}

function Show-RunSummary {
    # Tells the user in plain words what the last run did.
    $r = Read-JsonSafe $script:LastRunFile
    if ($null -eq $r) {
        [void](Show-Dialog 'DeskOrg finished, but no summary was written. Open the log for details.' 'DeskOrg' -Warn)
        return
    }
    switch ([string]$r.Action) {
        'organize' {
            if ([int]$r.Moved -eq 0) { $msg = (T 'run.none') -f $r.Skipped }
            else {
                $msg = (T 'run.done') -f $r.Moved, $r.Skipped
                if ([int]$r.Failed -gt 0) { $msg += " ($($r.Failed) could not be moved - see the log)" }
                $msg += "`n`n" + (T 'run.undohint')
            }
            [void](Show-Dialog $msg 'DeskOrg')
            Set-Status ((T 'run.done') -f $r.Moved, $r.Skipped)
        }
        'undo' {
            if ($r.Nothing) { [void](Show-Dialog (T 'run.nothing') 'DeskOrg'); return }
            $msg = (T 'run.undone') -f $r.Restored
            if ([int]$r.Missing -gt 0) { $msg += " $($r.Missing) could not be found (moved or deleted since)." }
            if ([int]$r.Failed -gt 0) { $msg += " $($r.Failed) failed (see the log)." }
            [void](Show-Dialog $msg 'DeskOrg')
            Set-Status ((T 'run.undone') -f $r.Restored)
        }
        'error' {
            [void](Show-Dialog ("DeskOrg could not finish:`n" + $r.Error) 'DeskOrg' -Warn)
        }
        default { [void](Show-Dialog 'Done.' 'DeskOrg') }
    }
    if ($script:CurrentPage -eq 'Activity') { Navigate-To 'Activity' }
}

function Invoke-OrganizeNow {
    try {
        Set-Status '...'
        Start-OrganizerJob -Switches @() -OnDone { Show-RunSummary }
    }
    catch {
        [void](Show-Dialog ("Unable to start the organizer.`n" + $_.Exception.Message) 'DeskOrg' -Warn)
    }
}

function Invoke-UndoLast {
    if (-not (Confirm-Dialog (T 'undo.ask'))) { return }
    try {
        Set-Status '...'
        Start-OrganizerJob -Switches @('-Undo') -OnDone { Show-RunSummary }
    }
    catch {
        [void](Show-Dialog ("Unable to start the undo.`n" + $_.Exception.Message) 'DeskOrg' -Warn)
    }
}

function New-DarkWindow {
    param([string]$Title, [int]$Width = 760, [int]$Height = 560)
    $w = New-Object System.Windows.Window
    $w.Title = $Title
    $w.Width = $Width; $w.Height = $Height
    $w.MinWidth = 520; $w.MinHeight = 320
    $w.Background = $script:C.Background
    $w.Foreground = $script:C.Text
    $w.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
    if ($script:Window -and $script:Window.IsVisible) { $w.Owner = $script:Window; $w.WindowStartupLocation = 'CenterOwner' }
    else { $w.WindowStartupLocation = 'CenterScreen' }
    return $w
}

function New-SmallButton {
    param([string]$Text, [scriptblock]$OnClick, [switch]$Primary)
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $Text
    $b.Padding = '14,6'
    $b.Margin = '8,0,0,0'
    Set-DeskOrgButtonStyle -Button $b -NormalBackground $(if ($Primary) { '#10332E' } else { $script:C.Panel2 }) -NormalBorder $(if ($Primary) { $script:C.Teal } else { $script:C.Border })
    if ($OnClick) { $b.Add_Click($OnClick) }
    return $b
}

function Show-PreviewWindow {
    try {
        Set-Status '...'
        Start-OrganizerJob -Switches @('-Preview') -OnDone {
            $p = Read-JsonSafe $script:PreviewFile
            if ($null -eq $p) {
                [void](Show-Dialog 'The preview could not be made. Open the log on the History page for details.' 'DeskOrg' -Warn)
                return
            }
            $items = @($p.Items)
            if ($items.Count -eq 0) {
                [void](Show-Dialog ("Your folders are already tidy. $($p.Skipped) file(s) are left alone on purpose (programs, shortcuts, new files and anything you protected).") 'DeskOrg')
                return
            }

            $w = New-DarkWindow 'DeskOrg | Preview' 820 560
            $g = New-Object System.Windows.Controls.Grid
            $g.Margin = '18'
            foreach ($h in @('Auto', '*', 'Auto')) {
                $rd = New-Object System.Windows.Controls.RowDefinition
                $rd.Height = $h
                [void]$g.RowDefinitions.Add($rd)
            }
            $head = New-Text "$($items.Count) file(s) would move; $($p.Skipped) left alone. Nothing has been moved yet." 14 $script:C.Text -Bold -Wrap
            $head.Margin = '0,0,0,10'
            [System.Windows.Controls.Grid]::SetRow($head, 0)
            [void]$g.Children.Add($head)

            $box = New-Object System.Windows.Controls.TextBox
            $box.IsReadOnly = $true
            $box.Background = $script:C.Panel
            $box.Foreground = $script:C.Text
            $box.BorderBrush = $script:C.Border
            $box.Padding = '10'
            $box.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
            $box.FontSize = 12
            $box.VerticalScrollBarVisibility = 'Auto'
            $box.HorizontalScrollBarVisibility = 'Auto'
            $lines = foreach ($i in $items) {
                $dir = Split-Path -Parent ([string]$i.From)
                $rel = ([string]$i.To)
                if ($rel.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($dir.Length).TrimStart('\') }
                $note = if ($i.Renamed) { ' (renamed: same name already there)' } else { '' }
                "{0}   ->   {1}{2}`r`n      why: {3}" -f ([IO.Path]::GetFileName([string]$i.From)), $rel, $note, $i.Why
            }
            $box.Text = ($lines -join "`r`n")
            [System.Windows.Controls.Grid]::SetRow($box, 1)
            [void]$g.Children.Add($box)

            $bar = New-Object System.Windows.Controls.StackPanel
            $bar.Orientation = 'Horizontal'
            $bar.HorizontalAlignment = 'Right'
            $bar.Margin = '0,12,0,0'
            $go = @{ Now = $false }
            [void]$bar.Children.Add((New-SmallButton (T 'close') { $w.Close() }.GetNewClosure()))
            [void]$bar.Children.Add((New-SmallButton (T 'org.now') { $go.Now = $true; $w.Close() }.GetNewClosure() -Primary))
            [System.Windows.Controls.Grid]::SetRow($bar, 2)
            [void]$g.Children.Add($bar)

            $w.Content = $g
            [void]$w.ShowDialog()
            if ($go.Now) { Invoke-OrganizeNow }
        }
    }
    catch {
        [void](Show-Dialog ("Unable to start the preview.`n" + $_.Exception.Message) 'DeskOrg' -Warn)
    }
}

# ---------------- HISTORY ----------------

function Get-RunHistory {
    $out = @()
    if (Test-Path -LiteralPath $script:RunsFolder) {
        $files = Get-ChildItem -LiteralPath $script:RunsFolder -Filter 'run-*.json' |
            Sort-Object Name -Descending | Select-Object -First 30
        foreach ($f in $files) {
            $d = Read-JsonSafe $f.FullName
            if (-not $d) { continue }
            $out += [pscustomobject]@{
                Name = $f.Name; Time = [datetime]$d.Time; Auto = [bool]$d.Auto
                Count = @($d.Moves).Count; Undone = ($f.Name -like '*.undone.json'); Data = $d
            }
        }
    }
    return $out
}

function Format-RunTime {
    param([datetime]$When)
    $days = ((Get-Date).Date - $When.Date).Days
    $hm = $When.ToString('HH:mm')
    if ($days -eq 0) { return "Today $hm" }
    if ($days -eq 1) { return "Yesterday $hm" }
    return $When.ToString('dd MMM') + " $hm"
}

function Add-HistoryCard {
    param($Root)
    $card = New-Card (T 'hist.title') (T 'hist.desc') $script:C.Blue
    $runs = @(Get-RunHistory)

    if ($runs.Count -eq 0) {
        $e = New-Text (T 'hist.empty') 13 $script:C.Muted -Wrap
        $e.Margin = '0,6,0,8'
        [void]$card.Body.Children.Add($e)
        Add-Action $card (T 'org.preview') (T 'org.preview.d') { Show-PreviewWindow } $script:C.Blue -Primary
    }
    else {
        foreach ($run in ($runs | Select-Object -First 12)) {
            $rowBorder = New-Object System.Windows.Controls.Border
            $rowBorder.Background = $script:C.Panel2
            $rowBorder.BorderBrush = $script:C.Border
            $rowBorder.BorderThickness = '1'
            $rowBorder.CornerRadius = '10'
            $rowBorder.Padding = '12,9'
            $rowBorder.Margin = '0,0,0,8'
            $dock = New-Object System.Windows.Controls.DockPanel

            $name = $run.Name
            $btns = New-Object System.Windows.Controls.StackPanel
            $btns.Orientation = 'Horizontal'
            [System.Windows.Controls.DockPanel]::SetDock($btns, 'Right')
            [void]$btns.Children.Add((New-SmallButton (T 'hist.details') { Show-RunDetails $name }.GetNewClosure()))
            if (-not $run.Undone) {
                [void]$btns.Children.Add((New-SmallButton (T 'hist.undo') {
                    if (Confirm-Dialog (T 'undo.ask')) {
                        Start-OrganizerJob -Switches @('-Undo', '-Run', $name) -OnDone { Show-RunSummary }
                    }
                }.GetNewClosure()))
            }
            [void]$dock.Children.Add($btns)

            $text = New-Stack
            $line = (Format-RunTime $run.Time) + '  -  ' + ((T 'hist.files') -f $run.Count)
            if ($run.Auto) { $line += '  ·  ' + (T 'hist.auto') }
            if ($run.Undone) { $line += '  ·  ' + (T 'hist.undone') }
            [void]$text.Children.Add((New-Text $line 12 $(if ($run.Undone) { $script:C.Muted } else { $script:C.Text }) -Bold))
            $dest = @(@($run.Data.Moves) | ForEach-Object { Split-Path (Split-Path ([string]$_.To) -Parent) -Leaf } | Select-Object -Unique | Select-Object -First 4)
            $sub = New-Text ($dest -join ', ') 10 $script:C.Muted -Wrap
            $sub.Margin = '0,2,0,0'
            [void]$text.Children.Add($sub)
            [void]$dock.Children.Add($text)

            $rowBorder.Child = $dock
            [void]$card.Body.Children.Add($rowBorder)
        }
    }
    [void]$Root.Children.Add($card.Border)
}

function Show-RunDetails {
    param([string]$Name)
    # Code inside .GetNewClosure() cannot see $script: variables: colours go in $C, state in $st.
    $C = $script:C
    $st = @{ Path = (Join-Path $script:RunsFolder $Name) }
    $w = New-DarkWindow 'DeskOrg | Details' 820 560
    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $list = New-Stack
    $list.Margin = '18'
    $scroll.Content = $list
    $w.Content = $scroll

    $holder = @{ Fill = $null }
    $holder.Fill = {
        $list.Children.Clear()
        if (-not (Test-Path -LiteralPath $st.Path)) {
            $alt = $st.Path -replace '\.json$', '.undone.json'
            if (Test-Path -LiteralPath $alt) { $st.Path = $alt } else { $w.Close(); return }
        }
        $undone = ($st.Path -like '*.undone.json')
        $d = Read-JsonSafe $st.Path
        $moves = @($d.Moves)
        $h = New-Text ("{0}  -  {1}" -f (Format-RunTime ([datetime]$d.Time)), ((T 'hist.files') -f $moves.Count)) 15 $C.Teal -Bold
        $h.Margin = '0,0,0,12'
        [void]$list.Children.Add($h)
        foreach ($m in $moves) {
            $b = New-Object System.Windows.Controls.Border
            $b.Background = $C.Panel
            $b.BorderBrush = $C.Border
            $b.BorderThickness = '1'
            $b.CornerRadius = '10'
            $b.Padding = '12,9'
            $b.Margin = '0,0,0,8'
            $dock = New-Object System.Windows.Controls.DockPanel
            $to = [string]$m.To
            if (-not $undone) {
                # A closure made inside another closure only sees variables of its own
                # immediate scope, so everything the button needs is copied to locals here.
                $runName = [IO.Path]::GetFileName($st.Path)
                $refill = $holder.Fill
                $btn = New-SmallButton (T 'hist.putback') {
                    Start-OrganizerJob -Switches @('-Undo', '-Run', $runName, '-File', $to) -OnDone {
                        Show-RunSummary
                        & $refill
                    }
                }.GetNewClosure()
                [System.Windows.Controls.DockPanel]::SetDock($btn, 'Right')
                [void]$dock.Children.Add($btn)
            }
            $t = New-Stack
            [void]$t.Children.Add((New-Text ([IO.Path]::GetFileName($to)) 12 $C.Text -Bold))
            $fromDir = Split-Path -Parent ([string]$m.From)
            $toDir = Split-Path -Parent $to
            $s1 = New-Text ("$fromDir  ->  $toDir") 10 $C.Muted -Wrap
            $s1.Margin = '0,2,0,0'
            [void]$t.Children.Add($s1)
            if ($m.Why) { [void]$t.Children.Add((New-Text ("Why: " + $m.Why) 10 $C.Teal -Wrap)) }
            [void]$dock.Children.Add($t)
            $b.Child = $dock
            [void]$list.Children.Add($b)
        }
    }.GetNewClosure()
    & $holder.Fill
    [void]$w.ShowDialog()
    if ($script:CurrentPage -eq 'Activity') { Navigate-To 'Activity' }
}

# ---------------- DUPLICATE FINDER ----------------

function Show-DuplicateFinder {
    try {
        Set-Status '...'
        Start-OrganizerJob -Switches @('-FindDuplicates') -OnDone {
            $d = Read-JsonSafe $script:DupFile
            if ($null -eq $d) {
                [void](Show-Dialog 'The search could not finish. Open the log on the History page for details.' 'DeskOrg' -Warn)
                return
            }
            $groups = @($d.Groups)
            if ($groups.Count -eq 0) {
                [void](Show-Dialog ("No identical files found among $($d.Scanned) file(s). Nice and clean.") 'DeskOrg')
                return
            }
            $C = $script:C
            $w = New-DarkWindow 'DeskOrg | Duplicate files' 860 620
            $g = New-Object System.Windows.Controls.Grid
            $g.Margin = '18'
            foreach ($h in @('Auto', '*', 'Auto')) {
                $rd = New-Object System.Windows.Controls.RowDefinition
                $rd.Height = $h
                [void]$g.RowDefinitions.Add($rd)
            }
            $head = New-Text ("$($groups.Count) group(s) of identical files. The oldest copy of each is kept; the ticked extras go to the Recycle Bin when you press the button.") 13 $C.Text -Wrap
            $head.Margin = '0,0,0,10'
            [System.Windows.Controls.Grid]::SetRow($head, 0)
            [void]$g.Children.Add($head)

            $scroll = New-Object System.Windows.Controls.ScrollViewer
            $scroll.VerticalScrollBarVisibility = 'Auto'
            $list = New-Stack
            $scroll.Content = $list
            [System.Windows.Controls.Grid]::SetRow($scroll, 1)
            [void]$g.Children.Add($scroll)

            $st = @{ Boxes = New-Object System.Collections.ArrayList; Summary = (New-Text '' 12 $C.Muted) }
            $holder = @{ Refresh = $null }
            $holder.Refresh = {
                $n = 0; $bytes = 0
                foreach ($x in $st.Boxes) { if ($x.Box.IsChecked) { $n++; $bytes += $x.Size } }
                $st.Summary.Text = ("{0} file(s) ticked, {1:N1} MB to free" -f $n, ($bytes / 1MB))
            }.GetNewClosure()

            $shown = 0
            foreach ($grp in ($groups | Select-Object -First 200)) {
                $shown++
                $gb = New-Object System.Windows.Controls.Border
                $gb.Background = $C.Panel
                $gb.BorderBrush = $C.Border
                $gb.BorderThickness = '1'
                $gb.CornerRadius = '10'
                $gb.Padding = '12,9'
                $gb.Margin = '0,0,0,8'
                $gs = New-Stack
                $files = @($grp.Files)
                $sizeText = if ($grp.Size -ge 1MB) { '{0:N1} MB' -f ($grp.Size / 1MB) } else { '{0:N0} KB' -f ([Math]::Max(1, $grp.Size / 1KB)) }
                $gh = New-Text ("{0} copies, {1} each" -f $files.Count, $sizeText) 12 $C.Teal -Bold
                $gh.Margin = '0,0,0,4'
                [void]$gs.Children.Add($gh)
                $groupBoxes = New-Object System.Collections.ArrayList
                $first = $true
                foreach ($f in $files) {
                    $cb = New-Object System.Windows.Controls.CheckBox
                    $cb.Foreground = $C.Text
                    $cb.Margin = '0,2,0,2'
                    $cb.Content = ("{0}   ({1})" -f $f.Path, ([datetime]$f.Modified).ToString('dd MMM yyyy'))
                    $cb.IsChecked = (-not $first)
                    $first = $false
                    $entry = @{ Box = $cb; Path = [string]$f.Path; Size = [long]$grp.Size }
                    [void]$groupBoxes.Add($entry)
                    [void]$st.Boxes.Add($entry)
                    [void]$gs.Children.Add($cb)
                }
                foreach ($entry in $groupBoxes) {
                    $mine = $entry.Box
                    $mates = $groupBoxes
                    $mine.Add_Click({
                        # Never let every copy of a file be ticked.
                        $unticked = 0
                        foreach ($mate in $mates) { if (-not $mate.Box.IsChecked) { $unticked++ } }
                        if ($unticked -eq 0) { $mine.IsChecked = $false }
                        & $holder.Refresh
                    }.GetNewClosure())
                }
                $gb.Child = $gs
                [void]$list.Children.Add($gb)
            }
            if ($groups.Count -gt $shown) {
                [void]$list.Children.Add((New-Text "...and $($groups.Count - $shown) more group(s). Run this again after cleaning these." 11 $C.Muted -Wrap))
            }
            & $holder.Refresh

            $bar = New-Object System.Windows.Controls.DockPanel
            $bar.Margin = '0,12,0,0'
            $btns = New-Object System.Windows.Controls.StackPanel
            $btns.Orientation = 'Horizontal'
            [System.Windows.Controls.DockPanel]::SetDock($btns, 'Right')
            [void]$btns.Children.Add((New-SmallButton (T 'close') { $w.Close() }.GetNewClosure()))
            [void]$btns.Children.Add((New-SmallButton 'Move ticked files to the Recycle Bin' {
                $sel = @($st.Boxes | Where-Object { $_.Box.IsChecked })
                if ($sel.Count -eq 0) { [void](Show-Dialog 'Nothing is ticked.'); return }
                if (-not (Confirm-Dialog "Move $($sel.Count) file(s) to the Recycle Bin?`n`nYou can restore them from the Recycle Bin.")) { return }
                $ok = 0; $bad = 0
                foreach ($s in $sel) {
                    try {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($s.Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
                        $ok++; $s.Box.IsEnabled = $false; $s.Box.IsChecked = $false
                    } catch { $bad++ }
                }
                [void](Show-Dialog "$ok file(s) moved to the Recycle Bin. $bad could not be moved.")
                & $holder.Refresh
            }.GetNewClosure() -Primary))
            [void]$bar.Children.Add($btns)
            [void]$bar.Children.Add($st.Summary)
            [System.Windows.Controls.Grid]::SetRow($bar, 2)
            [void]$g.Children.Add($bar)

            $w.Content = $g
            [void]$w.ShowDialog()
        }
    }
    catch {
        [void](Show-Dialog ("Unable to start the search.`n" + $_.Exception.Message) 'DeskOrg' -Warn)
    }
}

# ---------------- RULES EDITOR ----------------

function Show-RulesEditor {
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DeskOrg | Rules" Width="800" Height="800" MinHeight="560"
        WindowStartupLocation="CenterOwner" Background="#F4F6FB">
  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <ScrollViewer VerticalScrollBarVisibility="Auto">
      <StackPanel Margin="0,0,10,0">
        <TextBlock Text="Rules" FontSize="22" FontWeight="Bold" Foreground="#1A2238"/>
        <TextBlock Text="Choose what DeskOrg tidies and where files go. Changes apply from the next run." Foreground="#55607A" TextWrapping="Wrap" Margin="0,2,0,14"/>

        <TextBlock Text="Main folder to tidy" FontWeight="SemiBold" Foreground="#1A2238"/>
        <TextBox x:Name="txtSource" Margin="0,4,0,2" Padding="6"/>
        <TextBlock Text="Type Desktop, Downloads, or a full folder path." Foreground="#6B7690" FontSize="11"/>

        <TextBlock Text="Other folders to tidy, each with its own options" FontWeight="SemiBold" Foreground="#1A2238" Margin="0,16,0,0"/>
        <TextBlock Text="Unknown files: Leave, or a folder name such as Other Files. Dates: None, Month or Year." Foreground="#6B7690" FontSize="11"/>
        <DataGrid x:Name="gridFolders" Height="110" Margin="0,6,0,0" AutoGenerateColumns="True" CanUserAddRows="True" CanUserDeleteRows="True" HeadersVisibility="Column"/>
        <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
          <Button x:Name="btnAddDownloads" Content="Add my Downloads" Padding="10,4" Margin="0,0,8,0"/>
          <Button x:Name="btnAddFolder" Content="Add a folder..." Padding="10,4"/>
        </StackPanel>

        <TextBlock Text="Files DeskOrg does not know" FontWeight="SemiBold" Foreground="#1A2238" Margin="0,16,0,0"/>
        <ComboBox x:Name="cmbUnknown" Margin="0,4,0,0" Padding="6">
          <ComboBoxItem Content="Move them into a folder called Other Files"/>
          <ComboBoxItem Content="Leave them where they are"/>
        </ComboBox>

        <TextBlock Text="Folders by date" FontWeight="SemiBold" Foreground="#1A2238" Margin="0,16,0,0"/>
        <ComboBox x:Name="cmbDated" Margin="0,4,0,0" Padding="6">
          <ComboBoxItem Content="No dates (Images)"/>
          <ComboBoxItem Content="By month (Images\2026-11)"/>
          <ComboBoxItem Content="By year (Images\2026)"/>
        </ComboBox>

        <TextBlock Text="If a file with the same name is already there" FontWeight="SemiBold" Foreground="#1A2238" Margin="0,16,0,0"/>
        <ComboBox x:Name="cmbDup" Margin="0,4,0,0" Padding="6">
          <ComboBoxItem Content="Keep both (the new one becomes name (1))"/>
          <ComboBoxItem Content="Leave the new file where it is"/>
        </ComboBox>

        <TextBlock Text="Do not touch files changed in the last (minutes)" FontWeight="SemiBold" Foreground="#1A2238" Margin="0,16,0,0"/>
        <TextBox x:Name="txtRecent" Width="80" HorizontalAlignment="Left" Margin="0,4,0,0" Padding="6"/>

        <TextBlock Text="Quiet hours (no automatic tidying)" FontWeight="SemiBold" Foreground="#1A2238" Margin="0,16,0,0"/>
        <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
          <CheckBox x:Name="chkQuiet" Content="Stay quiet from" VerticalAlignment="Center"/>
          <TextBox x:Name="txtQuietFrom" Width="64" Margin="8,0,0,0" Padding="4"/>
          <TextBlock Text="to" Margin="8,0,0,0" VerticalAlignment="Center"/>
          <TextBox x:Name="txtQuietTo" Width="64" Margin="8,0,0,0" Padding="4"/>
          <TextBlock Text="(24-hour, like 09:00 and 18:00)" Foreground="#6B7690" FontSize="11" Margin="8,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>

        <TextBlock Text="Old files" FontWeight="SemiBold" Foreground="#1A2238" Margin="0,16,0,0"/>
        <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
          <CheckBox x:Name="chkOld" Content="Move files not touched for" VerticalAlignment="Center"/>
          <TextBox x:Name="txtOldDays" Width="56" Margin="8,0,0,0" Padding="4"/>
          <TextBlock Text="days into the folder" Margin="8,0,0,0" VerticalAlignment="Center"/>
          <TextBox x:Name="txtOldFolder" Width="120" Margin="8,0,0,0" Padding="4"/>
        </StackPanel>

        <TextBlock Text="Never move these files (one name per line, * works: invoice-*.pdf)" FontWeight="SemiBold" Foreground="#1A2238" Margin="0,16,0,0"/>
        <TextBox x:Name="txtSkip" Height="64" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Margin="0,4,0,0" Padding="6"/>

        <TextBlock Text="Never move these file types (programs and scripts, comma separated)" FontWeight="SemiBold" Foreground="#1A2238" Margin="0,16,0,0"/>
        <TextBox x:Name="txtProt" Height="56" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Margin="0,4,0,0" Padding="6"/>

        <TextBlock Text="Rules by file name" FontWeight="SemiBold" Foreground="#1A2238" Margin="0,16,0,0"/>
        <TextBlock Text="Pattern: * means anything, for example Screenshot*. These win over file types." Foreground="#6B7690" FontSize="11"/>
        <DataGrid x:Name="gridNames" Height="110" Margin="0,6,0,0" AutoGenerateColumns="True" CanUserAddRows="True" CanUserDeleteRows="True" HeadersVisibility="Column"/>

        <TextBlock Text="Rules by size" FontWeight="SemiBold" Foreground="#1A2238" Margin="0,16,0,0"/>
        <TextBlock Text="Files bigger than the MB value go to the folder. Types (optional): .mp4, .mkv" Foreground="#6B7690" FontSize="11"/>
        <DataGrid x:Name="gridSizes" Height="100" Margin="0,6,0,0" AutoGenerateColumns="True" CanUserAddRows="True" CanUserDeleteRows="True" HeadersVisibility="Column"/>

        <TextBlock Text="Which folder each file type goes to" FontWeight="SemiBold" Foreground="#1A2238" Margin="0,16,0,0"/>
        <TextBlock x:Name="lblDrop" Text="Tip: drag files from Explorer onto this table to add their types. Select a row and press Delete to remove it." Foreground="#6B7690" FontSize="11" TextWrapping="Wrap"/>
        <DataGrid x:Name="grid" Height="240" Margin="0,6,0,0" AutoGenerateColumns="True" CanUserAddRows="True" CanUserDeleteRows="True" HeadersVisibility="Column" AllowDrop="True"/>
      </StackPanel>
    </ScrollViewer>
    <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="btnImport" Content="Import rules..." Width="120" Height="32" Margin="0,0,8,0"/>
      <Button x:Name="btnExport" Content="Export rules..." Width="120" Height="32" Margin="0,0,8,0"/>
      <Button x:Name="btnReset" Content="Reset to defaults" Width="130" Height="32" Margin="0,0,16,0"/>
      <Button x:Name="btnSave" Content="Save" Width="100" Height="32" Margin="0,0,10,0" IsDefault="True"/>
      <Button x:Name="btnCancel" Content="Cancel" Width="90" Height="32" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $w = [Windows.Markup.XamlReader]::Parse($xaml)
    if ($script:Window -and $script:Window.IsVisible) { $w.Owner = $script:Window }
    $c = @{}
    foreach ($n in 'txtSource','gridFolders','btnAddDownloads','btnAddFolder','cmbUnknown','cmbDated','cmbDup','txtRecent','chkQuiet','txtQuietFrom','txtQuietTo','chkOld','txtOldDays','txtOldFolder','txtSkip','txtProt','gridNames','gridSizes','lblDrop','grid','btnImport','btnExport','btnReset','btnSave','btnCancel') {
        $c[$n] = $w.FindName($n)
    }

    $dtExt = New-Object System.Data.DataTable
    [void]$dtExt.Columns.Add('Extension'); [void]$dtExt.Columns.Add('Folder')
    $dtFolders = New-Object System.Data.DataTable
    [void]$dtFolders.Columns.Add('Folder'); [void]$dtFolders.Columns.Add('Unknown files'); [void]$dtFolders.Columns.Add('Dates')
    $dtNames = New-Object System.Data.DataTable
    [void]$dtNames.Columns.Add('Pattern'); [void]$dtNames.Columns.Add('Folder')
    $dtSizes = New-Object System.Data.DataTable
    [void]$dtSizes.Columns.Add('Bigger than (MB)'); [void]$dtSizes.Columns.Add('Folder'); [void]$dtSizes.Columns.Add('Only these types (optional)')

    $oldExtra = @{}   # per-folder settings the editor does not show are kept when saving

    $load = {
        param($rulesPath)
        $r = Read-JsonSafe $rulesPath
        if ($null -eq $r -or -not $r.Extensions) { $r = Read-JsonSafe (Join-Path $AppFolder 'DeskOrgRules.json') }
        $c.txtSource.Text = if ($r.SourceFolder) { [string]$r.SourceFolder } else { 'Desktop' }
        $c.cmbUnknown.SelectedIndex = if ([string]$r.UnknownFileBehavior -eq 'Leave') { 1 } else { 0 }
        $c.cmbDated.SelectedIndex = switch ([string]$r.DatedFolders) { 'Month' { 1 } 'Year' { 2 } default { 0 } }
        $c.cmbDup.SelectedIndex = if ([string]$r.Duplicates -eq 'Skip') { 1 } else { 0 }
        $c.txtRecent.Text = if ($null -ne $r.SkipRecentMinutes) { [string]$r.SkipRecentMinutes } else { '1' }
        $c.txtSkip.Text = (@($r.SkipFiles | Where-Object { $_ }) -join "`r`n")
        $c.txtProt.Text = (@($r.ProtectedExtensions) -join ', ')

        $dtFolders.Rows.Clear(); $oldExtra.Clear()
        foreach ($e in @($r.ExtraFolders)) {
            if (-not $e -or -not $e.Path) { continue }
            $oldExtra[[string]$e.Path] = $e
            [void]$dtFolders.Rows.Add([string]$e.Path, $(if ($e.UnknownFileBehavior) { [string]$e.UnknownFileBehavior } else { 'Leave' }), $(if ($e.DatedFolders) { [string]$e.DatedFolders } else { 'None' }))
        }
        $dtNames.Rows.Clear()
        foreach ($n in @($r.NameRules)) { if ($n) { [void]$dtNames.Rows.Add([string]$n.Match, [string]$n.Folder) } }
        $dtSizes.Rows.Clear()
        foreach ($s in @($r.SizeRules)) { if ($s) { [void]$dtSizes.Rows.Add([string]$s.MinMB, [string]$s.Folder, (@($s.Extensions) -join ', ')) } }

        $c.chkOld.IsChecked = [bool]$r.OldFiles.Enabled
        $c.txtOldDays.Text = if ($r.OldFiles.Days) { [string]$r.OldFiles.Days } else { '90' }
        $c.txtOldFolder.Text = if ($r.OldFiles.Folder) { [string]$r.OldFiles.Folder } else { 'Old' }
        $c.chkQuiet.IsChecked = [bool]$r.QuietHours.Enabled
        $c.txtQuietFrom.Text = if ($r.QuietHours.From) { [string]$r.QuietHours.From } else { '09:00' }
        $c.txtQuietTo.Text = if ($r.QuietHours.To) { [string]$r.QuietHours.To } else { '18:00' }

        $dtExt.Rows.Clear()
        $rows = foreach ($p in $r.Extensions.PSObject.Properties) { [pscustomobject]@{ E = $p.Name; F = [string]$p.Value } }
        foreach ($row in ($rows | Sort-Object F, E)) { [void]$dtExt.Rows.Add($row.E, $row.F) }
    }
    & $load $RulesFile
    $c.grid.ItemsSource = $dtExt.DefaultView
    $c.gridFolders.ItemsSource = $dtFolders.DefaultView
    $c.gridNames.ItemsSource = $dtNames.DefaultView
    $c.gridSizes.ItemsSource = $dtSizes.DefaultView

    # Drag files onto the type table to add their types.
    $c.grid.Add_PreviewDragOver({
        param($s, $e)
        if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { $e.Effects = 'Copy' } else { $e.Effects = 'None' }
        $e.Handled = $true
    })
    $c.grid.Add_Drop({
        param($s, $e)
        $added = @()
        if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) {
            foreach ($path in @($e.Data.GetData([Windows.DataFormats]::FileDrop))) {
                $ext = [IO.Path]::GetExtension([string]$path).ToLowerInvariant()
                if (-not $ext -or $ext -notmatch '^\.[a-z0-9_-]+$') { continue }
                $exists = $false
                foreach ($row in $dtExt.Rows) { if (([string]$row['Extension']).ToLowerInvariant() -eq $ext) { $exists = $true } }
                if (-not $exists -and ($added -notcontains $ext)) {
                    [void]$dtExt.Rows.Add($ext, ($ext.TrimStart('.').ToUpper() + ' Files'))
                    $added += $ext
                }
            }
        }
        $c.lblDrop.Text = if ($added.Count) { "Added: $($added -join ', '). Change the folder names in the table if you like, then press Save." } else { 'Those types are already in the table (or the files have no type).' }
        $e.Handled = $true
    }.GetNewClosure())

    $c.btnAddDownloads.Add_Click({
        foreach ($row in $dtFolders.Rows) { if ([string]$row['Folder'] -eq 'Downloads') { return } }
        [void]$dtFolders.Rows.Add('Downloads', 'Leave', 'None')
    }.GetNewClosure())
    $c.btnAddFolder.Add_Click({
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog
        $fb.Description = 'Choose a folder for DeskOrg to tidy'
        if ($fb.ShowDialog() -eq 'OK') { [void]$dtFolders.Rows.Add($fb.SelectedPath, 'Leave', 'None') }
    }.GetNewClosure())

    # Reads the editor, checks everything, and returns the rules object (or throws a plain message).
    $collect = {
        [void]$c.grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
        [void]$c.gridFolders.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
        [void]$c.gridNames.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
        [void]$c.gridSizes.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)

        $badName = { param($n) ([string]::IsNullOrWhiteSpace($n) -or $n -match '[\\/:*?"<>|]' -or $n -in @('.', '..') -or [IO.Path]::IsPathRooted($n)) }
        $folderOk = { param($p) ($p -in @('Desktop', 'Downloads')) -or (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($p)) -PathType Container) }

        $source = $c.txtSource.Text.Trim()
        if (-not $source) { throw 'Type the main folder to tidy (for example Desktop).' }
        if (-not (& $folderOk $source)) { throw "That folder does not exist:`n$source" }

        $extra = @()
        foreach ($row in $dtFolders.Rows) {
            $p = ([string]$row['Folder']).Trim()
            if (-not $p) { continue }
            if (-not (& $folderOk $p)) { throw "That folder does not exist:`n$p" }
            $u = ([string]$row['Unknown files']).Trim(); if (-not $u) { $u = 'Leave' }
            if ($u -ne 'Leave' -and (& $badName $u)) { throw "For $p, 'Unknown files' must be Leave or a simple folder name." }
            $dd = ([string]$row['Dates']).Trim(); if (-not $dd) { $dd = 'None' }
            if ($dd -notin @('None', 'Month', 'Year')) { throw "For $p, Dates must be None, Month or Year." }
            $entry = [ordered]@{ Path = $p; UnknownFileBehavior = $u; DatedFolders = $dd }
            if ($oldExtra.ContainsKey($p)) {
                if ($oldExtra[$p].Duplicates) { $entry['Duplicates'] = [string]$oldExtra[$p].Duplicates }
                if ($oldExtra[$p].Extensions) { $entry['Extensions'] = $oldExtra[$p].Extensions }
            }
            $extra += $entry
        }

        $recent = 0
        if (-not [int]::TryParse($c.txtRecent.Text.Trim(), [ref]$recent) -or $recent -lt 0 -or $recent -gt 1440) {
            throw 'Minutes must be a number from 0 to 1440.'
        }

        $tmp = [TimeSpan]::Zero
        $qf = $c.txtQuietFrom.Text.Trim(); $qt = $c.txtQuietTo.Text.Trim()
        if (-not [TimeSpan]::TryParse($qf, [ref]$tmp) -or -not [TimeSpan]::TryParse($qt, [ref]$tmp)) {
            throw 'Quiet hours must be times like 09:00 and 18:00.'
        }

        $oldDays = 90
        if (-not [int]::TryParse($c.txtOldDays.Text.Trim(), [ref]$oldDays) -or $oldDays -lt 1 -or $oldDays -gt 3650) {
            throw 'Old files: days must be a number from 1 to 3650.'
        }
        $oldFolder = $c.txtOldFolder.Text.Trim()
        if (& $badName $oldFolder) { throw 'Old files: choose a simple folder name (no \ / : * ? " < > |).' }

        $prot = @()
        foreach ($t in ($c.txtProt.Text -split '[,\s]+')) {
            $t = $t.Trim().ToLowerInvariant()
            if (-not $t) { continue }
            if (-not $t.StartsWith('.')) { $t = '.' + $t }
            if ($t -notmatch '^\.[a-z0-9_-]+$') { throw "Not a file type: $t" }
            $prot += $t
        }

        $map = [ordered]@{}
        foreach ($row in $dtExt.Rows) {
            $e = ([string]$row['Extension']).Trim().ToLowerInvariant()
            $f = ([string]$row['Folder']).Trim()
            if (-not $e -and -not $f) { continue }
            if (-not $e.StartsWith('.')) { $e = '.' + $e }
            if ($e -notmatch '^\.[a-z0-9_-]+$') { throw "Not a file type: $e" }
            if (& $badName $f) { throw "Choose a simple folder name for $e (no \ / : * ? `" < > |)." }
            if ($prot -contains $e) { throw "$e is in the never-move list, so it cannot also have a folder." }
            $map[$e] = $f
        }
        if ($map.Count -eq 0) { throw 'Add at least one file type.' }

        $names = @()
        foreach ($row in $dtNames.Rows) {
            $m = ([string]$row['Pattern']).Trim(); $f = ([string]$row['Folder']).Trim()
            if (-not $m -and -not $f) { continue }
            if (-not $m) { throw 'A name rule has a folder but no pattern.' }
            if (& $badName $f) { throw "Choose a simple folder name for the name rule '$m'." }
            $names += [ordered]@{ Match = $m; Folder = $f }
        }

        $sizes = @()
        foreach ($row in $dtSizes.Rows) {
            $mbText = ([string]$row['Bigger than (MB)']).Trim(); $f = ([string]$row['Folder']).Trim()
            if (-not $mbText -and -not $f) { continue }
            $mb = 0.0
            if (-not [double]::TryParse($mbText, [ref]$mb) -or $mb -le 0) { throw 'A size rule needs a size in MB above 0.' }
            if (& $badName $f) { throw "Choose a simple folder name for the $mbText MB size rule." }
            $types = @()
            foreach ($t in (([string]$row['Only these types (optional)']) -split '[,\s]+')) {
                $t = $t.Trim().ToLowerInvariant(); if (-not $t) { continue }
                if (-not $t.StartsWith('.')) { $t = '.' + $t }
                if ($t -notmatch '^\.[a-z0-9_-]+$') { throw "Not a file type: $t" }
                $types += $t
            }
            $sizes += [ordered]@{ MinMB = $mb; Folder = $f; Extensions = $types }
        }

        return [ordered]@{
            SourceFolder = $source
            UnknownFileBehavior = $(if ($c.cmbUnknown.SelectedIndex -eq 1) { 'Leave' } else { 'Other Files' })
            SkipRecentMinutes = $recent
            DatedFolders = @('None', 'Month', 'Year')[[Math]::Max(0, $c.cmbDated.SelectedIndex)]
            Duplicates = $(if ($c.cmbDup.SelectedIndex -eq 1) { 'Skip' } else { 'Rename' })
            SkipFiles = @(($c.txtSkip.Text -split "\r?\n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            ExtraFolders = $extra
            NameRules = $names
            SizeRules = $sizes
            OldFiles = [ordered]@{ Enabled = [bool]$c.chkOld.IsChecked; Days = $oldDays; Folder = $oldFolder }
            QuietHours = [ordered]@{ Enabled = [bool]$c.chkQuiet.IsChecked; From = $qf; To = $qt }
            ProtectedExtensions = $prot
            Extensions = $map
        }
    }

    $c.btnReset.Add_Click({
        if (Confirm-Dialog 'Put every rule back to the DeskOrg defaults? (Nothing is saved until you press Save.)') { & $load (Join-Path $AppFolder 'DeskOrgRules.json') }
    }.GetNewClosure())
    $c.btnCancel.Add_Click({ $w.Close() }.GetNewClosure())

    $c.btnExport.Add_Click({
        try {
            $out = & $collect
            $dlg = New-Object Microsoft.Win32.SaveFileDialog
            $dlg.Filter = 'DeskOrg rules (*.json)|*.json'
            $dlg.FileName = 'DeskOrg rules.json'
            if ($dlg.ShowDialog()) {
                ($out | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $dlg.FileName -Encoding UTF8
                [void](Show-Dialog "Rules exported to:`n$($dlg.FileName)")
            }
        }
        catch { [void](Show-Dialog $_.Exception.Message 'DeskOrg' -Warn) }
    }.GetNewClosure())

    $c.btnImport.Add_Click({
        try {
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Filter = 'DeskOrg rules (*.json)|*.json'
            if ($dlg.ShowDialog()) {
                $r = Read-JsonSafe $dlg.FileName
                if ($null -eq $r -or -not $r.Extensions -or -not $r.SourceFolder) { throw 'That file is not a DeskOrg rules file.' }
                & $load $dlg.FileName
                [void](Show-Dialog 'Rules loaded into the editor. Press Save to use them.')
            }
        }
        catch { [void](Show-Dialog $_.Exception.Message 'DeskOrg' -Warn) }
    }.GetNewClosure())

    $c.btnSave.Add_Click({
        try {
            $out = & $collect
            if (Test-Path -LiteralPath $RulesFile) {
                Copy-Item -LiteralPath $RulesFile -Destination ($RulesFile + '.bak') -Force
            }
            ($out | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $RulesFile -Encoding UTF8
            Set-Status 'Rules saved.'
            $w.Close()
            [void](Show-Dialog 'Rules saved. They apply from the next run. The old rules are kept as DeskOrgRules.json.bak.')
        }
        catch {
            [void](Show-Dialog $_.Exception.Message 'DeskOrg' -Warn)
        }
    }.GetNewClosure())

    $script:RulesWindow = $w      # kept so automated tests can reach the editor
    $script:RulesControls = $c
    [void]$w.ShowDialog()
}

# ---------------- PAUSE / RESUME ----------------

function Test-Paused { return (Test-Path -LiteralPath $script:PauseFile) }

function Set-Paused {
    param([bool]$Paused)
    try {
        if ($Paused) { Set-Content -LiteralPath $script:PauseFile -Value 'paused' -Encoding ASCII }
        else { Remove-Item -LiteralPath $script:PauseFile -Force -ErrorAction SilentlyContinue }
    } catch { }
    if ($script:TrayPause) { $script:TrayPause.Text = if (Test-Paused) { T 'tray.resume' } else { T 'tray.pause' } }
    Set-Status $(if (Test-Paused) { 'Automatic tidying is paused.' } else { 'Automatic tidying is on.' })
}

# ---------------- FIRST RUN AND WHAT'S NEW ----------------

function Show-WhatsNew {
    $lines = @()
    foreach ($c in $script:Changes) {
        $lines += ("Version " + $c.Version)
        foreach ($i in $c.Items) { $lines += ("   - " + $i) }
        $lines += ''
    }
    [void](Show-Dialog (($lines -join "`n").Trim()) (T 'hist.whatsnew'))
}

function Show-FirstRun {
    $w = New-DarkWindow 'DeskOrg' 560 520
    $w.SizeToContent = 'Height'
    $w.ResizeMode = 'NoResize'
    $s = New-Stack
    $s.Margin = '26'
    $h = New-Text (T 'first.title') 22 $script:C.Teal -Display -Wrap
    $h.Margin = '0,0,0,10'
    [void]$s.Children.Add($h)
    $t = New-Text (T 'first.text') 13 $script:C.Text -Wrap
    $t.Margin = '0,0,0,12'
    [void]$s.Children.Add($t)

    $cbDesk = New-Object System.Windows.Controls.CheckBox
    $cbDesk.Content = T 'first.desktop'; $cbDesk.IsChecked = $true; $cbDesk.IsEnabled = $false
    $cbDesk.Foreground = $script:C.Text; $cbDesk.Margin = '0,0,0,6'
    [void]$s.Children.Add($cbDesk)
    $cbDl = New-Object System.Windows.Controls.CheckBox
    $cbDl.Content = T 'first.downloads'; $cbDl.IsChecked = $false
    $cbDl.Foreground = $script:C.Text; $cbDl.Margin = '0,0,0,14'
    [void]$s.Children.Add($cbDl)

    $lg = New-Text (T 'first.lang') 12 $script:C.Muted -Bold
    [void]$s.Children.Add($lg)
    $cmb = New-Object System.Windows.Controls.ComboBox
    foreach ($n in @('English', 'हिन्दी', 'ਪੰਜਾਬੀ')) { [void]$cmb.Items.Add($n) }
    $cmb.SelectedIndex = switch ($script:Lang) { 'hi' { 1 } 'pa' { 2 } default { 0 } }
    $cmb.Margin = '0,4,0,18'; $cmb.Padding = '6'
    [void]$s.Children.Add($cmb)

    $choice = @{ V = 'skip' }
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'
    [void]$row.Children.Add((New-SmallButton (T 'first.skip') { $choice.V = 'skip'; $w.Close() }.GetNewClosure()))
    [void]$row.Children.Add((New-SmallButton (T 'first.preview') { $choice.V = 'preview'; $w.Close() }.GetNewClosure() -Primary))
    [void]$s.Children.Add($row)
    $w.Content = $s
    [void]$w.ShowDialog()

    # Save the choices.
    $lang = @('en', 'hi', 'pa')[[Math]::Max(0, $cmb.SelectedIndex)]
    if ($lang -ne $script:Lang) {
        $script:Lang = $lang; Update-Setting 'Language' $lang
        if ($script:Window) { Apply-Language }
    }
    if ($cbDl.IsChecked) {
        $r = Read-JsonSafe $RulesFile
        if ($r) {
            $has = $false
            foreach ($e in @($r.ExtraFolders)) { if ($e -and [string]$e.Path -eq 'Downloads') { $has = $true } }
            if (-not $has) {
                $list = @(@($r.ExtraFolders) | Where-Object { $_ }) + @([pscustomobject]@{ Path = 'Downloads'; UnknownFileBehavior = 'Leave'; DatedFolders = 'None' })
                $r | Add-Member -NotePropertyName ExtraFolders -NotePropertyValue $list -Force
                try { ($r | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $RulesFile -Encoding UTF8 } catch { }
            }
        }
    }
    Update-Setting 'FirstRunDone' $true
    Update-Setting 'LastSeenVersion' $script:AppVersion
    if ($choice.V -eq 'preview') { Show-PreviewWindow }
}

# ---------------- LANGUAGE ----------------

function Apply-Language {
    # Updates the sidebar and the current page after a language change.
    $labels = @{ Home = '01'; Organize = '02'; Automation = '03'; Settings = '04'; Activity = '05' }
    foreach ($k in $labels.Keys) {
        if ($script:NavButtons.ContainsKey($k)) { $script:NavButtons[$k].Content.Text = ($labels[$k] + '   ' + (T ('nav.' + $k))) }
    }
    if ($script:Tray) {
        $items = $script:Tray.ContextMenuStrip.Items
        $items[0].Text = T 'tray.open'; $items[1].Text = T 'tray.now'; $items[2].Text = T 'tray.undo'
        $script:TrayPause.Text = if (Test-Paused) { T 'tray.resume' } else { T 'tray.pause' }
        $items[$items.Count - 1].Text = T 'tray.exit'
    }
    Navigate-To $script:CurrentPage
}

function Update-CurrentPage { Navigate-To $script:CurrentPage }

function Set-Language {
    param([string]$Code)
    $script:Lang = $Code
    Update-Setting 'Language' $Code
    Apply-Language
}

function Add-LanguageAndLookCards {
    param($Root)
    $card = New-Card (T 'set.lang') (T 'set.lang.d') $script:C.Purple
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    foreach ($pair in @(@('en', 'English'), @('hi', 'हिन्दी'), @('pa', 'ਪੰਜਾਬੀ'))) {
        $code = $pair[0]
        $b = New-SmallButton $pair[1] { Set-Language $code }.GetNewClosure() -Primary:($script:Lang -eq $code)
        $b.Margin = '0,0,8,0'
        [void]$row.Children.Add($b)
    }
    [void]$card.Body.Children.Add($row)
    [void]$Root.Children.Add($card.Border)

    $look = New-Card (T 'set.look') (T 'set.look.d') $script:C.Blue
    $lab = New-Text (T 'set.size') 12 $script:C.Muted -Bold
    [void]$look.Body.Children.Add($lab)
    $row2 = New-Object System.Windows.Controls.StackPanel
    $row2.Orientation = 'Horizontal'
    $row2.Margin = '0,6,0,12'
    foreach ($pair in @(@(100, 'A'), @(115, 'A+'), @(130, 'A++'))) {
        $pct = $pair[0]
        $b = New-SmallButton $pair[1] { Set-TextScale $pct; Update-CurrentPage }.GetNewClosure() -Primary:([int]$script:Settings.TextScale -eq $pct)
        $b.Margin = '0,0,8,0'
        [void]$row2.Children.Add($b)
    }
    [void]$look.Body.Children.Add($row2)
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = T 'set.contrast'
    $cb.Foreground = $script:C.Text
    $cb.IsChecked = [bool]$script:Settings.HighContrast
    $cb.Add_Click({ Update-Setting 'HighContrast' ([bool]$cb.IsChecked) }.GetNewClosure())
    [void]$look.Body.Children.Add($cb)
    [void]$Root.Children.Add($look.Border)
}

function Add-PrivacyCard {
    param($Root)
    $card = New-Card (T 'priv.title') (T 'priv.text') $script:C.Teal
    [void]$Root.Children.Add($card.Border)
}

# ---------------- TRAY ICON ----------------

function Show-ControlCenter {
    $script:Window.Visibility = 'Visible'
    if ($script:Window.WindowState -eq 'Minimized') { $script:Window.WindowState = 'Normal' }
    [void]$script:Window.Activate()
}

function Initialize-Tray {
    try {
        $icon = Join-Path $AppFolder 'DeskOrg.ico'
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ni.Icon = if (Test-Path -LiteralPath $icon) { New-Object System.Drawing.Icon($icon) } else { [System.Drawing.SystemIcons]::Application }
        $ni.Text = 'DeskOrg'
        $menu = New-Object System.Windows.Forms.ContextMenuStrip

        $open = $menu.Items.Add((T 'tray.open'))
        $open.Font = New-Object System.Drawing.Font($open.Font, [System.Drawing.FontStyle]::Bold)
        $open.Add_Click({ Show-ControlCenter })

        $now = $menu.Items.Add((T 'tray.now'))
        $now.Add_Click({ Invoke-OrganizeNow })

        $undo = $menu.Items.Add((T 'tray.undo'))
        $undo.Add_Click({ Show-ControlCenter; Invoke-UndoLast })

        [void]$menu.Items.Add('-')
        $script:TrayPause = $menu.Items.Add($(if (Test-Paused) { T 'tray.resume' } else { T 'tray.pause' }))
        $script:TrayPause.Add_Click({ Set-Paused (-not (Test-Paused)) })

        [void]$menu.Items.Add('-')
        $quit = $menu.Items.Add((T 'tray.exit'))
        $quit.Add_Click({ $script:RealExit = $true; $script:Window.Close() })

        $ni.ContextMenuStrip = $menu
        $ni.Add_DoubleClick({ Show-ControlCenter })
        $ni.Visible = $true
        $script:Tray = $ni
        return $true
    }
    catch { return $false }
}

function Initialize-WindowBehaviour {
    # Closing the window with X hides it to the tray; Exit really quits.
    $trayOk = Initialize-Tray
    if (-not $trayOk) { $script:RealExit = $true }
    try {
        $ico = Join-Path $AppFolder 'DeskOrg.ico'
        if (Test-Path -LiteralPath $ico) {
            $script:Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri($ico)))
        }
    } catch { }
    if ([int]$script:Settings.TextScale -ne 100) { Set-TextScale ([int]$script:Settings.TextScale) }

    $script:Window.Add_Closing({
        param($sender, $e)
        if (-not $script:RealExit) {
            $e.Cancel = $true
            $script:Window.Visibility = 'Hidden'
            if (-not $script:TrayTipShown -and $script:Tray) {
                $script:TrayTipShown = $true
                $script:Tray.ShowBalloonTip(3000, 'DeskOrg is still running', 'Right-click the DeskOrg icon near the clock for options, or choose Exit to quit.', [System.Windows.Forms.ToolTipIcon]::Info)
            }
        }
    })
    $script:Window.Add_Closed({
        if ($script:Tray) { $script:Tray.Visible = $false; $script:Tray.Dispose() }
        if ($script:ShowTimer) { $script:ShowTimer.Stop() }
        try { $script:InstanceMutex.ReleaseMutex() } catch { }
    })

    # Keyboard shortcuts.
    $script:Window.Add_PreviewKeyDown({
        param($sender, $e)
        $ctrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
        $k = [string]$e.Key
        if ($k -eq 'F1') { Open-FileSafely (Join-Path $AppFolder 'DeskOrg-Guide.html') 'the guide'; $e.Handled = $true }
        elseif ($ctrl -and $k -eq 'P') { Show-PreviewWindow; $e.Handled = $true }
        elseif ($ctrl -and $k -eq 'O') { Invoke-OrganizeNow; $e.Handled = $true }
        elseif ($ctrl -and $k -eq 'Z') { Invoke-UndoLast; $e.Handled = $true }
        elseif ($ctrl -and $k -eq 'D') { Show-DuplicateFinder; $e.Handled = $true }
        elseif ($ctrl -and $k -in @('D1', 'D2', 'D3', 'D4', 'D5')) {
            Navigate-To @('Home', 'Organize', 'Automation', 'Settings', 'Activity')[[int]$k.Substring(1) - 1]
            $e.Handled = $true
        }
    })

    # A second start of DeskOrg asks this window to come forward.
    $script:ShowTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ShowTimer.Interval = [TimeSpan]::FromMilliseconds(700)
    $script:ShowTimer.Add_Tick({
        if ($script:ShowEvent -and $script:ShowEvent.WaitOne(0)) { Show-ControlCenter }
    })
    $script:ShowTimer.Start()

    # First start: welcome. After an update: what's new.
    $script:Window.Add_ContentRendered({
        if ($script:WelcomeDone) { return }
        $script:WelcomeDone = $true
        if (-not $script:Settings.FirstRunDone) { Show-FirstRun }
        elseif ([string]$script:Settings.LastSeenVersion -ne $script:AppVersion) {
            Show-WhatsNew
            Update-Setting 'LastSeenVersion' $script:AppVersion
        }
    })
}

# ---------------- UPDATE CHECK ----------------

function Start-UpdateCheck {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers['User-Agent'] = 'DeskOrg/' + $script:AppVersion
        $script:UpdateTask = $wc.DownloadStringTaskAsync($script:UpdateUrl)
        $script:UpdateClient = $wc
        $script:UpdateTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:UpdateTimer.Interval = [TimeSpan]::FromSeconds(1)
        $script:UpdateTries = 0
        $script:UpdateTimer.Add_Tick({
            $script:UpdateTries++
            if ($script:UpdateTask.IsCompleted -or $script:UpdateTries -gt 20) {
                $script:UpdateTimer.Stop()
                try {
                    if ($script:UpdateTask.IsCompleted -and -not $script:UpdateTask.IsFaulted -and -not $script:UpdateTask.IsCanceled) {
                        $info = $script:UpdateTask.Result | ConvertFrom-Json
                        if ([version]$info.version -gt [version]$script:AppVersion) {
                            $script:UpdateInfo = $info
                            Add-UpdateBanner
                        }
                    }
                } catch { }
                try { $script:UpdateClient.Dispose() } catch { }
            }
        })
        $script:UpdateTimer.Start()
    }
    catch { }
}

function Add-UpdateBanner {
    # Shown at the top of the current page when a newer version exists.
    if ($null -eq $script:UpdateInfo -or $null -eq $script:PageHost) { return }
    $b = New-Object System.Windows.Controls.Border
    $b.Background = '#10332E'
    $b.BorderBrush = $script:C.Teal
    $b.BorderThickness = '1'
    $b.CornerRadius = '12'
    $b.Padding = '14,10'
    $b.Margin = '0,0,12,14'
    $s = New-Stack
    [void]$s.Children.Add((New-Text ("A new DeskOrg is available: version " + $script:UpdateInfo.version) 12 $script:C.Teal -Bold))
    if ($script:UpdateInfo.notes) {
        $n = New-Text ([string]$script:UpdateInfo.notes) 11 $script:C.Muted -Wrap
        $n.Margin = '0,3,0,0'
        [void]$s.Children.Add($n)
    }
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = 'Download the update'
    $btn.HorizontalAlignment = 'Left'
    $btn.Padding = '12,6'
    $btn.Margin = '0,8,0,0'
    $url = [string]$script:UpdateInfo.url
    $btn.Add_Click({
        if ($url -like 'https://*') { Start-Process $url }
    }.GetNewClosure())
    [void]$s.Children.Add($btn)
    $b.Child = $s
    $script:PageHost.Children.Insert(0, $b)
}


# SIG # Begin signature block
# MIIcOAYJKoZIhvcNAQcCoIIcKTCCHCUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD4ANg/Z1NrudOr
# i7vGTSqwhaZHR4pjwTEIyoShyflLBKCCFm4wggMwMIICGKADAgECAhBAfeExfrxD
# qU1Saw4d1EDgMA0GCSqGSIb3DQEBCwUAMDAxLjAsBgNVBAMMJURlc2tPcmcgQ29k
# ZSBTaWduaW5nIChOaXZlc2ggU2FoYXlhaykwHhcNMjYxMDMwMDEwMDQ5WhcNMzYx
# MDMwMDExMDQ5WjAwMS4wLAYDVQQDDCVEZXNrT3JnIENvZGUgU2lnbmluZyAoTml2
# ZXNoIFNhaGF5YWspMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvE4v
# prYvvRAEIy8X47cy3iL4T+uNLkWXpXJpVg5z+OXf38NcrB/5rjwDRUNNXIIFGA8X
# 4e1obz+avmLMbahaBPtKrSjRx47JkOrJh6Ysdh1YHuCsL2pb8BtqM7xXbDsw7/kF
# nalG+/VnSDfhjQIqv8wQfn2xSIfHcRL3+2s5hzG+ePZHrkTaOQlX1dlxPwBqocPL
# APq3zRvt/XgzzZ2yVbDiVouLfYQZRwhz4CIbbZch1E+DiL9wAlBBeoYzD4s3ZGhw
# STRQd1GVRX3DxR1wykL5BbO3FEw4czwSE7PXV0sgKpgLH5t+VUqdSCbpZX5EPgLk
# LPMLAm1Hmz+gjGapxQIDAQABo0YwRDAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAww
# CgYIKwYBBQUHAwMwHQYDVR0OBBYEFPvlioepdVL8MeNd+np67jS/ZZjlMA0GCSqG
# SIb3DQEBCwUAA4IBAQAru4kY6BCVH9PznqvUtgxFSFpzTEXHfqUyIED/6mhDPI8a
# JTIAfeqreBNksH2sZ4+MaPattQcfoROiz31rqdCtTSGB4ytPqXArmjaR1QrAMWBN
# DpDhJPNArD30wXmrG8sKU8HSQSxoL5M8awibcWj1RmsoeMqbCoY7tt6t3F+AsWfW
# BkZpUZ1oqUq1ZzzelBA8AXtQCC4ZwqVnaPlOx5RwV7WNVvxzJ+o65fwxJiJXXy7N
# Dsh57QQuIlgidjPV8/aUp2KPA/X6EtwhIr9aSlBBxRQbf7HDLx4oZO88To3gFyFl
# dDOW0SoyetYTITBLNWiEY/Zcc71xTHoNJmW5k8P+MIIFjTCCBHWgAwIBAgIQDpsY
# jvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJVUzEVMBMG
# A1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQw
# IgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAw
# MDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhE
# aWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57
# G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9o
# k3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFh
# mzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463J
# T17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFw
# q1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yh
# Tzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU
# 75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LV
# jHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJ
# bOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+whX8Qg
# UWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IB
# OjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6
# mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/
# BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3Au
# ZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4
# oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJv
# b3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBw
# oL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0
# E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtD
# IeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlU
# sLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAIDyyCwrFig
# DkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwY
# w02fc7cBqZ9Xql4o4rmUMIIGtDCCBJygAwIBAgIQDcesVwX/IZkuQEMiDDpJhjAN
# BgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2Vy
# dCBUcnVzdGVkIFJvb3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcNMzgwMTE0MjM1OTU5
# WjBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNV
# BAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hB
# MjU2IDIwMjUgQ0ExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAtHgx
# 0wqYQXK+PEbAHKx126NGaHS0URedTa2NDZS1mZaDLFTtQ2oRjzUXMmxCqvkbsDpz
# 4aH+qbxeLho8I6jY3xL1IusLopuW2qftJYJaDNs1+JH7Z+QdSKWM06qchUP+AbdJ
# gMQB3h2DZ0Mal5kYp77jYMVQXSZH++0trj6Ao+xh/AS7sQRuQL37QXbDhAktVJMQ
# bzIBHYJBYgzWIjk8eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0Xm+nt5pnYJU3Gmq6
# bNMI1I7Gb5IBZK4ivbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQVESYOszFI2Wv82wnJ
# RfN20VRS3hpLgIR4hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2qHxJ0ucS638ZxqU1
# 4lDnki7CcoKCz6eum5A19WZQHkqUJfdkDjHkccpL6uoG8pbF0LJAQQZxst7VvwDD
# jAmSFTUms+wV/FbWBqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgxCZSKi17yVp2NL+cn
# T6Toy+rN+nM8M7LnLqCrO2JP3oW//1sfuZDKiDEb1AQ8es9Xr/u6bDTnYCTKIsDq
# 1BtmXUqEG1NqzJKS4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7OgWmnhFr4yUozZtqg
# PrHRVHhGNKlYzyjlroPxul+bgIspzOwbtmsgY1MCAwEAAaOCAV0wggFZMBIGA1Ud
# EwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFO9vU0rp5AZ8esrikFb2L9RJ7MtOMB8G
# A1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjAT
# BgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGG
# GGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2Nh
# Y2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYD
# VR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9
# bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEwvb4LyLU0pn/N0IfF
# iBowf0/Dm1wGc/Do7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8G0iP5kvN2n7Jd2E4
# /iEIUBO41P5F448rSYJ59Ib61eoalhnd6ywFLerycvZTAz40y8S4F3/a+Z1jEMK/
# DMm/axFSgoR8n6c3nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCDA/JYsq7pGdogP8HR
# trYfctSLANEBfHU16r3J05qX3kId+ZOczgj5kjatVB+NdADVZKON/gnZruMvNYY2
# o1f4MXRJDMdTSlOLh0HCn2cQLwQCqjFbqrXuvTPSegOOzr4EWj7PtspIHBldNE2K
# 9i697cvaiIo2p61Ed2p8xMJb82Yosn0z4y25xUbI7GIN/TpVfHIqQ6Ku/qjTY6hc
# 3hsXMrS+U0yy+GWqAXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0c1ugMZyZZd/BdHLi
# Ru7hAWE6bTEm4XYRkA6Tl4KSFLFk43esaUeqGkH/wyW4N7OigizwJWeukcyIPbAv
# jSabnf7+Pu0VrFgoiovRDiyx3zEdmcif/sYQsfch28bZeUz2rtY/9TCA6TD8dC3J
# E3rYkrhLULy7Dc90G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz0scmbKvFoW2jNrbM
# 1pD2T7m3XDCCBu0wggTVoAMCAQICEAhP3DNPfkVO28MPj/mSGDUwDQYJKoZIhvcN
# AQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEw
# PwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2
# IFNIQTI1NiAyMDI1IENBMTAeFw0yNjA4MDUwMDAwMDBaFw0zNzExMDQyMzU5NTla
# MGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UE
# AxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3BvbmRlciAy
# MDI2IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC2e6byyf7NSvjU
# m0xls/04xjD4fAkOkbnGQi7+Wpx81iYxfzViaxSIctuH3KSl5YEYpMuFgGsA31N2
# D9ATMbfZdw5uaAhuWevQKhDdZIB4NnqcfpfpWQXJiQnDdAElETC+bhSEvNLGbA8D
# twUpFMQ4yyYQSPqomT92osQAv6hBi47ATZS6JfVWe6XxhF4jJZ3iSAuf2Cros1cz
# RSmWRHqMv9AfGZvp8ygYElhudpQjtcPpwoOl6QrZJUyV3iINvN4cO05prGV0fkjG
# 426xDr2d3z9lcSIHkdvGPdGUrXdxfVbgOUVcp2/8ISEzwKPW++Wa+E2ujI91EZtu
# kGWDJ/xZ27k3oHKEXBRGfRTqjOU+jE3ba/5++JSE/7oNHnjs5mekExYN96LV/mxU
# bCKJb8pBNY4r3uD7hEmk/M81XhVgwDA7aMzYC3LZBg9WY5BMmbSay5ecmtJuXaB/
# 0nKWmQmVZeqTVDgsmzHP5MQuhAJkiWNuC9MmCg9TZHXbJ2/yLVSov9p16UDTLtT0
# +aa1vN71fHeu1qMLlLNB3WOB/ADCxr3S/1hxI92Z6jKgEED/btwIvbfuXkNNhg8M
# tDg43c4tMZae9FvqMOt/9PvmAxF9TNIsIFB8G6yb36ZJZGUL8N/pL971DyLXcK6H
# M5PYnH5X+eVtczhCgHCVQCF6XDAlPQIDAQABo4IBlTCCAZEwDAYDVR0TAQH/BAIw
# ADAdBgNVHQ4EFgQUFMljijAu1Er7bpTz5uNAfvXszeIwHwYDVR0jBBgwFoAU729T
# SunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB/wQMMAoG
# CCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYYaHR0cDov
# L29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2FjZXJ0cy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2
# U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL2NybDMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5nUlNBNDA5
# NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG
# /WwHATANBgkqhkiG9w0BAQsFAAOCAgEAjcU6YR6dUgrfmawJgH59KECxa9Ji8sEi
# 2g10CBDaMiqsaxWyW5cwlT/6ZF5sFznazqVsoC85U9dqLOYqQwst+UQQoNlDHgKR
# La3xoc+OReFreFhnTXSG0Vrd2E2CZqUfm+5a+He1MJ/h+tNLuA+0Zzhn/Fo+FDYA
# HWZHx4R79ZsfRFYe9UiXpXBDf6DkUo183Y38NYmR/XfDYf7YZ+oR9t3flbDwK+hg
# GMs0gNNp1w9Z2CyOyI5or/sSwomAuNQ0hWC9xoU4stD8aWsD7RkcmgVRs6vlIk3z
# PKQ+ylcheWkMlj+CoVRlFE55pv0ZWCaFt04lwP/rdGHE9qEVQZtyRE42ox7oNgC/
# r+Y4bSlZ3dw9K2x1xLtu6PkPKeLBFjzKigwfqm3Hm+k/+lnME8F5kPZTgiy2HLEH
# klpryqs6QHnPXrRNeIzkAMyylnRN8P0wmirS0WkU+ywpEWFZ4QNg+9xS43tTuW9x
# 0eXh7NDc1P/sV+zWxHXKH8tFt1ncHdVzqrZaYPyYMLSn2TOXajveJW1L3joiQSPs
# WRGxkbDDW15jERFE4LvjnGu2O9zD1nLJSMdlYZEikl4w2w+q4IN/R+TIe0H4ngCI
# 1moJCTbevGH4punIxM1Uoi0nmX3ZK+XbRT01uowE5ViXWHng0RgsmrX/EdYUo80r
# 3TfMlkD0/YMxggUgMIIFHAIBATBEMDAxLjAsBgNVBAMMJURlc2tPcmcgQ29kZSBT
# aWduaW5nIChOaXZlc2ggU2FoYXlhaykCEEB94TF+vEOpTVJrDh3UQOAwDQYJYIZI
# AWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0B
# CQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAv
# BgkqhkiG9w0BCQQxIgQgpxFSb2QRVDcP8uBaDknLIJhSiIAywu5fjpbQgLrty+Iw
# DQYJKoZIhvcNAQEBBQAEggEAj08yr1fJyfAuO020mO/j7MTCTOqvZR8w+d/KS7IC
# hOiIYEw0CDxHZS8gYH74sOTyZgM63FZzU4sIH4Ao7eLt/kBnMZdst9u/9x7ARI7w
# GjxCYJ1mvDiRScMX11txBuZQRv6msXB4yH7h3OI8w1jcvOLKS/mS85Dk1ORDhtZ9
# +38w9KqOelbR2/+GBbeFoA246l2V0gmOhb1mp/Q6/MaGVZnqTsmbHdZxmV3D03X2
# /0XTF1t/abLUAVabmZb4XHUMoVkJWoqK7GEfx+yypPPdf4+ivRcloA0Ncz9W0Qa6
# IOKqobxR9JlUH1ffEOC/RkhDWEu7G9miX9K/pJZ6A3WctqGCAyYwggMiBgkqhkiG
# 9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3Rh
# bXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO28MPj/mSGDUw
# DQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqG
# SIb3DQEJBTEPFw0yNjExMTMwMjM4MDRaMC8GCSqGSIb3DQEJBDEiBCCDfC9cAhor
# KBRHyZhDFzTAAffVTC57EHAxd2BFJWhCUjANBgkqhkiG9w0BAQEFAASCAgCRbt+6
# ULEi9Jdm4C98oFVy1EDlSmulUFFwLU6H79UmP0zhoeVCSTnX/3DXni09kjiAY7Xq
# IKMxQFphcoTDcTfIEiWJ3CmOmdT4bit61Ee5OYEvqMFExScw74tvnGqptxo8briL
# tX2pqvs31Rp5hEwq3YfcyZHPigOt20YYhPoKvbHOOs+MqaplVC2o2/6mmmnwv0ez
# aGVeBSyNKbbVo9zFOV1OWLIowp4QELElZt/yZepJIoYSBHswHKDdCBKQ/1sXKbIo
# 93PrwDcQV+YFKNAR4jLZYbrTdKnUImFA2USo5ZYJwYewk0nv7MV15pYodweC/2/+
# Qc2MI6AdXYqoOpI3KfmBSfIZaePbylf61jLpmnYC7JN9o41ndSIZIR/rtsd5QrNt
# D98/lA5UrWGcCV1z0dVtG0Dfx4o+6aXOxr84bWaxo5jwwJ54lGmRXFrmjeKydQRS
# HDSzoYLIcLyA5MBZCWF6XSaqpb1R0J1nMuQiR2bIgYfKtRK/dQPdJyUvSO1WNzMp
# liZI/c+GTvSQD+xr+zXncfOJfMcrE3Y4ghpXTzuzsLLq7rNIS/dMsr3Ve4TjHj03
# haZcEL9BLm4S0wSaaFrcZDF7seSoYLbNYdPIp202/5D5HxEVybro+LsYqCXyHHsm
# nrGKdnoS27QeHC7FDwoZkWeUHlfjzRD5jHrzhw==
# SIG # End signature block
