# ask-user — Claude Code plugin

Нативні діалоги вибору для Claude Code на Linux. Коли Claude потребує підтвердження або вибору опції, плагін показує системне сповіщення з кнопками, якщо термінал не у фокусі. Якщо термінал у фокусі — Claude використовує вбудований `AskUserQuestion`.

Також додає `PreToolUse`-хук: коли Claude хоче виконати `Bash`/`Edit`/`Write` і термінал не у фокусі — спливає сповіщення Allow/Block.

Бекенд перемикається у конфізі: `notify` (сповіщення з кнопками, за замовчуванням) або `zenity` (класичне вікно).

## Що всередині

```
.
├── .claude-plugin/
│   └── plugin.json              # маніфест плагіна
├── hooks/
│   ├── hooks.json               # реєстрація PreToolUse + SessionStart хуків
│   ├── pre-tool-notify.sh       # PreToolUse: Allow/Block попап
│   └── migrate-legacy.sh        # SessionStart: чистить залишки від старих версій
├── lib/
│   ├── config.sh                # читання ~/.claude/ask-user.conf + env
│   ├── ui.sh                    # бекенди діалогів: notify (D-Bus) та zenity
│   └── focus.sh                 # детекція фокусу вкладки термінала
├── scripts/
│   └── ask.sh                   # діалог вибору (notify/zenity або fallback)
├── skills/
│   └── choice-dialog/
│       └── SKILL.md             # інструкція для Claude як викликати ask.sh
├── tests/
│   ├── test-ui.sh               # автотести чистої логіки (без GUI)
│   └── manual-ui.sh             # інтерактивна перевірка діалогів
├── ask-user.conf.example        # приклад конфігу
└── install.sh                   # реєстрація плагіна + whitelist ask.sh
```

## Вимоги

- Linux з X11 або Wayland з XWayland
- `bash`, `python3`
- `gdbus` (пакет `glib2` / `libglib2.0-bin`) — для бекенда `notify`; зазвичай вже стоїть
- сповіщувач з підтримкою кнопок (`actions`): GNOME, Cinnamon, KDE, dunst, mako
- `zenity` — для бекенда `zenity` і як автоматичний фолбек
- `xdotool` — для детекції фокусу вікна (скрипт сам спробує доставити через apt/dnf/pacman)
- Claude Code CLI

Встановити залежності вручну:

```bash
# Debian/Ubuntu
sudo apt-get install -y zenity xdotool

# Fedora
sudo dnf install -y zenity xdotool

# Arch
sudo pacman -S --noconfirm zenity xdotool
```

## Установка

```bash
git clone https://github.com/<you>/ask-user.git
cd ask-user
bash install.sh
```

Скрипт `install.sh`:

1. Реєструє плагін у `~/.claude/plugins/installed_plugins.json` як `ask-user@local`, із посиланням на поточну директорію.
2. Додає `Bash(<repo>/scripts/ask.sh *)` у `permissions.allow`.
3. Вмикає плагін у `enabledPlugins`.
4. Якщо на машині є легасі-хук з попередніх версій (`~/.claude/hooks/pre-tool-notify.sh` + запис у `settings.json`) — видаляє.

PreToolUse-хук **живе всередині плагіна** (`hooks/hooks.json` + `hooks/pre-tool-notify.sh`). Claude Code завантажує його разом із плагіном. Коли плагін вимкнено через `/plugin` — хук теж вимикається автоматично.

Після установки перезапустіть Claude Code.

### Оновлення зі старих версій

Плагін підтримує SessionStart-міграцію: `hooks/migrate-legacy.sh` перевіряє наявність залишків від попередніх версій (`~/.claude/hooks/pre-tool-notify.sh` та відповідний запис у `~/.claude/settings.json.hooks.PreToolUse`) і чистить їх. Fast-path: якщо чистити нема чого — вихід за ~5мс.

Тобто якщо ти встановиш нову версію через marketplace/git pull і перезапустиш Claude Code, легасі приберуться самі на першій сесії. Ручний `install.sh` перезапускати не обов'язково.

## Налаштування

Конфіг: `~/.claude/ask-user.conf` (приклад — `ask-user.conf.example` у репозиторії). Кожен ключ можна також задати змінною оточення, вона має пріоритет над файлом. Файл парситься через `grep`, а не `source` — випадковий рядок у ньому не виконає код усередині permission-хука.

| Ключ | Дефолт | Що робить |
|------|--------|-----------|
| `ASK_USER_UI` | `notify` | Бекенд: `notify` (сповіщення з кнопками) або `zenity` (вікно) |
| `ASK_USER_TIMEOUT` | `300` | Скільки секунд чекати відповідь; `0` — чекати вічно |
| `ASK_USER_BTN_PAD` | `6` | Скільки em-пробілів додати з кожного боку номера на кнопці |
| `ASK_USER_MAX_LABEL` | `10` | Найдовший текст опції, який ще пишеться прямо на кнопці |

### Як виглядають кнопки

Сповіщувачі жорстко обрізають підписи кнопок — cinnamon ріже приблизно до одного слова. Тому опції рендеряться по-різному:

