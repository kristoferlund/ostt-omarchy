# Sourced by the bin scripts.

# The error in ostt's stderr ($1): from its "Error: " line on, without the
# prefix and the "Caused by:" layout; its last line if there is none; or $2.
ostt_error() {
  local error
  error=$(sed -n '/^Error: /,$p' <<<"$1" |
    sed -e '1s/^Error: //' -e '/^Caused by:$/d' -e 's/^ *\([0-9]*: \)\{0,1\}//' -e '/^$/d')
  [[ $error ]] || error=$(grep -v '^[[:space:]]*$' <<<"$1" | tail -n1)
  error=${error:-${2:-}}
  (( ${#error} > 400 )) && error="${error:0:400}…"
  printf '%s' "$error"
}
