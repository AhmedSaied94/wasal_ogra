"""Pack pages (contracts/admin.md "Pack pages"): import, export, builds, reports, publishing,
rollback and the minimum app version.

Every action is a plain form posted to its own URL, after a confirmation page where the contract
asks for one. The services make the checks again, so a crafted request gets nothing more.
"""

from __future__ import annotations

from typing import Any

from django import forms
from django.contrib import admin, messages
from django.core.exceptions import PermissionDenied, ValidationError
from django.http import (
    Http404,
    HttpRequest,
    HttpResponse,
    HttpResponseNotAllowed,
    HttpResponseRedirect,
)
from django.template.response import TemplateResponse
from django.urls import URLPattern, path, reverse

from apps.content.admin.common import (
    MAX_LISTED_FINDINGS,
    attachment,
    is_staff,
    on_source,
    on_target,
)
from apps.content.admin.reports import report_sections
from apps.content.models import ContentAuditRecord, ContentPack
from apps.content.models.packs import CLIENT_VERSION_PATTERN, STORED, BuildState, Status
from apps.content.services import (
    build,
    exporter,
    files,
    importer,
    manifest,
    promote,
    publish,
    release,
)
from apps.content.services.rollback import ROLLBACK_PERMISSION, request_rollback

# While a build waits or runs, its page reloads itself: a meta refresh, so no script (CSP).
REFRESH_SECONDS = 5


class ImportForm(forms.Form):
    file = forms.FileField(help_text="A zip of the content/source layout, at most 4 MiB.")


class PromotionForm(forms.Form):
    code = forms.RegexField(
        promote.CODE,
        max_length=100,
        label="Promotion code",
        help_text="From the staging pack's page: core-<version>:<64 hex characters>.",
        error_messages={"invalid": "A promotion code looks like core-12:<64 hex characters>."},
    )


class MinClientVersionForm(forms.Form):
    min_client_version = forms.RegexField(
        CLIENT_VERSION_PATTERN,
        max_length=32,
        label="Minimum app version",
        help_text="MAJOR.MINOR.PATCH. Older apps get the newest pack they can read.",
    )