- опція коротша за `ASK_USER_MAX_LABEL` → її текст іде прямо на кнопку (`Yes`, `No`, `Cancel`);
- довша → на кнопці номер, а повний текст списком у тілі сповіщення.

В одному діалозі режими змішуються: три довгі варіанти й `Cancel` дадуть кнопки `1` `2` `3` `Cancel`. Номер обгортається em-пробілами (`ASK_USER_BTN_PAD`), бо кнопка з однією цифрою виходить надто вузькою, щоб у неї зручно було влучити.

### Чому D-Bus, а не notify-send

Бекенд `notify` говорить з `org.freedesktop.Notifications` напряму через `gdbus`. У `notify-send` з `--action` stdout буферизується до кліку, тому `--print-id` не встигає віддати ідентифікатор — і якщо очікування впирається в таймаут, сповіщення лишається висіти на екрані, а закрити його нічим. Прямий виклик віддає id одразу, тож таймаут прибирає сповіщення за собою. Бонус: знімається вимога libnotify >= 0.8.

Якщо сесійної шини нема, `gdbus` відсутній або сповіщувач не заявляє capability `actions` — плагін мовчки перемикається на `zenity`.

## Перевірка

1. Запустіть Claude Code у терміналі.
2. Переключіться у браузер (термінал не у фокусі).
3. Попросіть Claude щось зробити, що потребує `Bash` (наприклад `ls -la`).
4. Має спливти сповіщення з кнопками Allow/Block.

Тести:

```bash
bash tests/test-ui.sh                      # автотести логіки, GUI не потрібен
bash tests/manual-ui.sh all                # інтерактивна перевірка діалогів
ASK_USER_UI=zenity bash tests/manual-ui.sh all
```

Тест скрипта вибору вручну:

```bash
./scripts/ask.sh "Який варіант?" "A" "B" "C"
```

Якщо термінал не у фокусі — сповіщення з кнопками. Якщо у фокусі — виведе `__USE_ASK_USER_QUESTION__` (сигнал для Claude використати вбудований `AskUserQuestion`).

## Як Claude використовує плагін

Скіл `choice-dialog` інструктує Claude викликати:

```bash
RESULT=$("${CLAUDE_PLUGIN_ROOT}/scripts/ask.sh" "Питання?" "Опція A" "Опція B")
if [ "$RESULT" = "__USE_ASK_USER_QUESTION__" ]; then
    # Claude викликає AskUserQuestion з тими ж опціями
else
    echo "Вибрано: $RESULT"
fi
```

Прапор `--delay N` корисний для довгих операцій: захоплює tab ID одразу, потім чекає `N` секунд, лише тоді перевіряє фокус.

## Поведінка ask.sh

| Умова | Метод |
|-------|-------|
| **Remote Control активний** (`CLAUDE_CODE_REMOTE` truthy або `CLAUDE_CODE_REMOTE_SESSION_ID` встановлений) | Fallback: `__USE_ASK_USER_QUESTION__` — питання передається на віддалений пристрій нативно |
| Немає `$DISPLAY` | Fallback: `__USE_ASK_USER_QUESTION__` |
| Дисплей є, термінал у фокусі | Fallback: `__USE_ASK_USER_QUESTION__` |
| Дисплей є, термінал НЕ у фокусі | Сповіщення з кнопками (або вікно `zenity`, залежно від `ASK_USER_UI`) |
| Діалог закрито без відповіді або вичерпано таймаут | Fallback: `__USE_ASK_USER_QUESTION__` — питання переїжджає у термінал, нічого не губиться |

### Remote Control bypass

Коли Claude Code запущено з `--remote-control` / `--rc` (керування з телефона або десктоп-додатку), плагін **не перехоплює** ні питання, ні permission-промпти:

- `scripts/ask.sh` одразу повертає `__USE_ASK_USER_QUESTION__` — Claude викликає вбудований `AskUserQuestion`, який Claude Code сам доставляє на віддалений пристрій.
- `pre-tool-notify.sh` виходить з `exit 0` — Claude використовує стандартний permission-flow, який також системно передається на пристрій.

Детекція через env vars що Claude Code експортує у дочірні процеси:

- `CLAUDE_CODE_REMOTE` — truthy значення (`1`, `true`, `yes`, `on`)
- `CLAUDE_CODE_REMOTE_SESSION_ID` — будь-яке непорожнє значення

Для детекції правильного вікна термінала скрипт іде вверх по `/proc` від свого PID, шукає процес термінального емулятора (gnome-terminal, konsole, alacritty, kitty, wezterm, tilix, terminator, foot, rxvt, xterm), потім через `xdotool search --pid` отримує його X-вікна. Це коректно працює навіть коли користувач вже у іншій програмі на момент старту скрипта.

## Вимкнення та видалення

**Тимчасово вимкнути** — команда `/plugin` у Claude Code, вибрати `ask-user@local` → Disable. Хук та `ask.sh` перестають діяти, бо є частиною плагіна.

**Повне видалення** вручну:

```bash
# З settings.json прибрати:
#   - permissions.allow: запис "Bash(<repo>/scripts/ask.sh *)"
#   - enabledPlugins: "ask-user@local"
# З installed_plugins.json прибрати "ask-user@local"
```

## Ліцензія

MIT
