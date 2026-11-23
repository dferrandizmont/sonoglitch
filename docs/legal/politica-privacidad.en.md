# Privacy policy

*Last updated: 2026-11-20 · Applies to Sonoglitch (all versions).*

Sonoglitch is a camera app that distorts photos according to the sound level, the light and the movement around you. It is free, open source software and it works entirely on your device.

## What the app does with your data

| Data | Why | Where it goes |
| --- | --- | --- |
| Camera image | Live preview with the effect and taking the photo | Stays on your device. While you work on a photo, temporary files may exist in the app's private cache (no other app can read them) until the system clears it or you uninstall the app. Photos are saved to your gallery only when you tap Save. |
| Microphone | Only numbers are measured, in memory, to drive the effect: the **volume level** and the energy of **three frequency bands** (bass, mid, treble) | **No audio is recorded, stored or sent.** The microphone's audio buffers are processed in memory only to compute the volume and the three band energies and are then discarded; only the resulting numbers are kept, briefly. |
| Motion sensors (accelerometer and gyroscope) | Measure how much the phone moves and turns | Used in memory. Readings can appear in the local diagnostics log as plain numbers (see *Diagnostics*); never sent. |
| Image analysis | Brightness, how colourful the scene is, and the difference between consecutive small camera frames, computed to drive the effect | Used in memory. Brightness and movement readings can appear in the local diagnostics log as plain numbers; never sent. |
| Compass (magnetometer) and barometer | The direction the phone faces gives a small variation of the effect; the optional context line can also print the heading and the air pressure of a photo | Read in memory around the moment of the shot, never stored, logged or sent. The compass is approximate and magnetic; there is no location lookup. |
| Clock and calendar | The time of day, the date and the moon phase give a small variation of the effect; the optional context line (off by default) can print them on the exported picture | Computed in memory from the system clock. Only what you choose to export is written into the picture you save or share. |
| Photo gallery | Saves the photo you choose to save | Written to your gallery only when you tap Save. |

## What the app does not do

- It has no accounts, no ads, no analytics and no trackers.
- Release builds do not declare the Android `INTERNET` permission, so the app has no network access. (Debug and profile builds made by developers include it, as Flutter requires for its tooling.)
- On Android it asks for no storage permission: photos are saved through the system media store, and the app does not read other apps' files. On iOS the system asks for access to your photo library so the app can save into its own album.
- On Android, its data is excluded from device and cloud backups.
- It does not share data with anyone. When you tap Share, the photo is handed to the app you choose through the system share sheet; from then on that app's own privacy policy applies.

## Diagnostics

The app keeps a small text log in its private storage on your device: technical events, timings, errors and the numeric readings shown in the diagnostics panel (volume level, brightness, movement as plain numbers), plus the device model and Android version. It never contains audio or photos. It is shared only if you tap *Share logs* or *Copy report* and send it yourself. You can remove it by clearing the app's storage or uninstalling the app.

## Optional links

The GitHub releases show an optional "Support the project" link to a Ko-fi page; the Google Play build has none. Tapping it opens the link in another app on your device, normally your browser. Nothing is sent by the app itself, and the app does not know whether you donate.

## If you email us

The app sends nothing. The data controller is Daniel Mont Ferrandiz (DanielMF), Spain. If you write to [sonoglitch@mainshai.com](mailto:sonoglitch@mainshai.com), we use your email address, your name if you give it and what you tell us (including anything you attach, such as a diagnostics report) to answer you and deal with your question. If you exercise a data protection right, we process your request to meet our obligations under the GDPR (Art. 6(1)(c)). If we need to keep a conversation for a legal claim, we do so for as long as necessary for our legitimate interest in establishing, exercising or defending that claim (Art. 6(1)(f)). These providers take part along the way:

