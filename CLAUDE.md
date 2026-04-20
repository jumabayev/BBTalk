# CLAUDE.md

Claude Code bilen BBTalk repozitoriýasynda işleýän wagtyňda bu faýly okap başla.

## Proýektiň bir setirde manysy

Internet bolmaýan bas-konuş: iki/birnäçe telefon şol bir Wi-Fi-da, şifrelenen kanal üsti bilen UDP broadcast arkaly ses iberişýär. Hesap ýok, serwer ýok.

## Esasy kararlar we näme üçin

- **UDP broadcast 255.255.255.255** (peer IP däl) — ulanyjy el bilen IP ýazmaly däl; şol kanaldaky her kim awtomatiki eşidýär.
- **iOS üçin multicast däl, broadcast** — multicast Apple-dan `com.apple.developer.networking.multicast` entitlement talap edýär (diňe arza boýunça berilýär). `255.255.255.255` broadcast bu entitlement talap edenok.
- **AES-256-GCM per-paket** — kanal ady açar derewine çalşyrylýar (`SHA-256(channel + "|BBTalk-v1")`). Başga kanaldan gelen paket GCM tag barlagyndan geçmän sessiz taşlanýar → privacy + filtrasiýa bir ädimde.
- **AAD = paketiň başlygy (magic+version+flags+seq)** — başlyk açyk gidýär, ýöne üýtgedilse tag geçmez.
- **`reusePort: true`** (POSIX-de) — Android-de hot-reload-dan soň `errno=98 EADDRINUSE` ýalňyşynyň öňüni alýar.
- **Öz userId filtri** — paketdäki ugradyjynyň `userId` biziňki bolsa ret edilýär (öz sesimizi eşidemizok).
- **PCM16 LE, 16 kHz mono** — LAN üçin bant-ini 32 KB/s, Opus-y gurnamazdan MVP-ä ýeterlik.
- **Paket çägi 1024 B PCM + 36 B başlyk** — MTU-dan örän pes, IP fragment ýok.

## Ses/tor akymy

```
mikrofon (record paketi, pcm16bits stream)
   ↓
udp_voice.sendVoice(): plaintext = userId+name+avatarIdx+pcm
   ↓  AES-GCM encrypt, header = AAD
   ↓  UDP → 255.255.255.255:9001
── WiFi ──
   ↓  UDP :9001
   ↓  decrypt (wrong channel → drop)
   ↓  selfUserId filter
   ↓  IncomingVoice → StreamController
   ↓
audio_player.feedPcm() → flutter_pcm_sound
   ↓  dynamik
```

## Fail düzümi

| ýol                                    | borjy                                           |
|----------------------------------------|-------------------------------------------------|
| `lib/audio_constants.dart`             | sample-rate, paket çäkleri, magic baýtlar       |
| `lib/models/avatars.dart`              | 24 sany emoji+reňk avatar                       |
| `lib/services/settings.dart`           | SharedPreferences model (channel, userId, ...)  |
| `lib/services/channel_codec.dart`      | AES-256-GCM encrypt/decrypt wrapper             |
| `lib/services/udp_voice.dart`          | RawDatagramSocket, paket format, broadcast      |
| `lib/services/audio_capture.dart`      | `record` paketi → PCM stream                    |
| `lib/services/audio_player.dart`       | `flutter_pcm_sound` → dynamige feed             |
| `lib/screens/ptt_screen.dart`          | esasy UI — uly düwme, speaker banneri           |
| `lib/screens/settings_screen.dart`     | kanal/ad/avatar saýlaw                          |
| `android/app/src/main/AndroidManifest.xml` | mikrofon+tor rugsatlary                     |
| `ios/Runner/Info.plist`                | NSMicrophone + NSLocalNetwork + Bonjour         |

## Derwaýys daşarky paketler

- `record: ^6.1.1` — streaming PCM16 mikrofony. API: `AudioRecorder().startStream(RecordConfig(...))` → `Stream<Uint8List>`.
- `flutter_pcm_sound: ^3.3.3` — streaming PCM dynamige. API: `setup(sampleRate, channelCount)`, `feed(PcmArrayInt16)`, `start()`. iOS audio category **`playAndRecord`** hökman — ýogsam mikrofon bilen konflikt.
- `cryptography: ^2.7.0` — arassa Dart AES-GCM.
- `permission_handler: ^12.0.0` — mik rugsady.
- `network_info_plus: ^6.0.0` — öz WiFi IP-ni göstermek üçin.
- `wakelock_plus: ^1.2.11` — ulanyş mahaly ekran ölmesin.
- `shared_preferences: ^2.3.3` — sazlama persistans.

## Adaty ädimler

```bash
flutter pub get
flutter analyze            # PR-dan öň hökman arassa bolmaly
flutter run                # goşulan enjamda ýa emulýatorda
```

Android studio/iOS Xcode taraplary özbaşdak seljerilýär — bu repo diňe Dart + platforma konfigurasiýasyny öz içine alýar.

## Şol giňelişde seresap bolmaly ýerler

- **Nonce täsiri:** AES-GCM-de nonce gaýtalanmaly däl. Biz `Random.secure()` bilen 12 baýt random döredýäris; 30 pkt/s-da kollision ~2^48 paketde → howp ýok. Ýöne täze codec goşulsa şol kepili saklamaly.
- **endian:** `record` host-endian PCM16 berýär, `flutter_pcm_sound` hem host-endian garaşýar. Android/iOS arm64/x86-64 = LE, şonuň üçin göni geçirýäris. Başga arhitekturada bu çalşyrylmaly.
- **Hot reload & socket:** `reusePort: true` bolmasa Android-de bind ýalňyş gaýtalanýar. Dispose() çagyrylmasa hem täze bind işlär.
- **Öz echo:** `selfUserId` filtrini ýatdan çykarma; ýogsam ulanyjy öz sesini kem-azajyk gijä galyp eşider.
- **iOS multicast:** multicast goşmakçy bolsaň, entitlement derkar. Broadcast-da galsaň — hiç zat goşmaly däl.
- **Opus goşmak:** `flutter_opus` / `opus_flutter` — encode + decode dinatiw bolar; paket formaty `version` baýtyny 3-e çykaryp goşup bolar.

## Stil ileri tutmalary

- Kod düşündirişlerini türkmenmençe ýazýarys (esasy faýllarda görersin). Täze kod goşanyňda şol stili dowam etdiriň.
- Analyzer-siz PR ýok. `flutter analyze` → `No issues found!` hökman.
- UI-tekstler türkmençe (diňlemek üçin çaga hem ulanýar).
- Gerek däl paket gurnama. MVP diňe LAN ses — täze paket goşmakçy bolsaň ýagdaýyny delillendir.

## Hem bolsa

- LAN discovery (UDP "HELLO" broadcast) → enjam sanawy
- Opus codec → bant-inini ~10× azaltmak
- Ýönekeý jetter-buffer (häzir feed göni akýar)
- Duplicate paket filtri (seq boýunça)
