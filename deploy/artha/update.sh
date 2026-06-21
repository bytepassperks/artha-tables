#!/usr/bin/env bash
# Universal Artha gated auto-update pipeline.
#
# One script, shared verbatim across every Artha module fork. All per-module
# specifics live in deploy/artha/deploy.conf next to this file. The pipeline is
# GATED: it only deploys when the next upstream is proven safe (clean trial-merge
# + Artha rebrand intact). On any conflict or branding drift it STOPS LOUDLY and
# never touches production.
#
# Two update models (set UPDATE_MODEL in deploy.conf):
#   source   fork tracks an upstream git branch; new commits are merged in with
#            the thin Artha white-label layer preserved, assets rebuilt, and the
#            tree shipped to Scalingo as a deploy archive (or via git push).
#   release  fork repackages a published upstream binary/slug (e.g. Metabase jar,
#            Mattermost slug). The gate checks whether upstream cut a newer stable
#            release than the recorded one; the actual repackage+deploy is done by
#            deploy/artha/release-deploy.sh (kept per-module because the artifact
#            shape differs). If that hook is absent the run opens an issue instead
#            of deploying — a human bumps the pin. Production is never touched.
#
# Flags:
#   --dry-run   resolve + trial-merge (or release check) + rebrand assertions only
#   --force     proceed even if the recorded upstream is unchanged
#
# Required env:
#   GH_TOKEN              GitHub token with push access to the fork
#   SCALINGO_API_TOKEN    only for a real (non-dry-run) deploy
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

[ -f "$HERE/deploy.conf" ] || { echo "!! deploy/artha/deploy.conf missing" >&2; exit 1; }
# shellcheck disable=SC1090
. "$HERE/deploy.conf"

: "${UPDATE_MODEL:=source}"
: "${UPSTREAM_REMOTE:=upstream}"
: "${SCALINGO_REGION:=osc-fr1}"
: "${DEPLOY_METHOD:=archive}"
: "${VERIFY_PATH:=/}"
VERSION_FILE="$HERE/VERSION"

DRY_RUN=0; FORCE=0

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf '\n !  %s\n' "$*" >&2; }
die()  { printf '\n !! %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *)         die "unknown flag: $1" ;;
  esac
  shift
done

[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is required (push access to the fork)."

# Make sure pushes use the token even on a fresh runner checkout.
configure_push_auth() {
  local url; url="$(git remote get-url origin)"
  case "$url" in
    https://*)
      local host_path="${url#https://}"
      host_path="${host_path#*@}"
      git remote set-url origin "https://x-access-token:${GH_TOKEN}@${host_path}"
      ;;
  esac
  git config user.name  "artha-auto-update[bot]" 2>/dev/null || true
  git config user.email "artha-auto-update[bot]@users.noreply.github.com" 2>/dev/null || true
}

verify_live() {
  log "Verifying live app at $LIVE_URL$VERIFY_PATH"
  local ok=0 code
  for _ in $(seq 1 30); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "$LIVE_URL$VERIFY_PATH" || true)"
    if [ "$code" = "200" ] && { [ -z "${EXPECTED_TOKEN:-}" ] || curl -s "$LIVE_URL$VERIFY_PATH" | grep -qF "$EXPECTED_TOKEN"; }; then
      ok=1; break
    fi
    sleep 10
  done
  [ "$ok" -eq 1 ] || die "post-deploy verification failed: $LIVE_URL$VERIFY_PATH not HTTP 200 with '${EXPECTED_TOKEN:-}'."
  log "live: HTTP 200${EXPECTED_TOKEN:+ + '$EXPECTED_TOKEN' present}."
}

scalingo_login() {
  [ -n "${SCALINGO_API_TOKEN:-}" ] || die "SCALINGO_API_TOKEN is required for deploy."
  export SCALINGO_REGION
  scalingo login --api-token "$SCALINGO_API_TOKEN" >/dev/null
}

# ══════════════════════════════════════════════════════════════════════════════
# RELEASE MODEL  (binary/slug apps: Metabase, Mattermost, ...)
# ══════════════════════════════════════════════════════════════════════════════
if [ "$UPDATE_MODEL" = "release" ]; then
  [ -n "${UPSTREAM_REPO:-}" ] || die "UPSTREAM_REPO (owner/repo) required for release model."
  log "Checking latest stable release of $UPSTREAM_REPO"
  LATEST="$(curl -fsSL -H "Authorization: Bearer $GH_TOKEN" \
            "https://api.github.com/repos/$UPSTREAM_REPO/releases/latest" \
            | jq -r '.tag_name')"
  [ -n "$LATEST" ] && [ "$LATEST" != "null" ] || die "could not resolve latest release of $UPSTREAM_REPO."
  RECORDED="$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)"
  log "recorded release: ${RECORDED:-<none>}   latest release: $LATEST"
  if [ "$LATEST" = "$RECORDED" ] && [ "$FORCE" -ne 1 ]; then
    log "Already on $LATEST — nothing to do."; exit 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN: upstream has a newer release ($LATEST). A real run would repackage + deploy it."
    exit 0
  fi
  if [ -x "$HERE/release-deploy.sh" ]; then
    scalingo_login
    UPSTREAM_TAG="$LATEST" "$HERE/release-deploy.sh"
    verify_live
    echo "$LATEST" > "$VERSION_FILE"
    configure_push_auth
    git add "$VERSION_FILE"
    git commit -m "Record deployed upstream release $LATEST" || true
    git push origin "${FORK_BRANCH:-HEAD}"
    log "DONE. ${MODULE_NAME:-module} updated to upstream release $LATEST and live."
  else
    die "new upstream release $LATEST available but no release-deploy.sh hook — a human must bump the pin. Production untouched."
  fi
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# SOURCE MODEL  (git fork tracks an upstream branch)
# ══════════════════════════════════════════════════════════════════════════════
[ -n "${UPSTREAM_BRANCH:-}" ] || die "UPSTREAM_BRANCH required for source model."
[ -n "${FORK_BRANCH:-}" ]     || die "FORK_BRANCH required for source model."