- **Cloudflare** (Cloudflare, Inc., United States) receives the message on our domain and forwards it at once. It does not keep the message, but it does keep a technical log of the forwarding (sender, recipient, subject, date and result). It keeps that log for the period its service sets; we have not been able to confirm that period or the options for deleting the log. If you ask us to delete your data, we will also pass the request on to Cloudflare and tell you the outcome. Cloudflare also processes the email in the United States.
- **Google** (Gmail; Google Ireland Limited) is the mailbox where we read your message, reply to you and keep the conversation. Google may also process this data in the United States.
- **Proton** (Proton AG, Switzerland) keeps a copy of the messages we receive, as a backup. We do not reply from there.
- **Resend** (Plus Five Five, Inc., United States) sends our replies, so it processes their content. It sends them from its servers in Ireland, but stores the data in the United States: a copy of each reply (which may include your message, if it is quoted below it) and a sending log (recipient, subject, date and whether it was delivered). Resend says it keeps each reply and its sending log for 30 days after sending, and it keeps backups for seven days. We have turned off open and click tracking: our replies carry no tracking image and their links are not changed. Resend uses its own sub-processors (for example, Amazon Web Services for sending), in the United States, listed at https://resend.com/legal/subprocessors. Resend processes the replies as a processor, under the data processing agreement (Art. 28 GDPR) that applies to all its accounts (https://resend.com/legal/dpa).

**Brevo, until 20 November 2026.** Until that date, this policy said that replies were sent through Brevo (Sendinblue SAS, trading as Brevo, France), which adds to emails an invisible image (a pixel) that records whether they are opened and replaces links with its own links that record whether they are tapped. Before the switch to Resend, the owner used Brevo only to send test emails from sonoglitch@mainshai.com, and no reply to anyone who wrote to us; those tests also carried an unsubscribe header, although there is no list. Brevo keeps the log of those tests and deletes it automatically twelve months after each email is sent (deletion can take up to another day). We will ask Brevo to delete that history sooner and we will close the account.

For ordinary enquiries, we rely on our legitimate interest in replying. We do not add your address to a mailing list. We keep the conversation in Gmail and the copy in Proton for at most one year from the last message of the conversation, unless we need to keep them longer to deal with a complaint or claim. We run a clean-up every three months, and each time we delete whatever would reach one year before the next one. Resend says it keeps each reply and its sending log for 30 days after sending, and it keeps backups for seven days. If you ask us to delete your messages sooner and the right to erasure applies, we delete the messages from Gmail and Proton and ask Resend to delete any replies and sending logs it still holds (this can only be done by asking its support team). If we need to keep any data, we will explain what we keep and why. For what remains at Brevo, see the previous paragraph.

Cloudflare, Google and Resend may process data in the United States. Cloudflare, Inc. and Google LLC take part in the EU-US Data Privacy Framework (adequacy decision of the European Commission of 10 July 2023); Cloudflare's data processing agreement also includes standard contractual clauses. Proton is in Switzerland, which has an adequacy decision from the European Commission. Resend (Plus Five Five, Inc.) stores the replies and their log in the United States, even though the emails are sent from Ireland; that transfer relies on Resend's participation in the EU-US Data Privacy Framework and on the European Commission's standard contractual clauses (module 2) included in its data processing agreement (https://resend.com/legal/dpa); you can also ask us for information at the contact email. Brevo, the intended sending service until 20 November 2026, is a French company and, according to its documentation, hosts the data in the European Union.

You can email sonoglitch@mainshai.com to access or correct your data, request erasure or restriction of processing, or object to processing based on our legitimate interests. You can also complain to the Spanish data protection authority (Agencia Española de Protección de Datos).

If you open an issue on GitHub, what you write is public and GitHub's privacy policy applies.

## Children

The app does not collect personal data from anyone, including children.

## Changes and contact

Changes to this policy will appear in this file and in the release notes. If you have questions, email [sonoglitch@mainshai.com](mailto:sonoglitch@mainshai.com) or [open an issue on GitHub](https://github.com/dferrandizmont/sonoglitch/issues).
