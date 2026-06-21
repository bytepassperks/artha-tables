#!/bin/bash
# Artha Tables rebrand of the Baserow all-in-one image (build-time, idempotent).
# Visible brand = logo image + favicon + browser title. Body-text help strings
# that mention the upstream name are left untouched (changing them risks breaking
# internal identifiers/URLs); they are not part of the chrome a user sees.
set -e
A=/tmp/artha
WF=/baserow/web-frontend

# --- Logos: source static + served (content-hashed) copies ---
for n in logo logoOnly logo-white; do
  cp "$A/logo.svg" "$WF/modules/core/static/img/$n.svg" 2>/dev/null || true
done
for n in logo logoOnly logo-white; do
  for f in "$WF"/.nuxt/dist/client/img/$n.*.svg; do
    [ -e "$f" ] && cp "$A/logo.svg" "$f"
  done
done

# --- Favicons: source static + served (content-hashed) copies ---
for sz in 16 32 48 192; do
  cp "$A/fav$sz.png" "$WF/modules/core/static/img/favicon_$sz.png" 2>/dev/null || true
  for f in "$WF"/.nuxt/dist/client/img/favicon_$sz.*.png; do
    [ -e "$f" ] && cp "$A/fav$sz.png" "$f"
  done
done

# --- Browser tab title in the built bundles (targeted, safe) ---
grep -rl 'Baserow' "$WF/.nuxt/dist" 2>/dev/null | while read -r f; do
  sed -i 's/%s | Baserow/%s | Artha Tables/g; s/"title":"Baserow"/"title":"Artha Tables"/g' "$f"
done

# --- Visible UI strings: rebrand the i18n locale message bundles only ---
# The locale bundles are pure translation values (all languages); rebranding the
# standalone word "Baserow" there is safe. We DELIBERATELY do not touch the app
# logic bundles, where "Baserow" appears inside code identifiers (BaserowFormula,
# BaserowAdmin, ...) that must not change. We anchor on a marker string that only
# the message bundle contains.
for d in "$WF/.nuxt/dist/client" "$WF/.nuxt/dist/server"; do
  for f in $(grep -rl 'Welcome to Baserow' "$d" 2>/dev/null); do
    # whole-word only: leaves "BaserowFormula"/"baserow.io" untouched
    sed -i 's/\bBaserow\b/Artha Tables/g' "$f"
  done
done

echo "ARTHA_REBRAND_DONE"
