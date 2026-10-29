# syntax=docker/dockerfile:1
# One image for the API, admin, worker, scheduler and ops jobs (research R2, R3; FR-024, FR-029).
# Build from the repository root, which holds tools/content_kit and tools/solver (B04 research
# R13, B05 research R16):
#   docker build -f backend/docker/Dockerfile --build-arg RELEASE=<sha> .
# The image holds no secret. Runtime values come from the environment (contracts/environment.md).

FROM ghcr.io/astral-sh/uv:0.13.1-python3.13-trixie-slim AS builder
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0 \
    UV_PROJECT_ENVIRONMENT=/opt/venv
WORKDIR /app
# The backend sits at /app, the toolkit at /tools/content_kit and the solver at /tools/solver, so
# the lock's `../tools/content_kit` and `../tools/solver` paths resolve. Both install non-editable
# into /opt/venv, rebuilt every time: uv's cache keeps a local package's build until its
# pyproject.toml changes, so a new schema or solver file would otherwise ship the old copy.
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=backend/uv.lock,target=uv.lock \
    --mount=type=bind,source=backend/pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=backend/.python-version,target=.python-version \
    --mount=type=bind,source=tools/content_kit,target=/tools/content_kit \
    --mount=type=bind,source=tools/solver,target=/tools/solver \
    uv sync --locked --no-dev --no-install-project \
        --reinstall-package wassal-content --reinstall-package wassal-solver
COPY backend /app

FROM python:3.13.16-slim-trixie AS runtime
LABEL org.opencontainers.image.source="https://github.com/AhmedSaied94/wasal_ogra"
# pg_dump and psql for the backup and restore drill jobs (FR-039, FR-041).
RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client-17 \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --system --uid 10001 --user-group --create-home app
# Strict by default: an env file that forgets DJANGO_SETTINGS_MODULE still gets prod's checks.
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DJANGO_SETTINGS_MODULE=config.settings.prod
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app /app

# Throwaway build values for this RUN only. DJANGO_DEBUG=false keeps the manifest storage, so the
# manifest that production serves from is written here (T010).
RUN DJANGO_SETTINGS_MODULE=config.settings.dev \
    DJANGO_DEBUG=false \
    WASSAL_READ_DOTENV=0 \
    SECRET_KEY=build-only-not-a-secret \
    AUTH_SIGNING_KEYS=build:build-only-not-a-signing-key-00000000000000000 \
    DATABASE_URL=postgres://build@build.invalid/build \
    CACHE_URL=locmem:// \
    CELERY_BROKER_URL=memory:// \
    API_HOST=build.invalid \
    ADMIN_HOST=build.invalid \
    CONTENT_ROLE=source \
    CONTENT_PACKS_PUBLIC_URL=http://build.invalid/packs/ \
    python manage.py collectstatic --noinput
RUN test -f /app/staticfiles/staticfiles.json

# The stack definition travels with the code (contracts/operations.md, deploy step 3).
RUN mkdir -p /app/deploy \
    && cp docker/compose.yml /app/deploy/ \
    && cp -r docker/env /app/deploy/env \
    && cp -r docker/postgres /app/deploy/postgres

# The packs directory's mount point (B04 contracts/environment.md). A named volume mounted here, as
# in dev, starts with this owner; on the hosts, provision.sh gives the bind-mounted directory the
# same uid.
RUN install -d -m 0755 -o app -g app /var/lib/wassal/packs

ARG RELEASE=dev
ENV RELEASE=$RELEASE
LABEL org.opencontainers.image.revision=$RELEASE

USER app
EXPOSE 8000
CMD ["gunicorn", "-c", "config/gunicorn.conf.py", "config.wsgi"]
