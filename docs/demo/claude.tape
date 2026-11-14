# The README's second GIF: the same flow as readme.tape, asked of Claude
# Code with Urbex's plugin - deploy to staging, release and promote
# (Claude asks first), what runs where. Run it with record.sh (see
# README.md). Claude works hidden; the status line says when it waits for
# the user ("● ready", set by the hooks in claude/settings.json), and the
# recording shows each answer. /clear, hidden, starts each request on a
# clean screen.

Output claude.gif

Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 20
Set Width 1240
Set Height 760
Set Padding 24
Set TypingSpeed 35ms
Set Theme "Catppuccin Mocha"
Set WaitTimeout 25m

Hide
Type "source /work/demo/demo-env.sh && source /work/demo/claude-env.sh && cd /work/demo/app && clear" Enter
Sleep 1s
Type "claude --plugin-dir /work/demo/plugin" Enter
Wait+Screen@3m /● ready/
Sleep 2s
Type "/clear" Enter
Sleep 2s
Show

Type "deploy this app to staging" Sleep 400ms Enter
Sleep 3s
Hide
Wait+Screen /● ready/
Show
Sleep 6s

Hide
Type "/clear" Enter
Sleep 2s
Show
Type "release it and promote it to production" Sleep 400ms Enter
Sleep 3s
Hide
Wait+Screen /● ready/
Show
Sleep 4s
Type "yes" Sleep 400ms Enter
Sleep 3s
Hide
Wait+Screen /● ready/
Show
Sleep 6s

Hide
Type "/clear" Enter
Sleep 2s
Show
Type "what runs where?" Sleep 400ms Enter
Sleep 3s
Hide
Wait+Screen /● ready/
Show
Sleep 7s
