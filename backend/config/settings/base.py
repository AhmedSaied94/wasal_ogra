"""Settings shared by every environment (research R3, contracts/environment.md).

Every value comes from the environment through `config.env`, which refuses to start on a missing
or invalid value (FR-003). The leaf modules (`dev`, `test`, `staging`, `prod`) import this one.
"""

from __future__ import annotations

from datetime import timedelta

from kombu import Exchange, Queue

from apps.common.sentry import init_sentry
from config.env import BACKEND_DIR, Env, settings_name

env = Env(settings_name())
env.check_environment()

BASE_DIR = BACKEND_DIR
WASSAL_ENV = env.name
SECRET_KEY = env.secret_key()
DEBUG = env.boolean("DJANGO_DEBUG", default=False)
RELEASE = env.string("RELEASE", "dev")

# -- Roles and hostnames (backend §4, FR-042a) -----------------------------------------------------

ADMIN_ONLY = env.boolean("ADMIN_ONLY", default=False)
API_HOST = env.string("API_HOST")
ADMIN_HOST = env.string("ADMIN_HOST")
ROOT_URLCONF = "config.urls_admin" if ADMIN_ONLY else "config.urls"
# 127.0.0.1 and localhost serve the container health checks and the deploy's verify step.
ALLOWED_HOSTS = [ADMIN_HOST if ADMIN_ONLY else API_HOST, "127.0.0.1", "localhost"]
NUM_PROXIES = env.integer("NUM_PROXIES", default=1 if env.strict else 0)

# -- Applications ----------------------------------------------------------------------------------

INSTALLED_APPS = [
    "apps.accounts.admin_config.StaffAdminConfig",  # django.contrib.admin, OTP site as default
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "drf_spectacular",
    "django_celery_beat",
    "django_otp",
    "django_otp.plugins.otp_totp",
    "axes",
    "apps.common",
    "apps.accounts",
    "apps.content",
    # `economy` imports `progress`, never the reverse (B03 research R1).
    "apps.progress",
    "apps.economy",
]

# The request id comes first, so every line, the access line included, carries it (FR-036).
MIDDLEWARE = ["apps.common.middleware.RequestIdMiddleware"]
if not ADMIN_ONLY:
    MIDDLEWARE += ["apps.common.middleware.AccessLogMiddleware"]
MIDDLEWARE += [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django_otp.middleware.OTPMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "apps.common.middleware.DependencyUnavailableMiddleware",
]
if not ADMIN_ONLY:
    MIDDLEWARE += [
        "apps.common.middleware.NoStoreMiddleware",
        "apps.common.middleware.BodySizeLimitMiddleware",
    ]
MIDDLEWARE += ["axes.middleware.AxesMiddleware"]

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

# -- Data stores -----------------------------------------------------------------------------------

DATABASES = {"default": env.database()}
CACHES = {"default": env.cache()}
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"  # framework apps only; project apps use UUIDv7

# -- Accounts (FR-017, FR-022) ---------------------------------------------------------------------

AUTH_USER_MODEL = "accounts.User"
AUTHENTICATION_BACKENDS = [
    "axes.backends.AxesStandaloneBackend",
    "django.contrib.auth.backends.ModelBackend",
]
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
        "OPTIONS": {"min_length": 12},
    },
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

# Lockout: 5 failures per username or per client address within 15 min lock it for 15 min. The
# address is the one the throttle sees (behind the edge, the WireGuard peer's address).
AXES_FAILURE_LIMIT = 5
AXES_COOLOFF_TIME = timedelta(minutes=15)
AXES_LOCKOUT_PARAMETERS = ["username", "ip_address"]
AXES_RESET_ON_SUCCESS = True
AXES_HANDLER = "axes.handlers.database.AxesDatabaseHandler"
AXES_CLIENT_IP_CALLABLE = "apps.common.net.client_ip"
AXES_USERNAME_CALLABLE = "apps.accounts.auth.lockout_username"

# -- Time and language (FR-004) --------------------------------------------------------------------

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

# -- Requests and static files ---------------------------------------------------------------------

DATA_UPLOAD_MAX_MEMORY_SIZE = 524288  # backstop for the edge's 512 KB limit (FR-020)
STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}

# -- Player accounts and tokens (B02, specs/009-b02-accounts-auth/contracts/environment.md) --------