if ! git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
  if [ -f "$HERE/UPSTREAM_URL" ]; then
    git remote add "$UPSTREAM_REMOTE" "$(head -n1 "$HERE/UPSTREAM_URL")"
  else
    die "git remote '$UPSTREAM_REMOTE' not configured and no UPSTREAM_URL file."
  fi
fi

log "Fetching $UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
git fetch --quiet "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH"

UPSTREAM_SHA="$(git rev-parse "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH")"
RECORDED_SHA="$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)"
log "recorded upstream: ${RECORDED_SHA:-<none>}   latest upstream: $UPSTREAM_SHA"

if git merge-base --is-ancestor "$UPSTREAM_SHA" HEAD 2>/dev/null && [ "$FORCE" -ne 1 ]; then
  log "Already contains upstream $UPSTREAM_SHA — nothing to do."; exit 0
fi

# Clear stat-cache false positives, then ignore line-ending renormalization that
# .gitattributes (text=auto / eol=lf) produces on a fresh checkout.
git update-index -q --really-refresh >/dev/null 2>&1 || true
if [ -n "$(git status --porcelain)" ]; then
  git -c core.autocrlf=false -c core.eol=lf add --renormalize . >/dev/null 2>&1 || true
  git stash --include-untracked --quiet >/dev/null 2>&1 || true
fi
# A real deploy must never build atop genuine uncommitted edits; dry-run does all
# merge work on a throwaway branch it aborts, so a pristine-CI tree is always safe.
if [ "$DRY_RUN" -ne 1 ] && [ -n "$(git status --porcelain)" ]; then
  die "working tree dirty — commit/stash first."
fi
git checkout --quiet "$FORK_BRANCH"

# ── dry-run trial merge ───────────────────────────────────────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
  TRIAL="artha-trial-$(date +%s)"
  log "DRY-RUN: trial-merging upstream onto $TRIAL"
  git checkout --quiet -b "$TRIAL"
  cleanup_trial() { git merge --abort 2>/dev/null || true; git checkout --quiet "$FORK_BRANCH"; git branch -D "$TRIAL" 2>/dev/null || true; }
  trap cleanup_trial EXIT
  if ! git merge --no-edit --no-ff "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" >/dev/null 2>&1; then
    git merge --abort 2>/dev/null || true
    die "DRY-RUN: merge CONFLICT against upstream $UPSTREAM_SHA — needs a human. Production untouched."
  fi
  bash "$HERE/verify-rebrand.sh"
  if [ -n "${BUILD_CMD:-}" ]; then
    log "DRY-RUN: building assets to prove they compile against the merged tree"
    eval "$BUILD_CMD"
  fi
  log "DRY-RUN complete: upstream $UPSTREAM_SHA merges cleanly, rebrand intact${BUILD_CMD:+, assets build}. Safe to ship."
  exit 0
