# AyahLock

A personal iPhone app: pin one ayah or dua to your lock screen, tap play, and hear the Arabic recitation repeat as many times as you choose. English and Bengali meanings can be shown or hidden.

## What it does

- **Lock-screen widget** with the Arabic text, one meaning (Bengali first, then English, whichever is on), and a play button.
- **Repeat player**: 1–999 times or until you stop it, with a 0–10 second pause between repeats and an automatic stop after a time limit you set (default 30 minutes).
- **Lock-screen panel while playing** (a Live Activity) with the text, meanings, a "3 of 7" counter and a stop button. Also shows in the Dynamic Island.
- **Standard lock-screen media controls** (pause, play, stop), headphone buttons, and pause during calls.
- **Add any ayah or a range of up to 20 ayahs**, or one of 16 quick picks (Ayat al-Kursi, last two ayahs of Al-Baqarah, the three Quls, common Quranic duas).
- **Add your own dua**: type the Arabic, the meanings and the source, and attach an audio file from the Files app.
- **Works offline** after an item is downloaded. No account, no ads, no tracking.

Text and audio come from the free AlQuran Cloud API: Arabic (Uthmani), English (Saheeh International), Bengali (Muhiuddin Khan), and six reciters.

## Quran reader (Quran tab)

- Whole Quran saved on the phone: Arabic with English and Bengali meanings, each switched on or off.
- Recitation of any surah with the current ayah highlighted; surahs can be saved for offline listening.
- **Tafsir** for any ayah (tap the ayah, then "Tafsir"): Ibn Kathir and Ma'ariful Qur'an in English; Ahsanul Bayaan, Abu Bakr Zakaria and Ibn Kathir in Bengali. Each surah is kept after first opening, or save a whole tafsir in Reader settings.
- **Bookmarks with notes** (tap an ayah, then "Bookmark with note"); see them all under Quran > Bookmarks, search the notes, and share them as text.
- **IndoPak script** with the Digital Khatt IndoPak font (SIL Open Font License). The matching text needs a free account to download: get "Digital Khatt Indopak Script – Ayah by Ayah" as JSON from https://qul.tarteel.ai/resources/quran-script/566, then either import it in Reader settings on the phone, or add it to the project as `App/IndoPak.json` so it's built in.

## What you need

- A Mac with **Xcode** (free from the Mac App Store). Xcode 16 or newer is safest.
- Your iPhone on **iOS 17 or newer** (Settings > General > About > iOS Version), and a USB cable.
- A free Apple Account. With a free account the app **stops opening 7 days after you install it**; plug in and press Run again to renew. The paid Apple Developer Program ($99/year) makes it last a year.

## Install (about 20 minutes the first time)

1. **Install Homebrew and XcodeGen.** Open Terminal on the Mac and paste the Homebrew install command from https://brew.sh. Then run:
   ```
   brew install xcodegen
   ```
2. **Unzip AyahLock.zip** and move into the folder in Terminal:
   ```
   cd ~/Downloads/AyahLock
   ```
3. **Give the app your own identifier** (letters and numbers only):
   ```
   sh rename.sh yourname
   ```
4. **Create the Xcode project and open it:**
   ```
   xcodegen generate
   open AyahLock.xcodeproj
   ```
5. **Sign it.** In Xcode, click the blue AyahLock project at the top left. For **each** of the two targets, AyahLock and AyahLockWidget: open **Signing & Capabilities**, tick **Automatically manage signing**, and choose your name ("Personal Team") under Team. Add your Apple Account under Xcode > Settings > Accounts if it isn't listed.
6. **Prepare the iPhone.** Plug it in and tap Trust. Turn on Settings > Privacy & Security > **Developer Mode** (the iPhone restarts).
7. **Run.** Choose your iPhone in the device menu at the top of Xcode and press the ▶ button.
8. **Trust the app** the first time: on the iPhone go to Settings > General > VPN & Device Management, tap your Apple Account, and tap Trust.

## Use it

1. Open AyahLock, tap **+**, choose a reciter and a quick pick or any ayah range. It downloads and pins automatically.
2. Set the repeat count, pause and meanings on the main screen.
3. Lock the phone, touch and hold the lock screen, tap **Customize > Lock Screen**, tap the widget area under the clock, and add **Pinned Ayah/Dua**. The rectangular size shows text plus a play button; the round one is just a play button.
4. Tap play on the lock screen. iPhone asks for Face ID or your passcode first (Apple requires this for widget buttons); then the recitation starts.

## Known limits and things to check when you first build it

This code was written without a Mac, so it **has not been compiled or run yet**. Expect to fix a few small compile errors on the first build; paste any error message to me and I'll fix it.

Specific things I'm not certain of until it runs on your phone:

- **App Group on a free account.** The widget reads your pinned item through an App Group. If Xcode says App Groups aren't available for your Personal Team, the widget will show "Open AyahLock and pin…" even after you pin. Tell me and I'll switch to another approach.
- **Starting the lock-screen panel from the widget.** If iOS refuses to start the Live Activity when playback begins from the lock screen, the audio still plays and the media controls still work; only the counter panel is missing.
- **Reciter availability.** Mishary Alafasy is the most widely used audio on this service. If another reciter shows "No audio came back", pick a different one.
- **Arabic script rendering.** The iPhone's system Arabic font displays Uthmani text well, but a few special marks may look slightly different from a printed mushaf.
- **Long passages** don't fit the lock-screen widget; it shows the first two or three lines. The full text is in the app and in the playing panel.

## Your own duas

Hadith duas (for example from Hisnul Muslim) aren't bundled, because I didn't want to type out Arabic and Bengali texts that could contain mistakes. Add them yourself under **+ > Add my own dua** with text you trust and an audio file, and check repeat counts (such as 3, 33 or 100) against the hadith source.

## Files

- `project.yml` – project description for XcodeGen
- `App/` – the app: screens, player, downloads
- `Widget/` – lock-screen widget and the Live Activity panel
- `Shared/` – data models, storage and play/stop actions used by both
