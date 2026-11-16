# The README's GIF: the app side of Urbex's flow on a platform that is
# already there - apply staging, open it, release, promote, status. Run
# it with record.sh, which says what it needs. The waits are cut: the
# commands run hidden, and the recording shows how each one ends. The
# addresses are typed with example.com in place of the platform's domain
# (flat hostnames: <name>-urbex.<domain>); demo-env.sh's curl asks the
# real one.

Output readme.gif

Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 20
Set Width 1240
Set Height 760
Set Padding 24
Set TypingSpeed 35ms
Set Theme "Catppuccin Mocha"
Set WaitTimeout 20m

Hide
Type "source /work/demo/demo-env.sh && cd /work/demo/app && clear" Enter
Sleep 1s
Show

# Staging: the LXCs, Komodo, the build of main, the deploy.
Type "urbex apply staging" Sleep 400ms Enter
Sleep 1.5s
Hide
Wait
Show
Sleep 3s

Type "curl https://web-staging-demo-urbex.example.com" Sleep 400ms Enter
Wait
Sleep 2.5s

# A release of what staging runs, then the same images in production.
Hide
Type "clear" Enter
Show
Type "urbex release" Sleep 400ms Enter
Hide
Wait
Show
Sleep 3s

Hide
Type "clear" Enter
Show
Type "urbex promote" Sleep 400ms Enter
Hide
Wait
Show
Sleep 3s

Type "curl https://web-demo-urbex.example.com" Sleep 400ms Enter
Wait
Sleep 2s

Hide
Type "clear" Enter
Show
Type "urbex status" Sleep 400ms Enter
Wait
Sleep 4s
