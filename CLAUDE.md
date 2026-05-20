# CLAUDE.md — `rootandbranch-discourse-peer-nominations`

This repository contains the Peer Nominations plugin for the Root & Branch Discourse forum. Read these rules before doing any work in this repo.

## STRICT RULES — NO EXCEPTIONS

These are inherited from the wider Root & Branch infrastructure rules. They apply equally to plugin development.

- NEVER SSH into any production or staging server directly.
- NEVER use SCP, rsync, or any direct file transfer to any server.
- NEVER run `./launcher` commands directly on any server.
- NEVER modify the production database directly.
- NEVER test plugin changes by manually copying files into a running Discourse container.
- NEVER disable or bypass email settings on production.
- NEVER change user passwords or credentials without explicit permission.
- ALL changes MUST be made as commits to this git repository.
- ALL changes MUST be tested on staging before production.
- Changes deploy through the CI/CD pipeline: `git push` → staging → production. There is no other path.

## Workflow

This plugin follows the same branching and deployment workflow as the other Root & Branch plugin repos:

1. Create a feature branch from `next`:
   ```
   git checkout next
   git pull
   git checkout -b my-feature
   ```
2. Make changes, commit, push.
3. Open a PR into `next`. **Merging does not auto-deploy** — under the current model (forum PR #19, 2026-05-19) plugin deploys are triggered manually via the forum repo's Actions tab.
4. To ship to staging: in the **forum** repo on GitHub, Actions → **Deploy to Staging** → **Run workflow** → leave branch on `next` → green button. Verify on `http://rootandbranch-staging` (Tailscale).
5. PR from `next` into `main`, merge.
6. To ship to production: forum repo → Actions → **Deploy to Production** → **Run workflow**. Blue/green swap, zero downtime.

See `rootandbranch-forum/CLAUDE.md` for the canonical deploy playbook.

The plugin is installed in the forum by a `git clone` line in `containers/app.yml` in the `rootandbranch-forum` repo. If this is the first deploy of the plugin, that line must be added in a coordinated PR to the forum repo.

## Plugin-specific notes

### What this plugin does

Lets logged-in members at trust level 1+ nominate other members for badges. Nominations create discussion topics in an admin-only "Badge Nominations" category. One admin click approves (granting the badge) or declines (silently closing the topic). A nominator can only successfully cause one approved grant per (nominee, badge) pair — the unique index on `peer_nomination_grants` enforces this at the database level.

See README.md for full details.

### User-facing language

Always use "admins" in user-visible strings, locale files, error messages, and PMs. Never use "staff" in user-facing text — members of this forum aren't paid employees of anything, and "staff" creates the wrong impression. The Discourse internal group name `staff` is fine to reference in technical code (it's just the literal group name), but anything a user will read should say "admin" or "admins."

### Data model

This plugin owns exactly one new database table: `peer_nomination_grants`. Everything else (nominations themselves, approval state, metadata) lives in Discourse topics and topic custom fields. If you find yourself reaching for additional tables, stop and reconsider — the design intentionally minimises new state.

### Testing on staging

Staging is at `http://rootandbranch-staging` (only accessible via Tailscale). After a `next` merge, allow ~15 minutes for the staging rebuild to complete. You can watch the run in the Actions tab of the `rootandbranch-forum` repo. Do not attempt to expedite or bypass this.

### Secrets

This plugin does not need any secrets. If it ever does, they go in `app.yml` in the forum repo as `${VARIABLE_NAME}` placeholders, with the actual values set as GitHub Actions secrets. Never commit secrets to this repo or anywhere else.

### When things break

1. Check Uptime Kuma (`http://rootandbranch-monitoring:3001`) for forum health.
2. Check the failing repo's Actions tab for deploy errors.
3. Check Beszel (`http://rootandbranch-monitoring:8090`) for server resource issues.
4. Contact Jonny. Do NOT attempt to fix production directly. If a deploy fails and the forum is in a bad state, the blue/green architecture means the previous container should still be running — but recovery is Jonny's call, not yours.

## Repository layout

```
plugin.rb                          # Main plugin file, version, dependencies
config/
  routes.rb                        # Engine routes mounted at /peer-nominations
  settings.yml                     # Plugin settings, defaults
  locales/
    server.en.yml                  # Server-side strings (PMs, errors, topic body/title)
    client.en.yml                  # Client-side strings (button labels, modal text)
db/
  migrate/                         # peer_nomination_grants + nominatable-badges seed
app/
  models/peer_nomination_grant.rb  # The one new model
  controllers/peer_nominations/    # Create / approve / decline endpoints
  serializers/peer_nominations/    # Nominatable-badge serializer
lib/peer_nominations/              # Service objects
  engine.rb
  nomination_creator.rb            # Validates input, creates topic, sets custom fields
  approval_handler.rb              # Approve (grant + PMs + grants row) / Decline (close topic)
assets/
  javascripts/discourse/
    connectors/
      user-profile-controls/       # "Nominate for a badge" button
      topic-above-post-stream/     # Admin Approve/Decline panel
    components/                    # Nominate modal, Decline modal
  stylesheets/
    peer-nominations.scss
.github/workflows/                 # (none — deploys are triggered manually
                                   #  from the forum repo's Actions tab; see
                                   #  rootandbranch-forum/CLAUDE.md)
README.md
CLAUDE.md                          # This file
```

## When in doubt

Ask Gemma. The whole point of these strict rules is that "moving fast" on infrastructure has bitten people before. A 15-minute wait for a staging rebuild is always cheaper than a broken production forum.
