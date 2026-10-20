"""The manifest's shape for the OpenAPI schema (contracts/api.md). It must equal
`manifest.schema.json` field for field, which `test_manifest` checks."""

from rest_framework import serializers

PACK_ID_PATTERN = r"^[a-z][a-z0-9_]{1,31}$"
URL_PATTERN = r"^https?://"
SHA256_PATTERN = r"^[0-9a-f]{64}$"
CLIENT_VERSION_PATTERN = r"^[0-9]+\.[0-9]+\.[0-9]+$"
MAX_PACKS = 5


class ContentManifestPackSerializer(serializers.Serializer[None]):
    pack_id = serializers.RegexField(PACK_ID_PATTERN)
    version = serializers.IntegerField(min_value=1)
    url = serializers.RegexField(URL_PATTERN)
    sha256 = serializers.RegexField(SHA256_PATTERN)
    size = serializers.IntegerField(min_value=1)
    min_client_version = serializers.RegexField(CLIENT_VERSION_PATTERN)

    class Meta:
        ref_name = "ContentManifestPack"


class ContentManifestSerializer(serializers.Serializer[None]):
    version = serializers.IntegerField(min_value=0)
    packs = serializers.ListField(
        child=ContentManifestPackSerializer(), min_length=0, max_length=MAX_PACKS
    )

    class Meta:
        ref_name = "ContentManifest"
