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

# --- Fix missing i18n keys in adminDashboard (all languages) ---
# The admin dashboard component uses keys like adminDashboard.noWorkspace,
# adminDashboard.noWorkspaceDescription, adminDashboard.addNew but these
# are missing from the locale bundles. We inject them into the compiled
# locale chunk so $t() resolves them instead of showing raw key paths.
LOCALE_CHUNK=$(grep -rl 'adminDashboard:{title:"Dashboard"' "$WF/.nuxt/dist/client" 2>/dev/null | head -1)
if [ -n "$LOCALE_CHUNK" ]; then
  echo "Patching missing adminDashboard i18n keys in $(basename "$LOCALE_CHUNK")"
  # English: add missing keys after viewAll:"View all"
  sed -i 's/viewAll:"View all"}/viewAll:"View all",noWorkspace:"No workspace",noWorkspaceDescription:"Create a new workspace to get started",addNew:"Create workspace"}/g' "$LOCALE_CHUNK"
  # French
  sed -i 's/viewAll:"Consulter"}/viewAll:"Consulter",noWorkspace:"Aucun espace de travail",noWorkspaceDescription:"Créez un nouvel espace de travail pour commencer",addNew:"Créer un espace de travail"}/g' "$LOCALE_CHUNK"
  # Dutch
  sed -i 's/viewAll:"Alles bekijken"}/viewAll:"Alles bekijken",noWorkspace:"Geen werkruimte",noWorkspaceDescription:"Maak een nieuwe werkruimte aan om te beginnen",addNew:"Werkruimte aanmaken"}/g' "$LOCALE_CHUNK"
  # German
  sed -i 's/viewAll:"Alle anzeigen"}/viewAll:"Alle anzeigen",noWorkspace:"Kein Arbeitsbereich",noWorkspaceDescription:"Erstellen Sie einen neuen Arbeitsbereich",addNew:"Arbeitsbereich erstellen"}/g' "$LOCALE_CHUNK"
  # Spanish
  sed -i 's/viewAll:"Ver todo"}/viewAll:"Ver todo",noWorkspace:"Sin espacio de trabajo",noWorkspaceDescription:"Crea un nuevo espacio de trabajo para empezar",addNew:"Crear espacio de trabajo"}/g' "$LOCALE_CHUNK"
  # Fallback: any remaining language that still ends with viewAll:*}
  # Add English keys as fallback for untranslated languages
  sed -i 's/\(viewAll:"[^"]*"\)}/\1,noWorkspace:"No workspace",noWorkspaceDescription:"Create a new workspace to get started",addNew:"Create workspace"}/g' "$LOCALE_CHUNK"
fi

echo "ARTHA_REBRAND_DONE"
