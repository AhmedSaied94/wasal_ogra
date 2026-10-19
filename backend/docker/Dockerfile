# syntax=docker/dockerfile:1
# One image for the API, admin, worker, scheduler and ops jobs (research R2, R3; FR-024, FR-029).
# Build from backend/: docker build -f docker/Dockerfile --build-arg RELEASE=<sha> .
# The image holds no secret. Runtime values come from the environment (contracts/environment.md).

FROM ghcr.io/astral-sh/uv:0.13.1-python3.13-trixie-slim AS builder
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0 \
    UV_PROJECT_ENVIRONMENT=/opt/venv
WORKDIR /app
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=.python-version,target=.python-version \
    uv sync --locked --no-dev --no-install-project
COPY . /app

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
    DATABASE_URL=postgres://build@build.invalid/build \
    CACHE_URL=locmem:// \
    CELERY_BROKER_URL=memory:// \
    API_HOST=build.invalid \
    ADMIN_HOST=build.invalid \
    python manage.py collectstatic --noinput
RUN test -f /app/staticfiles/staticfiles.json

# The stack definition travels with the code (contracts/operations.md, deploy step 3).
RUN mkdir -p /app/deploy \
    && cp docker/compose.yml /app/deploy/ \
    && cp -r docker/env /app/deploy/env \
    && cp -r docker/postgres /app/deploy/postgres

ARG RELEASE=dev
ENV RELEASE=$RELEASE
LABEL org.opencontainers.image.revision=$RELEASE

USER app
EXPOSE 8000
CMD ["gunicorn", "-c", "config/gunicorn.conf.py", "config.wsgi"]