@admin.register(ContentPack)
class ContentPackAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    """Packs are read-only records. Their actions are buttons and forms on these pages."""

    change_list_template = "admin/content/contentpack/change_list.html"
    change_form_template = "admin/content/contentpack/change_form.html"
    list_display = (
        "__str__",
        "status",
        "build_state",
        "origin",
        "short_sha256",
        "size",
        "min_client_version",
        "created_at",
        "built_at",
        "published_at",
    )
    list_filter = ("status", "build_state", "origin")
    # The report has its own section, and the files are downloaded, never shown.
    exclude = ("file", "release_file", "validation_report")

    def has_module_permission(self, request: HttpRequest) -> bool:
        return is_staff(request)

    def has_view_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return is_staff(request)

    def has_add_permission(self, request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    @admin.display(description="sha256")
    def short_sha256(self, pack: ContentPack) -> str:
        return pack.sha256[:12]

    def get_urls(self) -> list[URLPattern]:
        wrap = self.admin_site.admin_view
        return [
            path("import/", wrap(self.import_view), name="content_contentpack_import"),
            path("build/", wrap(self.build_view), name="content_contentpack_build"),
            path("promote/", wrap(self.promote_view), name="content_contentpack_promote"),
            path(
                "<path:object_id>/publish/",
                wrap(self.publish_view),
                name="content_contentpack_publish",
            ),
            path(
                "<path:object_id>/rollback/",
                wrap(self.rollback_view),
                name="content_contentpack_rollback",
            ),
            path(
                "<path:object_id>/min-version/",
                wrap(self.min_version_view),
                name="content_contentpack_min_version",
            ),
            path(
                "<path:object_id>/download/",
                wrap(self.download_view),
                name="content_contentpack_download",
            ),
            path(
                "<path:object_id>/export/",
                wrap(self.export_view),
                name="content_contentpack_export",
            ),
            path(
                "export-current/",
                wrap(self.export_current_view),
                name="content_contentpack_export_current",
            ),
            *super().get_urls(),
        ]

    def changelist_view(self, request: HttpRequest, extra_context: Any = None) -> HttpResponse:
        user = request.user
        tools = {
            "can_import": on_source() and user.has_perm("content.import_content"),
            "can_export_current": on_source() and user.has_perm("content.export_content"),
            "can_build": on_source() and user.has_perm(build.BUILD_PERMISSION),
            "can_promote": on_target() and user.has_perm(promote.PROMOTE_PERMISSION),
        }
        return super().changelist_view(request, {**(extra_context or {}), **tools})

    def change_view(
        self,
        request: HttpRequest,
        object_id: str,
        form_url: str = "",
        extra_context: dict[str, Any] | None = None,
    ) -> HttpResponse:
        pack = self.get_object(request, object_id)
        context: dict[str, Any] = {}
        if pack is not None:
            context = {
                "report_sections": report_sections(pack.validation_report),
                "refresh_seconds": (
                    REFRESH_SECONDS
                    if pack.build_state in (BuildState.QUEUED, BuildState.RUNNING)
                    else None
                ),
                **self.pack_tools(request, pack),
            }
        return super().change_view(
            request, object_id, form_url, {**(extra_context or {}), **context}
        )

    def build_view(self, request: HttpRequest) -> HttpResponse:
        """POST only: queue a build and show its page (contracts/admin.md "Build a new pack")."""
        if request.method != "POST":
            return HttpResponseNotAllowed(["POST"])
        pack = build.request_build(request.user)  # type: ignore[arg-type]
        self.message_user(request, "The build is queued. This page shows its result when done.")
        return HttpResponseRedirect(reverse("admin:content_contentpack_change", args=[pack.pk]))

    def pack_tools(self, request: HttpRequest, pack: ContentPack) -> dict[str, Any]:
        """Which actions the page offers. Each view and service checks again."""
        user = request.user
        stored = pack.status in STORED
        return {
            "can_publish": on_source()
            and user.has_perm(publish.PUBLISH_PERMISSION)
            and pack.status == Status.VALIDATED,
            "can_rollback": on_source() and user.has_perm(ROLLBACK_PERMISSION) and stored,
            "can_change_min": user.has_perm(manifest.CHANGE_PERMISSION) and stored,
            "can_download": bool(pack.sha256) and pack.build_state != BuildState.QUEUED,
            "can_export": stored,
            "promotion_code": (release.promotion_code(pack) if on_source() and stored else None),
        }

    def pack_or_404(self, request: HttpRequest, object_id: str) -> ContentPack:
        pack: ContentPack | None = self.get_object(request, object_id)
        if pack is None:
            raise Http404("No such pack.")
        return pack

    def confirm(
        self, request: HttpRequest, pack: ContentPack, title: str, text: str, **extra: Any
    ) -> TemplateResponse:
        context = {
            **self.admin_site.each_context(request),
            "title": title,
            "text": text,
            "opts": self.model._meta,
            "original": pack,
            **extra,
        }
        return TemplateResponse(request, "admin/content/contentpack/confirm.html", context)

    def back_to(self, pack: ContentPack) -> HttpResponseRedirect:
        return HttpResponseRedirect(reverse("admin:content_contentpack_change", args=[pack.pk]))

    def publish_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        """Confirm, then queue the publish (contracts/admin.md "Publish")."""
        pack = self.pack_or_404(request, object_id)
        if not self.pack_tools(request, pack)["can_publish"]:
            raise PermissionDenied
        if request.method != "POST":
            text = (
                f"Publish {pack}? Apps get it within a minute. Its files are written once and "
                "never change."
            )
            return self.confirm(request, pack, f"Publish {pack}", text, button="Publish")
        try:
            publish.request_publish(pack, request.user)  # type: ignore[arg-type]
        except publish.PublishRefused as refused:
            self.message_user(request, str(refused), messages.ERROR)
        else:
            self.message_user(request, f"Publishing {pack}. This page shows the result.")
        return self.back_to(pack)

    def rollback_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        """Confirm, then queue a build of this pack's content as a new version (FR-028)."""
        pack = self.pack_or_404(request, object_id)
        if not self.pack_tools(request, pack)["can_rollback"]:
            raise PermissionDenied
        if request.method != "POST":
            text = f"Build {pack}'s content as a new version? You then publish it like any pack."
            return self.confirm(request, pack, f"Roll back to {pack}", text, button="Build it")
        draft = request_rollback(pack, request.user)  # type: ignore[arg-type]
        self.message_user(request, f"The rollback build of {pack} is queued.")
        return self.back_to(draft)

    def min_version_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        """A form with the new value, refused below the schema major's floor (FR-032)."""
        pack = self.pack_or_404(request, object_id)
        if not self.pack_tools(request, pack)["can_change_min"]:
            raise PermissionDenied
        form = MinClientVersionForm(
            request.POST or None, initial={"min_client_version": pack.min_client_version}
        )
        if request.method == "POST" and form.is_valid():
            value = form.cleaned_data["min_client_version"]
            try:
                manifest.change_min_client_version(pack, value, request.user)  # type: ignore[arg-type]
            except ValidationError as error:
                form.add_error("min_client_version", error)
            else:
                self.message_user(request, f"{pack} now needs app {value} or later.")
                return self.back_to(pack)
        text = (
            f"Apps below this version get the newest pack they can read instead. The lowest "
            f"allowed is {manifest.floor_for(pack)}."
        )
        return self.confirm(
            request, pack, f"Minimum app version of {pack}", text, form=form, button="Save"
        )

    def download_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        pack = self.pack_or_404(request, object_id)
        if not self.pack_tools(request, pack)["can_download"]:
            raise Http404("This pack has no file yet.")
        name = files.pack_file_name(files.version_of(pack))
        return attachment(bytes(pack.file), name, "application/gzip")

    def export_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        pack = self.pack_or_404(request, object_id)
        if not self.pack_tools(request, pack)["can_export"]:
            raise Http404("Only a published or retired pack can be exported.")
        data = exporter.export_pack(pack, request.user)  # type: ignore[arg-type]
        return attachment(data, exporter.zip_name(files.version_of(pack)))

    def promote_view(self, request: HttpRequest) -> HttpResponse:
        """Production only: the pasted code queues the promotion (contracts/pack-delivery.md)."""
        if not (on_target() and request.user.has_perm(promote.PROMOTE_PERMISSION)):
            raise PermissionDenied
        form = PromotionForm(request.POST or None)
        if request.method == "POST" and form.is_valid():
            code = form.cleaned_data["code"]
            try:
                promote.request_promotion(code, request.user)  # type: ignore[arg-type]
            except promote.PromotionRefused as refused:
                form.add_error("code", str(refused))
            else:
                self.message_user(
                    request, "The promotion is queued. The pack appears here once it is done."
                )
                return HttpResponseRedirect(reverse("admin:content_contentpack_changelist"))
        context = {
            **self.admin_site.each_context(request),
            "title": "Promote from staging",
            "text": "Production fetches the pack staging published and checks it again.",
            "opts": self.model._meta,
            "form": form,
            "button": "Promote",
        }
        return TemplateResponse(request, "admin/content/contentpack/confirm.html", context)

    def import_view(self, request: HttpRequest) -> HttpResponse:
        if not (on_source() and request.user.has_perm("content.import_content")):
            raise PermissionDenied
        form = ImportForm(request.POST or None, request.FILES or None)
        findings: list[Any] = []
        if request.method == "POST" and form.is_valid():
            upload = form.cleaned_data["file"]
            try:
                result = importer.import_zip(
                    upload.read(importer.MAX_UPLOAD + 1),
                    request.user,  # type: ignore[arg-type]
                )
            except importer.ImportRefused as refused:
                findings = refused.findings[:MAX_LISTED_FINDINGS]
                self.message_user(request, str(refused), messages.ERROR)
            else:
                self.message_user(
                    request,
                    f"Imported: {len(result.added)} added, {len(result.changed)} changed, "
                    f"{result.unchanged} unchanged.",
                )
                return HttpResponseRedirect(reverse("admin:content_contentpack_changelist"))
        context = {
            **self.admin_site.each_context(request),
            "title": "Import content",
            "opts": self.model._meta,
            "form": form,
            "findings": findings,
        }
        return TemplateResponse(request, "admin/content/contentpack/import.html", context)

    def export_current_view(self, request: HttpRequest) -> HttpResponse:
        data = exporter.export_current(request.user)  # type: ignore[arg-type]
        return attachment(data, exporter.zip_name())


@admin.register(ContentAuditRecord)
class ContentAuditRecordAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    """Read-only for everyone, superusers included (FR-038)."""

    list_display = ("at", "action", "outcome", "actor", "pack_id", "version")
    list_filter = ("action", "outcome", "actor", "version")

    def has_module_permission(self, request: HttpRequest) -> bool:
        return is_staff(request)

    def has_view_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return is_staff(request)

    def has_add_permission(self, request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False
