"""The audit log is append-only in the database too (FR-038, data-model.md `ContentAuditRecord`).

`ContentAuditRecord.save()` and `delete()` already refuse, but a queryset `update()` or `delete()`,
a shell or raw SQL would not go through them. This trigger refuses every update and delete.
"""

from django.db import migrations

CREATE = """
CREATE FUNCTION content_audit_append_only() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'the content audit log is append-only'
        USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE TRIGGER content_audit_append_only
    BEFORE UPDATE OR DELETE ON content_contentauditrecord
    FOR EACH ROW EXECUTE FUNCTION content_audit_append_only();
"""

DROP = """
DROP TRIGGER content_audit_append_only ON content_contentauditrecord;
DROP FUNCTION content_audit_append_only();
"""


class Migration(migrations.Migration):
    dependencies = [("content", "0004_channel_and_schedules")]

    operations = [migrations.RunSQL(CREATE, DROP)]
