# Tweak for Telegram iOS

Кастомный твик для Telegram iOS с поддержкой джейлбрейка (Rootful / Rootless / RootHide) и инжекта в decrypted IPA (через TrollStore, Sideloadly, AltStore).

## Функционал

1. **Режим призрака (Ghost Mode):**
   - Скрытие онлайн-статуса (`kDisableOnlineStatus`)
   - Скрытие статусов набора текста, записи аудио/видео, загрузки файлов (`kDisableTypingStatus`, `kDisableRecordingVoiceStatus`, и др.)
2. **Отчёты о прочтении (Read Receipts):**
   - Отключение отправки статуса прочтения сообщений (`kDisableMessageReadReceipt`)
   - Отключение отметки о просмотре историй (`kDisableStoriesReadReceipt`)
3. **Разное (Miscellaneous):**
   - Отключение рекламы и спонсорских сообщений (`kDisableAllAds`)
   - Обход защиты от копирования и пересылки (`kDisableForwardRestriction`)
   - Отключение затемнения экрана при сворачивании и переключении приложений (`kDisableScreenBlackout`)
   - Разрешение скриншотов и записи экрана в защищённых каналах и секретных чатах (`kDisableScreenshotRestriction`)
4. **Фейковая геолокация (Fake Location / GPS Spoofing):**
   - Подмена реальных координат на любые выбранные на карте через интерактивный пикер
5. **Исправление выбора файлов (File Picker Fix):**
   - Исправление сбоя выбора файлов из приложения «Файлы» на sideloaded-версиях Telegram

## Активация меню настроек

Открыть панель настроек твика можно следующими способами:
1. **Зажатие пункта «Telegram FAQ» (или «Вопросы о Telegram»)** в настройках Telegram (длительное нажатие 0.5 сек).
2. **5 быстрых нажатий на вкладку «Чаты»** в нижней панели навигации (TabBar).
3. **Зажатие экрана тремя пальцами** (резервный жест).

## Сборка и автоматический инжект в IPA (GitHub Actions)

В репозитории настроен workflow `.github/workflows/build_and_inject.yml`:
1. Поместите ваш `Telegram.ipa` (или `Telegram.ios`) в папку `ipa/`.
2. Запустите GitHub Actions или сделайте пуш.
3. Workflow автоматически:
   - Соберёт твик под архитектуры ARM64/ARM64e через Theos.
   - Возьмёт файл из папки `ipa/` и выполнит инжект `Tweak.dylib` и `Tweak.bundle`.
   - Загрузит готовый `Telegram-Tweak.ipa` в артефакты сборки.
