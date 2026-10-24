"""The project-owned staff account (FR-017, data-model "accounts.User")."""

import pytest
from django.conf import settings
from django.contrib.auth import get_user_model, password_validation
from django.core.exceptions import FieldDoesNotExist, ValidationError
from django.db import connection
from django.db.migrations.loader import MigrationLoader
from django.db.utils import IntegrityError

from apps.accounts.models import User


def test_auth_user_model_is_project_owned() -> None:
    assert settings.AUTH_USER_MODEL == "accounts.User"
    assert get_user_model() is User


@pytest.mark.parametrize("name", ["email", "first_name", "last_name"])
def test_no_personal_data_fields(name: str) -> None:
    with pytest.raises(FieldDoesNotExist):
        User._meta.get_field(name)


@pytest.mark.django_db
def test_id_is_uuid7() -> None:
    user = User.objects.create_user("ahmed", "a-long-enough-password-1")
    assert user.id.version == 7


@pytest.mark.django_db
def test_username_is_lowercased_on_save() -> None:
    user = User.objects.create_user("Ahmed.S", "a-long-enough-password-1")
    user.refresh_from_db()
    assert user.username == "ahmed.s"


@pytest.mark.django_db
def test_username_is_unique() -> None:
    User.objects.create_user("ahmed", "a-long-enough-password-1")
    with pytest.raises(IntegrityError):
        User.objects.create_user("AHMED", "a-long-enough-password-1")


@pytest.mark.parametrize("name", ["ab", "a" * 151, "ahmed saied", "ahmed!"])
def test_invalid_usernames_rejected(name: str) -> None:
    user = User(username=name)
    user.set_password("a-long-enough-password-1")
    with pytest.raises(ValidationError) as excinfo:
        user.full_clean(validate_unique=False)
    assert "username" in excinfo.value.message_dict


@pytest.mark.parametrize("name", ["abc", "a.b-c_9", "x" * 150])
def test_valid_usernames_accepted(name: str) -> None:
    user = User(username=name)
    user.set_password("a-long-enough-password-1")
    user.full_clean(validate_unique=False)


@pytest.mark.parametrize(
    "password",
    [
        "shortpass01",  # 11 characters
        "password1234",  # common
        "123456789012345",  # numeric only
        "ahmedsaied-account",  # similar to the username
    ],
)
def test_weak_passwords_rejected(password: str) -> None:
    user = User(username="ahmedsaied")
    with pytest.raises(ValidationError):
        password_validation.validate_password(password, user)


@pytest.mark.django_db
def test_defaults() -> None:
    user = User.objects.create_user("ahmed", "a-long-enough-password-1")
    assert user.is_staff is False
    assert user.is_superuser is False
    assert user.is_active is True
    assert user.date_joined is not None


@pytest.mark.django_db
def test_create_superuser() -> None:
    user = User.objects.create_superuser("root.user", "a-long-enough-password-1")
    assert user.is_staff
    assert user.is_superuser


@pytest.mark.django_db
def test_user_comes_from_the_initial_migration_with_uuid_primary_key() -> None:
    """AUTH_USER_MODEL is created by 0001 and no later migration touches it (B02 adds players)."""
    loader = MigrationLoader(connection)
    migrations = {
        name: migration
        for (app, name), migration in loader.disk_migrations.items()
        if app == "accounts"
    }
    assert min(migrations) == "0001_initial"
    for name, migration in migrations.items():
        if name != "0001_initial":
            touched = {
                getattr(op, "model_name", getattr(op, "name", "")) for op in migration.operations
            }
            assert "user" not in {str(model).lower() for model in touched}, name
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT data_type FROM information_schema.columns "
            "WHERE table_name = %s AND column_name = %s",
            ["accounts_user", "id"],
        )
        assert cursor.fetchone() == ("uuid",)
