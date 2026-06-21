# Artha Tables — thin white-label of Baserow, pinned to an upstream stable tag.
# Auto-update = bump this tag (see deploy/artha/update.sh + the GitHub Actions
# workflow). Branding is layered at build time by rebrand.sh.
FROM baserow/baserow:1.30.1

# Behaviour defaults for running behind the Scalingo proxy with external PG/Redis.
ENV BASEROW_DISABLE_PUBLIC_URL_CHECK=yes \
    BASEROW_AMOUNT_OF_WORKERS=1 \
    DONT_UPDATE_FORMULAS_AFTER_MIGRATION=yes \
    DISABLE_VOLUME_CHECK=yes \
    BASEROW_RUN_MINIMAL=yes \
    BASEROW_TRIGGER_SYNC_TEMPLATES_AFTER_MIGRATION=false \
    MIGRATE_ON_STARTUP=true

USER root
COPY assets /tmp/artha
COPY rebrand.sh /tmp/rebrand.sh
RUN bash /tmp/rebrand.sh && rm -rf /tmp/artha /tmp/rebrand.sh

COPY Caddyfile /baserow/caddy/Caddyfile
COPY run-artha.sh /baserow/run-artha.sh
RUN chmod +x /baserow/run-artha.sh

ENTRYPOINT []
CMD ["/bin/bash", "/baserow/run-artha.sh"]
