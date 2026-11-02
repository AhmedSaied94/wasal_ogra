"""The `GET /v1/offers` response (B10 contracts/api.md). No price, ever."""

from __future__ import annotations

from rest_framework import serializers


class OfferProductSerializer(serializers.Serializer[None]):
    product_id = serializers.CharField()
    kind = serializers.CharField()
    bonat = serializers.IntegerField()
    bonus_bonat = serializers.IntegerField()
    entitlement = serializers.CharField(allow_null=True)
    best_value = serializers.BooleanField()


class CatalogOfferSerializer(serializers.Serializer[None]):
    offer_id = serializers.CharField()
    kind = serializers.CharField()
    product_id = serializers.CharField()
    ends_at = serializers.DateTimeField(allow_null=True)


class OffersSerializer(serializers.Serializer[None]):
    server_time = serializers.DateTimeField()
    products = OfferProductSerializer(many=True)
    offers = CatalogOfferSerializer(many=True)
