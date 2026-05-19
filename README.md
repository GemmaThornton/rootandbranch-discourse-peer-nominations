# rootandbranch-discourse-peer-nominations

A Discourse plugin for the Root & Branch forum that lets members nominate each other for badges. Nominations are reviewed by admins before any badge is granted.

## What it does

- Members at trust level 1 or higher can nominate any other member for any badge marked as nominatable.
- Each nomination creates a discussion topic in an admin-only category. Admins can discuss, approve, or decline.
- On approval, the plugin grants the badge via Discourse's `BadgeGranter` service and PMs both the nominee (with the nominator's name and reason) and the nominator (confirmation).
- On decline, the topic is closed with the decline reason recorded for the internal record. No notifications are sent.
- All nominatable badges are configured as multiple-grant, so a member can collect endorsements from many different peers over time — but any one nominator can only successfully cause one grant per (nominee, badge) pair. This is enforced at the database level by a unique index.

## How it fits together

| Piece | Where it lives |
|------|----------------|
| Nomination | A topic in the configured "Badge Nominations" category |
| Nomination metadata (nominator, nominee, badge) | Topic custom fields |
| Approval / decline state | Topic state + `approved` / `declined` tags |
| Approved-grant tracking | `peer_nomination_grants` table |
| Which badges are nominatable | `nominatable` custom field on Badge |

The plugin owns exactly one new database table. Everything else reuses existing Discourse primitives.

## Installation

This plugin is deployed automatically as part of the Root & Branch Discourse infrastructure. The clone URL is added to `containers/app.yml` in the [`rootandbranch-forum`](https://github.com/jpaylor/rootandbranch-forum) repo.

If you're setting up a fresh Discourse instance and want to use this plugin standalone, add the following to your `app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/GemmaThornton/rootandbranch-discourse-peer-nominations.git
```

Then rebuild your Discourse container.

## Configuration

After installation:

1. Create a category called "Badge Nominations" and restrict it to the `staff` group (read + reply).
2. Add the tags `approved`, `declined`, and `under-review` to that category.
3. In Admin → Settings, find the `peer_nominations` settings and:
   - Set `peer_nominations_category_id` to the ID of the new category.
   - Adjust other settings as needed (trust level, rate limits, reason length).
   - Enable `peer_nominations_enabled`.
4. The set of nominatable badges is hardcoded in `plugin.rb` as the
   `PeerNominations::NOMINATABLE_BADGE_NAMES` constant. To add another
   badge to that set later, edit the constant (matched by exact `Badge.name`)
   and ship a plugin deploy. On the Root & Branch forum, the 9 admin-created
   badges (Local Signpost, Order Order!, The IT Crowd, Councillor,
   Crowd Pleaser, Doorstep Hero, Got the T Shirt, On It !, Rule-book Guru)
   are already in the list and have `multiple_grant=true` set automatically
   by the seed migration on first install.

(Earlier drafts stored "nominatable" as a Discourse Badge custom field, but
the Badge model in current Discourse doesn't expose `.custom_fields` at all
— so the list lives in code instead.)

## Settings

| Setting | Default | Purpose |
|---------|---------|---------|
| `peer_nominations_enabled` | false | Master switch. |
| `peer_nominations_category_id` | (empty) | Category ID for nomination topics. Must be admin-only. |
| `peer_nominations_min_trust_level` | 1 | Minimum TL required to submit a nomination. |
| `peer_nominations_rate_limit_count` | 3 | Max nominations a user can submit in the window. |
| `peer_nominations_rate_limit_window_days` | 7 | Rate limit window in days. |
| `peer_nominations_min_reason_length` | 50 | Minimum characters in a nomination reason. |
| `peer_nominations_max_reason_length` | 1000 | Maximum characters in a nomination reason. |

## Development

This plugin follows the Root & Branch git-only workflow. See `CLAUDE.md` for the strict rules. In short: never touch production directly, all changes go via PR → `next` (staging) → `main` + Release (production).

### Local development

Standard Discourse plugin development — clone into your local Discourse `plugins/` directory and restart the dev server.

## License

Private — internal use by Root & Branch only.
