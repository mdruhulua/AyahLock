# Putting AyahLock on the App Store

Follow these phases in order. Phases 1–3 make sure the app works; phases 4–9 publish it.
Your phone (iPhone 12) runs iOS 26, and the app needs iOS 17 or later, so it is supported.
An iPhone 12 has no Dynamic Island: the "3 of 7" panel appears on the lock screen only, which the app already handles.

---

## Phase 0 – Decide before you pay

- **Cost:** the Apple Developer Program costs US$99 a year (or the local price). It is required for the App Store. If you stop paying, the app is removed from the store.
- **Your name is public:** as an individual, your legal name appears as the seller on the App Store page.
- **Content rights (the biggest risk):** Apple will ask whether you have the rights to the text and audio. The app downloads them from AlQuran Cloud, whose terms say the audio files' copyrights stay with their owners, and the Bengali translation (Muhiuddin Khan, via Tanzil) is offered for non-commercial use. A free app with no ads or purchases is non-commercial, but none of this is written permission. Before submitting, email AlQuran Cloud (via islamic.network) and ask whether a free app may use the API and audio. Keep the reply.
- **Similar apps:** Apple rejects apps that duplicate others (guideline 4.3). Your difference is the lock-screen repeat player; say so in the review notes (Phase 8).

## Phase 1 – Set up the Mac (once)

