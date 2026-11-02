# Changelog: Monogram iOS

## 2026-11-02 (final21)
- Фейк-покупка коллекционного подарка с маркета: при включённом «Фейк-подарки по умолчанию» кнопка «Купить» на экране подарка ничего не покупает, а добавляет локальную запись «Покупка подарка» (подарок, продавец, цена, ID `stx…`) и уменьшает показываемый баланс (`GiftViewScreen.swift` `commitBuy` и общий `buyStarGiftImpl` в `GiftViewBuyGift.swift`, в том числе покупка с подарком другому человеку: в строке его настоящие аватарка и имя).

## 2026-11-02 (final20)
- Звёзды (локально): переключатель «Фейк-подарки по умолчанию»; включён — «Фейк-подарок» в экране отправки подарка стоит включённым сразу.
- Экран отправки подарка: переключатель «Фейк-подарок (Monogram)». Включён — подарок не отправляется и не списывается, в «Звёзды (локально)» появляется запись с получателем, стикером, текущим временем, ID `stx…`, баланс уменьшается (`GiftSetupScreen.swift`).
- Звёзды (локально): «Покупка уникального подарка» по ссылке t.me/nft/…: подарок загружается настоящий, строка «Покупка подарка» с ценой и продавцом (`kind` = `uniqueBuy`, флаг `isStarGiftResale`).
- Звёзды (локально): «Подарок из каталога» (список подарков с ценой; сумма, стикер и подпись «Подарок» подставляются сами), «Пополнение звёзд» (App Store или Premium Bot с иконкой и подписью как у настоящих). У обеих записей время по умолчанию текущее, ID сделки в виде `stx…` и баланс меняется сам (минус цена подарка, плюс пополнение). Запись хранит `kind`, `giftData`, `transactionId` (`MonogramLocalStars.swift`). Всё только на устройстве.

## 2026-11-02 (final19)
- Звёзды (локально): если у записи указан юзернейм, он даёт только аватарку; имя в строке всегда то, что вы ввели сами (у операции это подпись, у подписки её название), а настоящее имя и ник пользователя не подставляются.

## 2026-11-01 (final18)
- Оптимизация: все часто читаемые настройки Monogram (около 25 булевых и три метки сообщений) читаются из памяти, кэш сбрасывается по `UserDefaults.didChangeNotification`; список фильтров сообщений хранится в памяти (раньше читался из UserDefaults для каждого сообщения при каждом обновлении чата); фильтр Zalgo пропускает латиницу, греческий и кириллицу без поиска категории символа.
- Диагностика: копия журнала в iCloud Drive пишется пачками (раз в 30 секунд или сразу при важных событиях), чтобы не будить синхронизацию iCloud на каждую строку.

## 2026-11-01 (final17)
- Исправлено: «сохранять одноразовое медиа» больше не действует на собственные исходящие сообщения (`keepsSelfDestructingMedia(_:incoming:)`). Раньше у отправителя фото с таймером зависало на «0 с», а кружок и фото «на один просмотр» оставались как непросмотренные, хотя получатель сжёг их и отметка просмотра дошла до сервера.

## 2026-11-01 (final16)
- Журнал сжигания (категория `burn`): состояние сообщения до и после «Сжечь» (таймеры, «просмотрено», тип медиа) и результат отправки отметки просмотра на сервер (`MonogramBurn.swift`, `ManagedSynchronizeConsumeMessageContentsOperations.swift`, хук `monogramLogSink` подключён в `AppDelegate.swift`). Нужен, чтобы найти, почему у кружков собеседник не видит просмотр, а у фото с таймером собеседник видит «0 с».

## 2026-11-01 (final15)
- Режим призрака теперь у каждого аккаунта свой: `MonogramSettings.sends(_:accountId:)` / `setGhostModeActive(accountId:)`, ключи `monogram_ghost_<флаг>_<id аккаунта>`; пока для аккаунта ничего не выбрано, действует прежнее общее значение. Переключатель в настройках профиля, экран Monogram, история, отметки о прочтении, набор текста и онлайн читают значение своего аккаунта.
- Локальные звёзды: в операции и подписке можно указать юзернейм; пользователь находится через `resolvePeerByName`, и в списке показываются его настоящие аватарка и имя.

## 2026-11-01 (final14)
- Сожжённое медиа остаётся самоуничтожающимся в чате (размытая заглушка с меткой), а не разворачивается в полный размер: `containsSecretMedia` теперь учитывает `MonogramBurnedMessageAttribute` (`SyncCore_AutoremoveTimeoutMessageAttribute.swift`).
- Локальные звёзды (`MonogramLocalStars.swift`, `MonogramStarsController.swift`): свой показываемый баланс, свои операции и подписки отдельно для каждого аккаунта; подмена идёт в `Stars.swift` в `_internal_requestStarsState`, `_internal_requestStarsSubscriptions` и при серверных обновлениях баланса. Настройки Monogram → «Звёзды (локально)».

## 2026-11-01 (final10)
- Чат с Claude теперь обычный экран-чат: пузыри сообщений, поле ввода, кнопка фото, история хранится на устройстве; настройки (ключ, модель, усилие, очистка) вынесены на отдельный экран.
- Разгрузка CPU: часто читаемые настройки (`hidePremiumStatuses`, `localPremium`, `ignoreCopyProtection`, `disableAds`, `peekSelfDestructing`) кэшируются в памяти вместо чтения UserDefaults на каждый вызов; у строки Claude в списке чатов время больше не меняется при каждом обновлении.

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

- Исправлено: нажатие на строку Claude открывало пустой чат; теперь открывает экран ИИ (перехват в ChatListItem.selected).

## Диагностика
- Новый модуль MonogramDiagnostics и переключатель «Журнал нагрева, нагрузки и ошибок» (настройки Monogram, раздел «ДИАГНОСТИКА»). Пишет нагрев, CPU, память, батарею, зависания главного потока, исключения, действия и отчёты MetricKit в Documents/Logs (Файлы → На iPhone → Monogram) и копирует в папку архива.
- Исправлен порядок пунктов в разделе «ИИ» настроек.

## 2026-11-01 (диагностика CPU)
- CI: сборка кладёт dSYM и расшифровывает горячие адреса из отчёта MetricKit (tools/hot_frames.json) в лог шага "Symbolicate hot frames"; номер сборки зафиксирован файлом build_number_override (35380), чтобы бинарники совпали с final10.

## 2026-11-01 (расширенный журнал, final11)
- Журнал диагностики: при нагрузке выше 80% пишет по 3 снимка стеков самых горячих потоков в виде `Фреймворк+0xсмещение` (категория `hot`), таблицу бинарников с UUID (`image`), память с остатком до лимита и ростом МБ/с, стек главного потока при зависании, стеки при предупреждении о памяти.
- CI: dSYM шифруется и выгружается артефактом `Monogram-dSYM-enc` для расшифровки адресов из журнала.

## 2026-11-01 (final12)
- Нагрев и рост памяти: по расшифрованным стекам горячий цикл найден в `SynchronizePeerReadStatesContextImpl.update()` (ManagedSynchronizePeerReadStates.swift): операция синхронизации прочитанного перезапускалась мгновенно и бесконечно (при ошибке `.retry` и когда после завершения она оставалась в таблице), вместе с записью в Logger. Теперь перед повтором пауза 0.5 с с удвоением до 60 с.

## 2026-11-01 (final13)
- Экран Claude оформлен как обычный чат: обои чата из настроек, пузыри цветов темы со временем и галочкой, нижняя панель со скрепкой, овальным полем и круглой кнопкой отправки. Время сообщений сохраняется в истории.
