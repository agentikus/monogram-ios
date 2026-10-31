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

- Self-destructing media: viewing without burning (Burn button sends the read receipt), media is kept in chat instead of "expired" placeholder.

- Icon: whole artwork fits inside the circle. Local premium: own account reports isPremium everywhere (Peer.isPremium), not only in AccountContext.

- Icon: square artwork, MONOLITH DM text replaced by MONOGRAM (no circle).

- Icon text uses the original 28 Days Later font.

- Archive: per-chat folders (name, username, ID) with chat.txt log and media for deleted/edited/self-destructing content in Documents/Archive (visible in Files) + optional user-picked external folder mirror.

- Кнопка "Сохранить в галерею" при просмотре самоуничтожающегося фото/видео (копия также идёт в архив/выбранную папку).

- Настройка "Сохранять из защищённых чатов": снимает клиентский запрет копирования/сохранения (группы, секретные чаты).

- Снятие запрета копирования/сохранения на всех уровнях (peer, кэш пользователя, галерея, список сообщений, состояние чата).

- Скриншоты разрешены в секретных чатах и защищённых медиа; уведомление собеседнику о скриншоте не отправляется (настройка "Не сообщать о скриншотах").

- Файлы: UIFileSharingEnabled в InfoBazel.plist (папка Monogram на iPhone). "Сжечь" убирает медиа из чата (markBurned), кнопки в контекстном меню самоуничтожающихся сообщений, кнопки в просмотре выше. isLocalPremiumPeer без чтения UserDefaults для чужих пиров.

## ID в профиле
- Копирование ID: тап или долгое нажатие открывает меню "Скопировать" + тост "ID скопирован".

## Кружки и кнопки
- Убраны кнопки "Сохранить в галерею"/"Сжечь" с экрана просмотра; остались только в контекстном меню.
- "Сжечь" = отметить прочитанным и удалить сообщение локально (работает и для уже открытых кружков). Сохранение использует ссылку на сообщение.
- Самоуничтожающиеся медиа (в т.ч. кружки), оставленные для сохранения, больше не теряют атрибут таймера после просмотра: остаются в виде самоуничтожающихся.
- Воспроизведение входящего самоуничтожающегося кружка в режиме подглядывания не помечает его прочитанным (собеседник не видит сгорание).
- Сжечь кружок: сообщение остаётся в чате с заглушкой "истекшее видеосообщение"; фото/видео по-прежнему удаляются.
- Сжечь: сообщение (фото/видео/кружок) остаётся у тебя, собеседнику уходит отметка просмотра; на сообщении метка "🔥 уничтожено" у времени (MonogramBurnedMessageAttribute). Заглушка и удаление убраны.
- Иконки приложения: добавлена текущая иконка Monogram (MonogramIcon) и 12 иконок AyuGram (Ayu*), отрисованы из SVG/PNG AyuGram Desktop; круглые SVG вписаны в квадрат с фоном цвета края. Выбор в Настройки → Оформление → Иконка приложения.
- Расшифровка голосовых: по умолчанию на устройстве (SFSpeechRecognizer), добавлен NSSpeechRecognitionUsageDescription (без него iOS закрывал приложение), переключатель в настройках Monogram; убрано принудительное требование офлайн-распознавания.
- Переключатель режима призрака в Настройках (блок смены фото/цвета профиля).
- Метка сожжённого настраивается; новые пресеты меток удалено/изменено в стиле AyuGram.

## Партия: подтверждения, фоны, ИИ (локально, не запушено)
- Подтверждение отправки стикеров и гифок (ChatController.swift, ChatControllerMonogram.swift), настройка confirmStickersAndGifs.
- Отключение фонов/тем чата от собеседников (ChatControllerContentData.swift), disableCustomChatBackgrounds.
- Скрытие приветственного стикера (ChatEmptyNode.swift), hideGreetingSticker.
- Zalgo-фильтр (>3 диакритик подряд) и удаление BIDI-управляющих символов при отображении (StringWithAppliedEntities.swift), filterZalgo.
- Ссылки tg://chat?id= (OpenUrl.swift).
- Чат с Claude: свой ключ API, модель, усилие (MonogramClaudeController.swift, MonogramSettingsController.swift, MonogramSettings.swift).
- Ghost: «Не показывать печатает» уже подавляет все виды активности (запись, загрузка файла); подпись уточнена.
- Меню ID в профиле: «Копировать дату» заменено на «Скопировать ID» (PeerInfoScreenOpenMonogramId.swift).
- Claude-чат: настоящее усилие через output_config.effort (low/medium/high) вместо длины ответа; max_tokens 16000, таймаут 300 с; повтор без effort при 400; обработка refusal (MonogramClaudeController.swift). Сверено со справочником Claude API.
- Ключ Claude API перенесён в Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly), старое значение из UserDefaults мигрирует при первом чтении (MonogramSettings.swift).
- Откат: Gemini-провайдер убран (по просьбе пользователя), остался только Claude (коммит e9507a3b49).
- ИИ-чат: отправка фото (выбор из галереи, сжатие до 1568 px JPEG, base64 в блоке image; фото уходит только в последнем сообщении, в истории — пометка) (MonogramClaudeController.swift).
- Исправлена ошибка компиляции (незакрытая строка с переводом строки) в MonogramClaudeController.swift:252.
- ChatControllerMonogram.swift: добавлен import PresentationDataUtils (перегрузка textAlertController(context:...)).

## Чат Claude в списке чатов
- Закреплённая строка «Claude» в основном списке «Все чаты» (под архивом); нажатие открывает экран ИИ, свайпы/меню/выделение отключены.
- Превью последнего ответа и время в строке.
- Переключатель «Показывать чат Claude в списке чатов» в настройках Monogram (раздел ИИ).

## Шифрование артефакта
- Сборка шифрует IPA (AES-256, секрет ARTIFACT_PASSWORD), хранится только последний артефакт, публичный Release отключён.
