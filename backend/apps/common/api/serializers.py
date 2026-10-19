"""Response shapes for the OpenAPI schema (FR-012). The views build plain dicts."""

from rest_framework import serializers

CHECK_RESULTS = ["pass", "fail"]


class ErrorSerializer(serializers.Serializer[None]):
    code = serializers.CharField()
    message = serializers.CharField()
    details = serializers.DictField()


class ErrorEnvelopeSerializer(serializers.Serializer[None]):
    error = ErrorSerializer()


class LivenessSerializer(serializers.Serializer[None]):
    status = serializers.ChoiceField(choices=["ok"])
    release = serializers.CharField()


class ReadinessChecksSerializer(serializers.Serializer[None]):
    database = serializers.ChoiceField(choices=CHECK_RESULTS)
    cache = serializers.ChoiceField(choices=CHECK_RESULTS)
    migrations = serializers.ChoiceField(choices=CHECK_RESULTS)


class ReadinessSerializer(serializers.Serializer[None]):
    status = serializers.ChoiceField(choices=["ready"])
    checks = ReadinessChecksSerializer()