1. Install **Xcode 26 or newer** from the Mac App Store. Apple only accepts uploads built with Xcode 26 and the iOS 26 SDK since April 28, 2026.
2. Open Xcode once and let it install its components, including the iOS 26 simulator.
3. Install Homebrew (https://brew.sh), then in Terminal: `brew install xcodegen`

## Phase 2 – Build and test in the virtual iPhone (Simulator)

1. In Terminal, go to the project folder and run:
   ```
   sh rename.sh yourname
   xcodegen generate
   open AyahLock.xcodeproj
   ```
2. At the top of Xcode, choose a simulator such as **iPhone 17** (any iPhone with iOS 17+ works) and press ▶.
3. Test in this order:
   - Tap **+**, pick **Ayat al-Kursi**. It should download and appear as pinned.
   - Set repeats to 3 and the pause to 2 seconds, press **Recite**, and check you hear it three times with pauses, then it stops.
   - Turn the English and Bengali meanings on and off.
   - In the Simulator menu choose **Device > Lock**. Click and hold the lock screen, choose **Customize > Lock Screen**, add **Pinned Ayah/Dua**, and tap its play button.
   - Add your own dua with an audio file (drag an MP3 onto the Simulator window first, then pick it in Files).
4. If the build fails, copy the red error text from Xcode's Issue navigator and send it to me.

Simulator limits: audio and widgets work, but Face ID prompts, Live Activity behaviour and background audio can differ from a real phone. Phase 3 checks those.

## Phase 3 – Test on your iPhone 12

1. Update the iPhone to the latest iOS (Settings > General > Software Update).
2. Plug it into the Mac and tap **Trust**.
3. Turn on Settings > Privacy & Security > **Developer Mode** (the phone restarts).
4. In Xcode, for **both** targets (AyahLock and AyahLockWidget): Signing & Capabilities > tick Automatically manage signing > choose your Team.
5. Choose your iPhone at the top of Xcode and press ▶. If asked, trust the developer in Settings > General > VPN & Device Management.
6. Repeat the Phase 2 tests, plus: lock the phone, tap play on the lock-screen widget, confirm with Face ID or passcode, and check that audio keeps playing with the screen off, the counter panel appears, and a phone call pauses it.

## Phase 4 – Join the Apple Developer Program

1. Make sure your Apple Account has two-factor authentication.
2. Install the **Apple Developer** app on your iPhone, sign in, tap **Account > Enroll**, and enroll as an **Individual**. You'll need ID and payment. (Or enroll at developer.apple.com/programs/enroll.)
3. Wait for the approval email. Then in Xcode > Settings > Accounts, your team changes from "Personal Team" to your paid team. Reselect it in Signing & Capabilities for both targets.

## Phase 5 – Get a privacy policy and support web page

Apple requires a public **Privacy Policy URL** and a **Support URL**.
1. Open `PRIVACY.md` in this folder and replace "[your email address]" with a contact email.
2. Publish it for free, for example with **Google Sites** (sites.google.com): create a site, paste the text, click Publish. Use the same page as the support page, or add a "Contact" section with your email.

## Phase 6 – Create the app in App Store Connect

1. Go to https://appstoreconnect.apple.com > **Apps** > **+** > **New App**.
2. Fill in: Platform iOS; Name (must be unique on the store, e.g. "AyahLock: Lock Screen Quran"); Primary language English; **Bundle ID** = the one rename.sh set (com.yourname.ayahlock; if it isn't listed, let Xcode upload once in Phase 7 or register it under Certificates, Identifiers & Profiles); SKU = any code, e.g. ayahlock001; User Access: Full.
3. **App Information:** category Reference (or Books); secondary Lifestyle. Content rights: answer that the app accesses third-party content, and only confirm you have rights once you have the written permission from Phase 0.
4. **Pricing and Availability:** Free. Under availability, **remove Malaysia**: its law requires Home Ministry certification for any Quran app. Also consider the EU (next item).
5. **EU Digital Services Act:** App Store Connect asks whether you're a trader. A free personal app with no business behind it is typically "not a trader", but read Apple's wording; if unsure, you can exclude the EU countries instead.
6. **App Privacy:** choose **Data Not Collected**. (The app has no accounts, analytics or ads; see PRIVACY.md.) Add the Privacy Policy URL.
7. **Age Rating:** answer the questionnaire. For this app every answer is "None"/"No", which should give the lowest rating.

## Phase 7 – Upload the build

1. In Xcode choose **Any iOS Device (arm64)** as the destination.
2. Menu **Product > Archive**. When it finishes, the Organizer window opens.
3. Click **Distribute App > App Store Connect > Upload**, accept the defaults, and click Upload.
4. Encryption: the project already declares that the app uses no non-exempt encryption, so Apple shouldn't ask.
5. After 10–60 minutes the build appears in App Store Connect under **TestFlight**. Optional but wise: install it through the TestFlight app on your iPhone and test once more.

## Phase 8 – Fill in the store page

In App Store Connect > your app > the version (1.0):
1. **Screenshots:** at least one iPhone screenshot at 1179 × 2556 or 1206 × 2622 pixels (Apple's required "iPhone with Dynamic Island, medium display" size). Run the app in the **iPhone 17** simulator and press ⌘S to save a screenshot of that size. Good set: main screen, lock-screen widget, playing panel, Add screen. Up to 10 allowed.
2. **Description**, **Keywords** (e.g. quran, ayah, dua, bengali, bangla, recitation, lock screen, widget, repeat, hifz), **Support URL**, **Promotional text** (optional).
3. **Build:** click + and select the uploaded build.
4. **App Review Information:** your contact details, and in Notes write something like:
   > AyahLock lets users pin one Quran ayah or dua to the Lock Screen and play its Arabic recitation a chosen number of times, with optional English and Bengali meanings. To test: tap +, choose "Ayat al-Kursi", press Recite. Then add the "Pinned Ayah/Dua" widget to the Lock Screen and tap its play button. No account is needed. Text and audio come from the AlQuran Cloud API.
5. **Version release:** choose manual or automatic release after approval.

## Phase 9 – Submit and respond

1. Click **Add for Review**, then **Submit**.
2. Watch your email. If Apple rejects it, the message names the guideline. Copy it to me and I'll help with the fix or the reply.
3. After approval, release it. Each update repeats Phases 7–9 with a higher version number (MARKETING_VERSION in project.yml).

## Every year

- Renew the Developer Program, or the app leaves the store.
- Apple raises the required Xcode/SDK version roughly yearly; rebuild with the new Xcode when asked.
