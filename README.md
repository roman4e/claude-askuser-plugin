# ask-user — Claude Code plugin

Нативні діалоги вибору для Claude Code на Linux. Коли Claude потребує підтвердження або вибору опції, плагін показує `zenity`-попап, якщо термінал не у фокусі. Якщо термінал у фокусі — Claude використовує вбудований `AskUserQuestion`.

Також додає `PreToolUse`-хук: коли Claude хоче виконати `Bash`/`Edit`/`Write` і термінал не у фокусі — спливає вікно Allow/Block.

## Що всередині

```
.
├── .claude-plugin/
│   └── plugin.json              # маніфест плагіна
├── hooks/
│   ├── hooks.json               # реєстрація PreToolUse-хука в плагіні
│   └── pre-tool-notify.sh       # сам хук (Allow/Block zenity-попап)
├── scripts/
│   └── ask.sh                   # діалог вибору (zenity або fallback)
├── skills/
│   └── choice-dialog/
│       └── SKILL.md             # інструкція для Claude як викликати ask.sh
└── install.sh                   # реєстрація плагіна + whitelist ask.sh
```

## Вимоги

- Linux з X11 або Wayland з XWayland
- `bash`, `python3`
- `zenity` — для GUI-попапів
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

## Перевірка

1. Запустіть Claude Code у терміналі.
2. Переключіться у браузер (термінал не у фокусі).
3. Попросіть Claude щось зробити, що потребує `Bash` (наприклад `ls -la`).
4. Має спливти `zenity`-вікно з Allow/Block.

Тест скрипта вибору вручну:

```bash
./scripts/ask.sh "Який варіант?" "A" "B" "C"
```

Якщо термінал не у фокусі — `zenity` зі списком. Якщо у фокусі — виведе `__USE_ASK_USER_QUESTION__` (сигнал для Claude використати вбудований `AskUserQuestion`).

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
| Дисплей є, термінал НЕ у фокусі | Нативне вікно `zenity` |

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