AUTH_SIGNING_KEYS = env.signing_keys(forbidden=SECRET_KEY)
_auth = env.auth()
AUTH_REFRESH_RETRY_SECONDS = _auth.retry_seconds
AUTH_MAX_SESSIONS_PER_PLAYER = _auth.max_sessions
AUTH_HTTP_TIMEOUT_SECONDS = _auth.http_timeout_seconds
GOOGLE_OAUTH_CLIENT_IDS = _auth.google_client_ids
GOOGLE_JWKS_URL = _auth.google_jwks_url
GOOGLE_KEYS_CACHE_SECONDS = _auth.google_keys_cache_seconds
# Fixed by the constitution ("Security & privacy"): access 15 min, refresh 30 days. Not settings.
ACCESS_TOKEN_LIFETIME = timedelta(minutes=15)
REFRESH_TOKEN_LIFETIME = timedelta(days=30)
# simplejwt's own reading of the tokens. apps.accounts.tokens signs and verifies through the
# AUTH_SIGNING_KEYS ring by `kid`; SIGNING_KEY is only its fallback. The token_blacklist app is not
# installed: sessions live in accounts.PlayerSession (B02 research R1, R3).
SIMPLE_JWT = {
    "ALGORITHM": "HS256",
    "SIGNING_KEY": AUTH_SIGNING_KEYS[0].key,
    "ACCESS_TOKEN_LIFETIME": ACCESS_TOKEN_LIFETIME,
    "REFRESH_TOKEN_LIFETIME": REFRESH_TOKEN_LIFETIME,
    "LEEWAY": 0,
    "USER_ID_FIELD": "id",
    "USER_ID_CLAIM": "sub",
    "TOKEN_TYPE_CLAIM": "token_type",
    "JTI_CLAIM": "jti",
    "AUTH_TOKEN_CLASSES": ("apps.accounts.tokens.PlayerAccessToken",),
    "UPDATE_LAST_LOGIN": False,
}

# -- API conventions (contracts/api.md, research R4) -----------------------------------------------

# Each limit is read on every request, so `None` (the `no_throttle` fixture) turns it off.
THROTTLE_ADDRESS_RATE: str | None = env.rate("THROTTLE_ADDRESS_RATE", "120/min")
THROTTLE_PLAYER_RATE: str | None = env.rate("THROTTLE_PLAYER_RATE", "120/min")
THROTTLE_ANONYMOUS_RATE: str | None = env.rate("THROTTLE_ANONYMOUS_RATE", "60/hour")
THROTTLE_REFRESH_RATE: str | None = env.rate("THROTTLE_REFRESH_RATE", "30/min")
THROTTLE_LINK_RATE: str | None = env.rate("THROTTLE_LINK_RATE", "10/min")
THROTTLE_SYNC_RATE: str | None = env.rate("THROTTLE_SYNC_RATE", "60/min")
REST_FRAMEWORK = {
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": ["apps.common.parsers.JSONParser"],
    # Every endpoint needs a player token and the client headers, and is limited per player,
    # unless its view opts out explicitly (B02 FR-019, FR-032, FR-034).
    "DEFAULT_AUTHENTICATION_CLASSES": ["apps.accounts.authentication.PlayerAuthentication"],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
        "apps.common.permissions.ClientHeaders",
    ],
    "DEFAULT_THROTTLE_CLASSES": [
        "apps.common.throttles.AddressRateThrottle",
        "apps.common.throttles.PlayerRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "address": THROTTLE_ADDRESS_RATE,
        "player": THROTTLE_PLAYER_RATE,
        "anonymous": THROTTLE_ANONYMOUS_RATE,
        "refresh": THROTTLE_REFRESH_RATE,
        "link": THROTTLE_LINK_RATE,
        "sync": THROTTLE_SYNC_RATE,
    },
    "NUM_PROXIES": NUM_PROXIES,
    "EXCEPTION_HANDLER": "apps.common.errors.exception_handler",
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
}

# The committed contracts/openapi.yaml is generated from ROOT_URLCONF, which is the API urlconf
# unless ADMIN_ONLY is set (FR-018).
SPECTACULAR_SETTINGS = {
    "TITLE": "wassal API",
    "VERSION": "1",
    "SERVE_INCLUDE_SCHEMA": False,
    "COMPONENT_SPLIT_REQUEST": True,
    # The three readiness checks share one choice set; name it once.
    "ENUM_NAME_OVERRIDES": {
        "CheckResultEnum": "apps.common.api.serializers.CHECK_RESULTS",
        "PlatformEnum": "apps.common.client.PLATFORMS",
        "ProviderEnum": "apps.accounts.api.serializers.PROVIDERS",
        "ResolveEnum": "apps.accounts.api.serializers.RESOLUTIONS",
    },
}

# -- Content pipeline (B04, specs/003-b04-content-pipeline/contracts/environment.md) ---------------