fi

# ── real merge ────────────────────────────────────────────────────────────────
log "Merging upstream $UPSTREAM_SHA into $FORK_BRANCH"
if ! git merge --no-edit --no-ff "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"; then
  git merge --abort 2>/dev/null || true
  die "merge CONFLICT against upstream $UPSTREAM_SHA — needs a human. Production untouched."
fi
bash "$HERE/verify-rebrand.sh" || die "rebrand drifted after merge — fix deploy/artha first. Production untouched."

# ── rebuild + commit assets ───────────────────────────────────────────────────
configure_push_auth
if [ -n "${BUILD_CMD:-}" ]; then
  log "Rebuilding assets"
  eval "$BUILD_CMD"
  [ -n "${BUILD_ARTIFACT_PATH:-}" ] && git add -f "$BUILD_ARTIFACT_PATH" 2>/dev/null || true
  git add -A
  git diff --cached --quiet || git commit -m "Rebuild assets after upstream merge ($UPSTREAM_SHA)"
fi

log "Pushing $FORK_BRANCH to origin"
git push origin "$FORK_BRANCH"

# ── deploy ────────────────────────────────────────────────────────────────────
if [ "$DEPLOY_METHOD" = "none" ]; then
  # Heavy monorepo/slug module: the upstream merge is clean and the Artha rebrand
  # is intact (gate passed) and the merged source is now pushed. The slug rebuild
  # is too heavy for a free runner, so we DO NOT auto-deploy — we open a tracking
  # issue and leave production untouched. A maintainer rebuilds + ships the slug.
  echo "$UPSTREAM_SHA" > "$VERSION_FILE"
  git add "$VERSION_FILE"
  git commit -m "Track verified upstream SHA $UPSTREAM_SHA (manual deploy pending)" || true
  git push origin "$FORK_BRANCH"
  if [ -n "${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
    GH_TOKEN="$GH_TOKEN" gh issue create \
      --title "Artha auto-update: upstream $UPSTREAM_SHA verified, ready to ship" \
      --body "Upstream merged cleanly into \`$FORK_BRANCH\` and the Artha rebrand survived (verify-rebrand passed). This is a heavy slug module (DEPLOY_METHOD=none) so the runner did not rebuild it. Rebuild the slug and deploy to \`$SCALINGO_APP\`. Production is unchanged." \
      --label artha-auto-update 2>/dev/null || true
  fi
  log "DONE (gate-only). ${MODULE_NAME:-module}: upstream $UPSTREAM_SHA merged + branding verified + pushed. Manual slug deploy pending — production untouched."
  exit 0
elif [ "$DEPLOY_METHOD" = "git-push" ]; then
  log "Deploy method git-push: Scalingo auto-deploy-on-push handles the rebuild."
else
  scalingo_login
  TARBALL="$(mktemp -d)/${SCALINGO_APP}.tar.gz"
  git archive --format=tar.gz --prefix="${ARCHIVE_PREFIX:-$SCALINGO_APP/}" HEAD -o "$TARBALL"
  log "Deploying archive ($(du -h "$TARBALL" | cut -f1)) to $SCALINGO_APP"
  scalingo --app "$SCALINGO_APP" deploy "$TARBALL" "artha-$(git rev-parse --short HEAD)-$(date +%s)"
fi

# ── migrate ───────────────────────────────────────────────────────────────────
if [ -n "${MIGRATE_CMD:-}" ]; then
  log "Running post-deploy migration"
  scalingo --app "$SCALINGO_APP" --region "$SCALINGO_REGION" run --silent "$MIGRATE_CMD"
fi

# ── verify + record ───────────────────────────────────────────────────────────
verify_live
echo "$UPSTREAM_SHA" > "$VERSION_FILE"
git add "$VERSION_FILE"
git commit -m "Record deployed upstream SHA $UPSTREAM_SHA"
git push origin "$FORK_BRANCH"
log "DONE. ${MODULE_NAME:-module} updated to upstream $UPSTREAM_SHA and live."
