"""The "one current pack" invariant as a database check (data-model.md "Invariants").

A channel's `current` is its highest published pack, and with nothing published it is empty. The
check is deferred to commit, because a publish makes the new pack `published` and points the
channel at it in the same transaction, in either order.
"""

from django.db import migrations

CREATE = """
CREATE FUNCTION content_check_current_pack() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    chosen uuid;
    highest integer;
    current_ok boolean;
BEGIN
    SELECT c.current_id INTO chosen FROM content_contentchannel c WHERE c.pack_id = NEW.pack_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    SELECT max(p.version) INTO highest FROM content_contentpack p
     WHERE p.pack_id = NEW.pack_id AND p.status = 'published';
    IF chosen IS NULL THEN
        current_ok := highest IS NULL;
    ELSE
        current_ok := EXISTS (
            SELECT 1 FROM content_contentpack p
             WHERE p.id = chosen AND p.pack_id = NEW.pack_id
               AND p.status = 'published' AND p.version = highest
        );
    END IF;
    IF NOT current_ok THEN
        RAISE EXCEPTION 'content channel %: current must be the highest published pack', NEW.pack_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER content_current_pack_on_channel
    AFTER INSERT OR UPDATE ON content_contentchannel
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION content_check_current_pack();

CREATE CONSTRAINT TRIGGER content_current_pack_on_pack
    AFTER INSERT OR UPDATE OF status, version, pack_id ON content_contentpack
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION content_check_current_pack();
"""

DROP = """
DROP TRIGGER content_current_pack_on_pack ON content_contentpack;
DROP TRIGGER content_current_pack_on_channel ON content_contentchannel;
DROP FUNCTION content_check_current_pack();
"""


class Migration(migrations.Migration):
    dependencies = [("content", "0001_initial")]

    operations = [migrations.RunSQL(CREATE, DROP)]
