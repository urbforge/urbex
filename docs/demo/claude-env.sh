# Sourced, hidden, by claude.tape after demo-env.sh: Claude Code's
# settings and login for the recording (record.sh puts them in
# claude-home), and bin/ first on the PATH - the urbex and curl Claude
# runs show what the GIF may show.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export CLAUDE_CONFIG_DIR=$here/claude-home DISABLE_AUTOUPDATER=1
export PATH=$here/bin:$PATH
# A token from 'claude setup-token', if record.sh was given one: read,
# then deleted.
if [ -f "$CLAUDE_CONFIG_DIR/oauth-token" ]; then
  CLAUDE_CODE_OAUTH_TOKEN=$(cat "$CLAUDE_CONFIG_DIR/oauth-token")
  export CLAUDE_CODE_OAUTH_TOKEN
  rm -f "$CLAUDE_CONFIG_DIR/oauth-token"
fi
rm -f /tmp/claude-demo-state
