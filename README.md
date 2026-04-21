# BBTalk

**Offline walkie-talkie** — internet gerek däl, diňe bir Wi-Fi ýeterlik.
Telefonlar şol bir ýerli ulgamda şifrelenen kanal arkaly bas-konuş ses iberýär.

> iOS & Android · Flutter · AES-256-GCM · UDP broadcast
> **Häzirki wersiýa: [v0.1.4](https://github.com/jumabayev/BBTalk/releases/tag/v0.1.4)**

## Android APK-ny ýüklemek

<table>
  <tr>
    <td align="center" width="220">
      <a href="https://github.com/jumabayev/BBTalk/releases/download/v0.1.4/bbtalk-v0.1.4.apk">
        <img src="qr-v0.1.4.png" width="200" alt="QR: BBTalk v0.1.4 APK-ny ýükle">
      </a>
      <br>
      <sub>Telefon kamerasy bilen okadyň</sub>
    </td>
    <td>
      <p><b>📥 Göni ýükleme salgysy:</b></p>
      <p><a href="https://github.com/jumabayev/BBTalk/releases/download/v0.1.4/bbtalk-v0.1.4.apk">bbtalk-v0.1.4.apk</a> (46 MB)</p>
      <p><b>🗂 Ähli wersiýalar:</b></p>
      <p><a href="https://github.com/jumabayev/BBTalk/releases">github.com/jumabayev/BBTalk/releases</a></p>
      <ol>
        <li>APK-ny ýükläp alyň</li>
        <li>Telefonda <i>"Näbelli çeşmelerden gurmak"</i> rugsadyny beriň</li>
        <li>APK-a basyp guruň — mikrofon rugsadyny beriň</li>
      </ol>
    </td>
  </tr>
</table>

## Aýratynlyklar

- 🔒 **Şifrelenen umumy kanal** — AES-256-GCM, açar kanal adyndan çykarylýar. Başga kanaldaky paketler awtomatiki ret edilýär.
- 📡 **Hesap ýa serwer ýok** — UDP LAN broadcast; kim hem bolsa şol kanaldadyr, biri-birini eşidýär.
- 🎙 **Bas-konuş** — uly düwme, çaga üçin-de amatly.
- 👤 **Kim gepleýän belli** — her paketde ugradyjynyň ady + avatar. Ekranda banner we düwme reňkinde görünýär.
- 🦸 **24 avatar preseti** — ilkinji işlenende random berilýär, sazlamalardan üýtgedip bolýar.
- 🔊 **16 kHz mono PCM16** — jetter-az, LAN üçin ýeterlik hil.

## Binagärlik

```
Mikrofon ──► PCM16 16kHz mono ──► AES-GCM şifrele ──► UDP :9001 ──► 255.255.255.255
                                                                           │
                                                                           ▼
Dynamik ◄── PCM16 ◄── AES-GCM aç (başarmasa ret et) ◄── UDP :9001 ◄── LAN
```

### Paket formaty

| ofset | uzynlyk | düşündiriş                                      |
|------:|--------:|--------------------------------------------------|
| 0     | 4       | magic `BBTK`                                     |
| 4     | 1       | version (=2)                                     |
| 5     | 1       | flags (bit0 = transmissiýa gutardy)              |
| 6–7   | 2       | seq (LE u16)                                     |
| 8–19  | 12      | AES-GCM nonce                                    |
| 20…   | N       | ciphertext (ahyrynda 16 baýt GCM tag)            |

Şifrelenen içerik:

| ofset        | düşündiriş                     |
|-------------:|---------------------------------|
| 0–15         | ugradyjynyň `userId` (16 baýt)  |
| 16           | ada uzynlyk (u8)                |
| 17…          | ady (UTF-8)                     |
| 17+nameLen   | avatar indeksi (u8)             |
| 18+nameLen…  | PCM16 LE, mono, 16 kHz          |

AAD = paketiň ilkinji 8 baýty (magic+version+flags+seq) — başlyk bilen oýnalsa tag geçmez.

Kanal açary: `key = SHA-256(utf8("<kanal>|BBTalk-v1"))`

## Fail düzümi

```
lib/
  main.dart                  — giriş
  audio_constants.dart       — paýlanýan sazlamalar (16kHz, 1024 B paket)
  models/
    avatars.dart             — 24 sany emoji+reňk preseti
  services/
    settings.dart            — kanal/userId/ad/avatar (SharedPreferences)
    channel_codec.dart       — AES-256-GCM şifrelemek/açmak
    udp_voice.dart           — UDP broadcast, kodirleme, ugradyjy filtr
    audio_capture.dart       — record paketi arkaly mik akymy
    audio_player.dart        — flutter_pcm_sound dynamige feed
  screens/
    ptt_screen.dart          — uly bas-konuş düwmesi, speaker banneri
    settings_screen.dart     — kanal / ad / avatar saýlaw
```

## Platforma sazlamalary

**Android** — [AndroidManifest.xml](android/app/src/main/AndroidManifest.xml):
`RECORD_AUDIO`, `INTERNET`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`,
`WAKE_LOCK`, `MODIFY_AUDIO_SETTINGS`, `usesCleartextTraffic=true`.

**iOS** — [Info.plist](ios/Runner/Info.plist):
- `NSMicrophoneUsageDescription`
- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` (`_bbtalk._udp`)
- `UIBackgroundModes: audio`

## Işletmek

```bash
flutter pub get
flutter run          # goşulan enjamda / emulýatorda
```

Iki sany enjam şol bir Wi-Fi-da bolmaly. Kanal ady deň bolsa biri-birini eşidýär;
başga kanaldakylar (meselem parolyny bilmeýänler) eşidip bilmeýär.

## Pes derejedäki saz

- **Ses formaty:** 16 kHz mono PCM16, ~32 KB/s
- **Paket ululygy:** iň köp 1024 B PCM + 36 B başlyk+nonce+tag (IP fragment ýok)
- **Codec:** MVP üçin PCM göni göýberilýär. Gerek bolsa Opus goşup bolar (`flutter_opus`, `opus_flutter`).

## Ses effektleri (v0.1.4)

Kanal boýunça ugradyjy tarapda hakyky-wagtly DSP bilen sesi üýtgedip bolýar:

| emoji | ady        | tehnikasy                                     |
|:-----:|------------|-----------------------------------------------|
| 🎤    | Hiç        | (asyl ses)                                    |
| 🤖    | Robot      | 100 Hz ring modulator                         |
| 👽    | Kosmos     | Ring-mod 55 Hz + 4.5 Hz tremolo               |
| 🎭    | Eho        | 220 ms delay + 38% feedback + 55% wet         |
| 📢    | Megafon    | Soft clip drive + ~500 Hz highpass            |
| 📻    | Stansiýa   | 350–3000 Hz bandpass + ýumşak drive           |
| 💾    | Döwük      | 6-bit kwantizator (pes kompýuter sesi)        |

Saýlaw: Sazlamalar → Ses effekti. Effekt mikrofon bilen paket iberiläninden öň
ulanylýar — beýleki taraplar eýýäm üýtgedilen sesi eşidýär. Şifrelemesi, seq
tertibi, jitter buferi — barysy öňki ýaly işleýär.

## Edilenler (v0.1.4-e çenli)

- ✅ LAN discovery — presence heartbeat (2 s aralyk, 12 s timeout) + täze
  peer-a bada-bat jogap
- ✅ Per-ugradyjy jitter buferi — paketler `seq` boýunça tertipläp berilýär,
  60 ms-e çenli ýitik pakede garaşyp soň seksen geçilýär
- ✅ Seq-esasly duplikat/gijik filtri — gaýtalanan ýa eýýäm geçilen paket
  buferiň girişinde ret edilýär
- ✅ Half-duplex gulp — başgasy gepläňde düwme sessiz ret edilýär
- ✅ Subnet broadcast (x.x.x.255) — bir ugradyjy-ähli-eşidýän mehanizm
- ✅ Šifrelenen umumy kanal (AES-256-GCM, açar = SHA-256(channel))

## Mümkin ösüşler

- **Opus codec** — `flutter_opus`/`opus_flutter` bilen ses göwrümini
  ~10× kiçeltmek we ýitik pakete garşy içerki concealment gazanmak.
  Native baglylyk getirer, diňe gowy synalandan soň goşulsa bolar.
- **Dinamik ugur** — iOS-da `playAndRecord` awtomatiki earpiece-e geçýär;
  ses güýçli dynamige awdirmek üçin AVAudioSession seta goşmaça patch
  gerek.
- **Kanal paroly aýrylyk "işleýiş kody"** — häzir kanal ady = parol.
  Iki aýratyn meýdan (kanal + parol) bölünmek bilen UX hasam gowy bolar.
- **PTT kilit toggle** — bir gezek basyp elini goýberip ýene basýança
  gepleýän rejim (awariýa ýa uzyn ulanyşda amatly).

## Litsenziýa

Hususy / okuw maksatly. Goşulan paket litsenziýalary öz paketleriniňkidir.
