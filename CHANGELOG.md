# Changelog: Monogram iOS

## [13.1.2-monogram] - 2026-10-30

### Ребрендинг
- Переименовано приложение в **Monogram** (`CFBundleDisplayName`, `CFBundleName`) в `Telegram/BUILD`, `en.lproj/InfoPlist.strings`, `ru.lproj/InfoPlist.strings`.
- Итоговый файл сборки в CI переименован в `Monogram.ipa`.

### Оптимизация под AltStore (Free Apple ID)
- Включен флаг `disableExtensions = True` по умолчанию в `Telegram/BUILD` (отключены все расширения: WatchApp, Widget, Share, Intents, BroadcastUpload, NotificationService), что позволяет подписывать приложение через бесплатный Apple ID в AltStore / Sideloadly без превышения лимита App ID.

### Призрачный режим (Ghost Mode)
- Создан модуль настроек `MonogramSettings.swift` (`TelegramCore`) с управлением статусами.
- Отключена отправка пакетов статуса онлайн (`ManagedAccountPresence.swift`).
- Отключена отправка индикатора набора текста (`ManagedLocalInputActivities.swift`).
- Отключена отправка отметок о прочтении сообщений на сервер (`SynchronizePeerReadState.swift`).
- Отключена отправка отметок о просмотре историй на сервер (`ManagedSynchronizeViewStoriesOperations.swift`).

### Защита от удаления и редактирования (Anti-Delete / Anti-Edit)
- Реализовано сохранение удалённых сообщений (`AccountStateManagementUtils.swift`): входящие удаленные сообщения не стираются из базы данных, оставаясь доступными для чтения.
- Реализовано сохранение оригинального текста при редактировании сообщений (`ServerMessageMerge.swift`): предыдущая версия текста сохраняется под пометкой `[Было: ...]`.

### CI / GitHub Actions
- Обновлен workflow `.github/workflows/build.yml` для сборки на `macos-15` (Apple Silicon runner).
- Добавлена безопасная подстановка `TELEGRAM_API_ID` и `TELEGRAM_API_HASH` из GitHub Secrets без коммита личных данных.
- Добавлена выгрузка готового артефакта `Monogram.ipa` через `actions/upload-artifact@v4` и релизов через `softprops/action-gh-release@v2`.
- Заменены относительные URL субмодулей `rlottie` и `tgcalls` на абсолютные для сборки в форке.
- Переключена иконка на `DefaultAppIcon` для совместимости сборщика `actool.bzl` с версиями Xcode 16+.
- Переподписаны тестовые provisioning профили (`.mobileprovision`) через ASN.1 PKCS#7 / CMS с продлением срока действия до 2030 года, устранив ошибку устаревания профилей в `rules_apple` `plisttool` и проверку OpenSSL S/MIME.



## Stage 1 (2026-10-31)
- Monogram settings screen (ghost mode, save deleted, keep original of edited)
- Deleted-message mark in bubble timestamp (MonogramDeletedMessageAttribute)
- App icon from MONOLITH DM logo (circular), backups in F:\Silentackup_20261031_1400

## Stage 2 (2026-10-31)
- Journal screen (deleted/edited/self-destructing media), edit-marker fix
- Confirm voice/video before sending, disable ads, local premium, remove bubble tail, custom deleted mark, save TTL media on open
- Hide stories row, custom edited mark, seconds in time, silent send in ghost mode, ghost suggestion before stories

## Stage 3
- Ghost: optional scheduled sending (useScheduledMessages), message filters (text and /regex/) with editor screen, hide premium statuses, show ID in profile, Google translator choice, hide app badge and chat counters, streamer mode (phone hidden in settings/profile).
- Not done: hiding the "All chats" folder (too risky for the folder tab bar).

- Fix: view-once/TTL media now saved from the viewer before consume (copy completes, then consume; 6s fallback).