_content = env.content(default_packs_dir=BASE_DIR / "var" / "packs")
CONTENT_ROLE = _content.role
CONTENT_PACKS_DIR = _content.packs_dir
CONTENT_PACKS_PUBLIC_URL = _content.public_url
CONTENT_VERSION_FLOOR_URL = _content.floor_url
CONTENT_PROMOTION_SOURCE_URL = _content.promotion_url
CONTENT_SOLVER_STAGE = _content.solver_stage
CONTENT_MANIFEST_CACHE_SECONDS = _content.manifest_cache_seconds
CONTENT_HTTP_TIMEOUT_SECONDS = _content.http_timeout_seconds
CONTENT_INDEX_KEEP = _content.index_keep

# -- Economy, bootstrap and sync (B03, specs/010-b03-ledger-sync/contracts/environment.md) ---------

_economy = env.economy()
ECONOMY_FUEL_MAX = _economy.fuel_max
ECONOMY_FUEL_MAX_SUBSCRIBER = _economy.fuel_max_subscriber
ECONOMY_FUEL_REGEN_MINUTES = _economy.fuel_regen_minutes
ECONOMY_FUEL_REFILL_DAILY_CAP = _economy.fuel_refill_daily_cap
ECONOMY_FUEL_OVERDRAFT_PER_DAY = _economy.fuel_overdraft_per_day
ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP = _economy.traffic_jam_ads_per_trip
ECONOMY_NAME_MIN_LENGTH = _economy.name_min_length
ECONOMY_NAME_MAX_LENGTH = _economy.name_max_length
SYNC_GAME_TIMEZONE = _economy.game_timezone
SYNC_OP_RETENTION_DAYS = _economy.op_retention_days
SYNC_CONTENT_MAX_AGE_DAYS = _economy.content_max_age_days
SYNC_MIN_DURATION_PERCENT = _economy.min_duration_percent
SYNC_FAST_RUN_PERCENT = _economy.fast_run_percent
SYNC_TRIPS_PER_DAY_FLAG = _economy.trips_per_day_flag
SYNC_CLOCK_CLAMP_FLAG_MINUTES = _economy.clock_clamp_flag_minutes
SYNC_SESSION_GAP_MINUTES = _economy.session_gap_minutes
SYNC_COMEBACK_AWAY_DAYS = _economy.comeback_away_days
SYNC_COMEBACK_COOLDOWN_DAYS = _economy.comeback_cooldown_days
CLIENT_MIN_VERSION = _economy.client_min_version
CLIENT_LATEST_VERSION = _economy.client_latest_version

# -- Background tasks (FR-006, FR-007) -------------------------------------------------------------

CELERY_BROKER_URL = env.broker()
CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True
CELERY_TASK_DEFAULT_QUEUE = "default"
# Each queue gets its own exchange and routing key. A bare Queue(name) would share the default
# route, and every message would then land in all four queues.
CELERY_TASK_QUEUES = [
    Queue(name, Exchange(name, type="direct"), routing_key=name)
    for name in ("default", "purchases", "content", "push")
]
CELERY_TASK_IGNORE_RESULT = True
CELERY_TIMEZONE = "UTC"
CELERY_WORKER_HIJACK_ROOT_LOGGER = False
CELERY_BEAT_SCHEDULER = "django_celery_beat.schedulers:DatabaseScheduler"

# -- Operations ------------------------------------------------------------------------------------

SENTRY_DSN = env.secret("SENTRY_DSN", "", required_outside_dev=True)
SENTRY_TRACES_SAMPLE_RATE = env.number("SENTRY_TRACES_SAMPLE_RATE", 0.05, minimum=0.0, maximum=0.1)
HC_PING_HEARTBEAT_URL = env.secret("HC_PING_HEARTBEAT_URL", "", required_outside_dev=True)
LOG_LEVEL = env.string("LOG_LEVEL", "INFO")

# One JSON object per line on stdout; Docker's json-file driver rotates it (research R7).
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "filters": {"context": {"()": "apps.common.logging.ContextFilter"}},
    "formatters": {"json": {"()": "apps.common.logging.JsonLineFormatter"}},
    "handlers": {
        "stdout": {
            "class": "logging.StreamHandler",
            "stream": "ext://sys.stdout",
            "formatter": "json",
            "filters": ["context"],
        },
    },
    "root": {"handlers": ["stdout"], "level": LOG_LEVEL},
    "loggers": {
        # Django's defaults add plain-text handlers; everything goes through the JSON one.
        "django": {"handlers": [], "level": LOG_LEVEL, "propagate": True},
        "django.server": {"handlers": [], "propagate": True},
    },
}

init_sentry(
    SENTRY_DSN,
    environment=WASSAL_ENV,
    release=RELEASE,
    traces_sample_rate=SENTRY_TRACES_SAMPLE_RATE,
)
