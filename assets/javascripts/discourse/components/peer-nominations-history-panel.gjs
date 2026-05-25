import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import avatar from "discourse/helpers/avatar";
import formatDate from "discourse/helpers/format-date";

// Admin-only "Peer nominations received" panel.
//
// Renders below the main bio on a user profile (via the
// user-profile-secondary outlet). Lazy-loads on construct via
// fetchGrants. Hidden entirely when the user has zero received grants
// — empty state would be noise on most profiles. Topic links work for
// closed AND archived topics (Discourse serves both, archived is just
// read-only); a small label tells the admin at a glance which state
// the original assessment topic is in.
//
// Toggle pattern note: we don't use the Glimmer `fn` helper to pass
// per-row args from {{#each}} click handlers — it silently fails in
// Discourse plugin connectors (see memory feedback_glimmer_fn_helper_pitfall).
// Instead each row carries a data-grant-id attribute and the click
// handler reads it off the event target.
export default class PeerNominationsHistoryPanel extends Component {
  @service router;

  @tracked grants = null;
  @tracked loading = true;
  @tracked errorMessage = null;
  @tracked expandedIds = new Set();

  constructor() {
    super(...arguments);
    this.fetchGrants();
  }

  get profileUser() {
    return this.args.profileUser;
  }

  get hasGrants() {
    return Array.isArray(this.grants) && this.grants.length > 0;
  }

  // While loading, render nothing so the panel doesn't briefly flash
  // empty for profiles with zero grants.
  get shouldRender() {
    return !this.loading && (this.hasGrants || this.errorMessage);
  }

  // Precompute per-row display state so the template stays simple and
  // we avoid invoking helpers-with-args inside {{#each}}.
  get displayGrants() {
    return (this.grants || []).map((g) => {
      let topicLabel = null;
      if (g?.topic?.archived) topicLabel = "archived";
      else if (g?.topic?.closed) topicLabel = "closed";
      return {
        ...g,
        isExpanded: this.expandedIds.has(g.id),
        topicLabel,
        toggleLabel: this.expandedIds.has(g.id)
          ? "Hide nomination details"
          : "Show nomination details",
      };
    });
  }

  @action
  async fetchGrants() {
    const userId = this.profileUser?.id;
    if (!userId) {
      this.loading = false;
      return;
    }
    try {
      const data = await ajax(
        `/peer-nominations/admin/users/${userId}/received`
      );
      this.grants = data?.grants || [];
    } catch (err) {
      this.errorMessage =
        err?.jqXHR?.responseJSON?.errors?.[0] ||
        "Could not load peer-nomination history.";
      popupAjaxError(err);
    } finally {
      this.loading = false;
    }
  }

  @action
  handleToggleClick(event) {
    const button = event.target.closest("[data-grant-id]");
    if (!button) return;
    const grantId = parseInt(button.getAttribute("data-grant-id"), 10);
    if (!grantId) return;
    const next = new Set(this.expandedIds);
    if (next.has(grantId)) {
      next.delete(grantId);
    } else {
      next.add(grantId);
    }
    this.expandedIds = next;
  }

  <template>
    {{#if this.shouldRender}}
      <section class="peer-nominations-history admin-only">
        <h3 class="peer-nominations-history__title">
          Peer nominations received
          <span class="peer-nominations-history__admin-tag">admin view</span>
        </h3>

        {{#if this.errorMessage}}
          <p class="peer-nominations-history__error">{{this.errorMessage}}</p>
        {{else}}
          <ul class="peer-nominations-history__list">
            {{#each this.displayGrants as |grant|}}
              <li class="peer-nominations-history__item">
                <div class="peer-nominations-history__row">
                  <div class="peer-nominations-history__nominator">
                    {{#if grant.nominator}}
                      <a href="/u/{{grant.nominator.username}}" class="peer-nominations-history__nominator-link">
                        {{avatar grant.nominator imageSize="small"}}
                        <span class="peer-nominations-history__nominator-name">
                          {{#if grant.nominator.name}}
                            {{grant.nominator.name}}
                          {{else}}
                            {{grant.nominator.username}}
                          {{/if}}
                        </span>
                      </a>
                    {{else}}
                      <em>(deleted user)</em>
                    {{/if}}
                  </div>
                  <div class="peer-nominations-history__badge">
                    nominated them for
                    <strong>{{grant.badge.name}}</strong>
                  </div>
                  <div class="peer-nominations-history__date">
                    {{formatDate grant.granted_at format="medium" leaveAgo="true"}}
                  </div>
                </div>

                <button
                  type="button"
                  class="peer-nominations-history__toggle btn-flat"
                  data-grant-id="{{grant.id}}"
                  {{on "click" this.handleToggleClick}}
                >
                  {{grant.toggleLabel}}
                </button>

                {{#if grant.isExpanded}}
                  <div class="peer-nominations-history__detail">
                    <blockquote class="peer-nominations-history__reason">
                      {{grant.reason}}
                    </blockquote>
                    {{#if grant.topic}}
                      <p class="peer-nominations-history__topic-link">
                        <a href={{grant.topic.url}}>
                          Open original nomination topic
                        </a>
                        {{#if grant.topicLabel}}
                          <span class="peer-nominations-history__topic-status">
                            ({{grant.topicLabel}})
                          </span>
                        {{/if}}
                      </p>
                    {{/if}}
                  </div>
                {{/if}}
              </li>
            {{/each}}
          </ul>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
