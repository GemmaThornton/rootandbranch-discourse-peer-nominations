import Component from "@glimmer/component";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import PeerDeclineModal from "../../components/peer-decline-modal";

// Reads the peer_nomination block from the topic JSON (added by the
// add_to_serializer(:topic_view, :peer_nomination) hook in plugin.rb).
// Only renders for admins/moderators on topics in a peer-nomination state.
//
// For "Known Lefty" topics, also shows two extra buttons:
//   - Add to Verified Socialists (gives access to National Organising category)
//   - Add to <District> Verified Socialists (GP) group
// These are independent of the badge approval — admins use their judgement
// based on how many Known Lefty grants the nominee has accumulated.
export default class PeerNominationAdminPanel extends Component {
  @service modal;
  @service currentUser;
  @service toasts;
  @service router;

  @tracked busy = false;
  @tracked nationalBusy = false;
  @tracked districtBusy = false;
  @tracked localState = null; // overrides server state after a click

  static shouldRender(args, { currentUser }) {
    if (!currentUser) return false;
    if (!currentUser.admin && !currentUser.moderator) return false;
    const peer = args.model?.peer_nomination;
    if (!peer || !peer.state) return false;
    return true;
  }

  get topic() {
    return this.args.model;
  }

  get peer() {
    return this.topic?.peer_nomination;
  }

  get currentState() {
    return this.localState || this.peer?.state;
  }

  get isUnderReview() {
    return this.currentState === "under-review";
  }

  get isApproved() {
    return this.currentState === "approved";
  }

  get isDeclined() {
    return this.currentState === "declined";
  }

  get isProperLefty() {
    return this.peer?.badge_name === "Known Lefty";
  }

  get knownLeftyGrantCount() {
    return this.peer?.known_lefty_grant_count ?? 0;
  }

  get stateLabel() {
    if (this.isApproved) {
      return i18n("peer_nominations.admin_panel.state_approved", {
        date: this.formatDate(this.peer?.resolved_at),
      });
    }
    if (this.isDeclined) {
      return i18n("peer_nominations.admin_panel.state_declined", {
        date: this.formatDate(this.peer?.resolved_at),
      });
    }
    return i18n("peer_nominations.admin_panel.state_under_review");
  }

  formatDate(value) {
    if (!value) return "";
    try {
      return new Date(value).toLocaleDateString();
    } catch (e) {
      return "";
    }
  }

  showToast(messageKey, opts = {}) {
    if (!this.toasts) return;
    const message = opts.message || i18n(messageKey, opts.interpolate || {});
    this.toasts.success({ data: { message } });
  }

  @action
  async approve() {
    if (this.busy) return;
    this.busy = true;
    try {
      await ajax(`/peer-nominations/${this.topic.id}/approve`, { type: "POST" });
      this.localState = "approved";
      this.showToast("peer_nominations.admin_panel.approved_toast");
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.busy = false;
    }
  }

  @action
  openDecline() {
    this.modal.show(PeerDeclineModal, {
      model: {
        topicId: this.topic.id,
        onDeclined: () => {
          this.localState = "declined";
          this.showToast("peer_nominations.admin_panel.declined_toast");
        },
      },
    });
  }

  @action
  async addToNationalGroup() {
    if (this.nationalBusy) return;
    this.nationalBusy = true;
    try {
      const result = await ajax(`/peer-nominations/${this.topic.id}/add-nominee-to-national-group`, { type: "POST" });
      const key = result.status === "already"
        ? "peer_nominations.admin_panel.national_already_toast"
        : "peer_nominations.admin_panel.national_added_toast";
      this.showToast(key, { interpolate: { group: result.label } });
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.nationalBusy = false;
    }
  }

  @action
  async addToDistrictGroup() {
    if (this.districtBusy) return;
    this.districtBusy = true;
    try {
      const result = await ajax(`/peer-nominations/${this.topic.id}/add-nominee-to-district-group`, { type: "POST" });
      const key = result.status === "already"
        ? "peer_nominations.admin_panel.district_already_toast"
        : "peer_nominations.admin_panel.district_added_toast";
      this.showToast(key, { interpolate: { group: result.label } });
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.districtBusy = false;
    }
  }

  <template>
    <div class="peer-nomination-admin-panel">
      <h3 class="peer-nomination-admin-panel__title">
        {{i18n "peer_nominations.admin_panel.title"}}
      </h3>
      <p class="peer-nomination-admin-panel__state">{{this.stateLabel}}</p>

      {{#if this.isUnderReview}}
        <div class="peer-nomination-admin-panel__actions">
          <button
            type="button"
            class="btn btn-primary"
            disabled={{this.busy}}
            {{on "click" this.approve}}
          >
            {{#if this.busy}}
              {{i18n "peer_nominations.admin_panel.approve_button_busy"}}
            {{else}}
              {{i18n "peer_nominations.admin_panel.approve_button"}}
            {{/if}}
          </button>
          <button
            type="button"
            class="btn btn-danger"
            disabled={{this.busy}}
            {{on "click" this.openDecline}}
          >
            {{i18n "peer_nominations.admin_panel.decline_button"}}
          </button>
        </div>
      {{/if}}

      {{#if this.isProperLefty}}
        <div class="peer-nomination-admin-panel__proper-lefty">
          <p class="peer-nomination-admin-panel__count">
            {{i18n "peer_nominations.admin_panel.known_lefty.grant_count" count=this.knownLeftyGrantCount}}
          </p>
          <p class="peer-nomination-admin-panel__group-hint">
            {{i18n "peer_nominations.admin_panel.known_lefty.group_hint"}}
          </p>
          <div class="peer-nomination-admin-panel__actions">
            <button
              type="button"
              class="btn btn-default"
              disabled={{this.nationalBusy}}
              {{on "click" this.addToNationalGroup}}
            >
              {{#if this.nationalBusy}}
                {{i18n "peer_nominations.admin_panel.known_lefty.national_button_busy"}}
              {{else}}
                {{i18n "peer_nominations.admin_panel.known_lefty.national_button"}}
              {{/if}}
            </button>
            <button
              type="button"
              class="btn btn-default"
              disabled={{this.districtBusy}}
              {{on "click" this.addToDistrictGroup}}
            >
              {{#if this.districtBusy}}
                {{i18n "peer_nominations.admin_panel.known_lefty.district_button_busy"}}
              {{else}}
                {{i18n "peer_nominations.admin_panel.known_lefty.district_button"}}
              {{/if}}
            </button>
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}
