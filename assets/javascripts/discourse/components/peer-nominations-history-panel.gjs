import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import avatar from "discourse/helpers/avatar";
import formatDate from "discourse/helpers/format-date";

// Renders the list of peer-nomination grants received by a member.
//
// Pure content — no title chrome, no section/card wrapper. The caller
// (currently PeerNominationsHistoryModal) supplies framing. Receives
// the already-fetched grants array via @grants — keeps the component
// dumb and the fetching responsibility on whoever opens the view.
//
// Toggle pattern note: we don't use the Glimmer `fn` helper to pass
// per-row args from {{#each}} click handlers — it silently fails in
// Discourse plugin connectors (see memory feedback_glimmer_fn_helper_pitfall).
// Each row carries a data-grant-id attribute; the click handler reads
// it off the event target.
export default class PeerNominationsHistoryPanel extends Component {
  @tracked expandedIds = new Set();

  get hasGrants() {
    return Array.isArray(this.args.grants) && this.args.grants.length > 0;
  }

  // Precompute per-row display state so the template stays simple and
  // we avoid invoking helpers-with-args inside {{#each}}.
  get displayGrants() {
    return (this.args.grants || []).map((g) => {
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
    {{#if this.hasGrants}}
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
    {{else}}
      <p class="peer-nominations-history__empty">
        This member hasn't received any peer nominations yet.
      </p>
    {{/if}}
  </template>
}
