# Contract: The Player Admin (FR-036, User Story 5)

On B01's OTP-protected admin site, on the admin hostname, which is reachable only over each host's
WireGuard network. Research R12.

## Access

| Who | Sees players | Can change |
| --- | --- | --- |
| Superuser | yes | the tester flag |
| Staff in the `player_support` group | yes | the tester flag |
| Other staff (for example B04's `content_author`, `content_publisher`) | no: no menu entry, `403` on the URLs | — |

The `player_support` group is created by migration `accounts/0003`, with these permissions:

- `accounts.view_player` and `accounts.change_player`;
- `accounts.view_device` and `accounts.view_identity`, which the inlines need.

`create_staff <name> --group player_support` (B01's command) adds a member.

## Player list

| Element | Value |
| --- | --- |
| Columns | `player_id`, status, platform, client version, tester, created, last seen |
| Search | Exact `player_id` (a full UUID). Partial ids and display names are not searchable. |
| Filters | status, platform, tester |
| Actions | none. Bulk delete is removed. |
| Add, delete | not allowed |

## Player page

| Section | Fields | Editable |
| --- | --- | --- |
| Account | `player_id`, status, display name, locale, country, platform, client version, driver level, created, last seen | no |
| Testing | `is_tester` | **yes** |
| Sign-in | Linked providers, by name and linked-at time. Live sessions: a count. | no |
| Devices (inline) | `device_id`, platform, app version, created, last seen | no |

- **Never shown:** tokens, the install id or its hash, provider subjects, session token ids.
- **Saving** writes Django's `LogEntry` (the admin's history) with the changed field. The tester
  flag is the only change possible (US5-2).
