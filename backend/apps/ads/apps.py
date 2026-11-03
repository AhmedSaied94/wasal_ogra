"""The ads app: AdMob's server-side verification callback and the morning piggy's rewards (B07).

`ads` imports `accounts`, `economy` and `liveops`. `economy` imports only `ads.models` and
`ads.services.status`, which never import `economy` (B07 plan, "Architecture boundaries").
"""

from django.apps import AppConfig


class AdsConfig(AppConfig):
    name = "apps.ads"
    label = "ads"
    verbose_name = "Ads"
