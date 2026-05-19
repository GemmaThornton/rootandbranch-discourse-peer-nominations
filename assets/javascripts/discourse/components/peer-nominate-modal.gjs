import Component from "@glimmer/component";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DModal from "discourse/components/d-modal";
import { i18n } from "discourse-i18n";

export default class PeerNominateModal extends Component {
  @service siteSettings;

  @tracked badges = null;
  @tracked loadingBadges = true;
  @tracked selectedBadgeId = "";
  @tracked reason = "";
  @tracked submitting = false;
  @tracked submitted = false;

  constructor() {
    super(...arguments);
    this.loadBadges();
  }

  get profileUser() {
    return this.args.model.profileUser;
  }

  get isSelf() {
    return this.args.model.isSelf === true;
  }

  get usernameLabel() {
    return this.profileUser?.name || this.profileUser?.username;
  }

  get titleText() {
    return this.isSelf
      ? i18n("peer_nominations.modal.title_self")
      : i18n("peer_nominations.modal.title", { username: this.usernameLabel });
  }

  get introText() {
    return this.isSelf
      ? i18n("peer_nominations.modal.intro_self")
      : i18n("peer_nominations.modal.intro", { username: this.usernameLabel });
  }

  get reasonLabel() {
    return this.isSelf
      ? i18n("peer_nominations.modal.reason_label_self")
      : i18n("peer_nominations.modal.reason_label");
  }

  get reasonPlaceholder() {
    return this.isSelf
      ? i18n("peer_nominations.modal.reason_placeholder_self")
      : i18n("peer_nominations.modal.reason_placeholder", { username: this.usernameLabel });
  }

  get selectedBadge() {
    if (!this.selectedBadgeId || !this.badges) return null;
    const id = parseInt(this.selectedBadgeId, 10);
    return this.badges.find((b) => b.id === id) || null;
  }

  get minReasonLength() {
    return this.siteSettings.peer_nominations_min_reason_length || 50;
  }

  get maxReasonLength() {
    return this.siteSettings.peer_nominations_max_reason_length || 1000;
  }

  get reasonLength() {
    return this.reason.trim().length;
  }

  get reasonTooShort() {
    return this.reasonLength < this.minReasonLength;
  }

  get reasonTooLong() {
    return this.reasonLength > this.maxReasonLength;
  }

  get reasonCounterText() {
    if (this.reasonTooShort) {
      return i18n("peer_nominations.modal.reason_counter.too_short", {
        count: this.reasonLength,
        min: this.minReasonLength,
      });
    }
    if (this.reasonTooLong) {
      return i18n("peer_nominations.modal.reason_counter.too_long", {
        count: this.reasonLength,
        max: this.maxReasonLength,
      });
    }
    return i18n("peer_nominations.modal.reason_counter.ok", { count: this.reasonLength });
  }

  get submitDisabled() {
    if (this.submitting) return true;
    if (!this.selectedBadgeId) return true;
    if (this.reasonTooShort) return true;
    if (this.reasonTooLong) return true;
    return false;
  }

  async loadBadges() {
    try {
      const result = await ajax("/peer-nominations/nominatable-badges");
      this.badges = result.badges || [];
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.loadingBadges = false;
    }
  }

  @action
  updateBadgeSelection(event) {
    this.selectedBadgeId = event.target.value;
  }

  @action
  updateReason(event) {
    this.reason = event.target.value;
  }

  @action
  async submit() {
    if (this.submitDisabled) return;
    this.submitting = true;
    try {
      await ajax("/peer-nominations", {
        type: "POST",
        data: {
          username: this.profileUser.username,
          badge_id: parseInt(this.selectedBadgeId, 10),
          reason: this.reason.trim(),
        },
      });
      this.submitted = true;
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.submitting = false;
    }
  }

  @action
  close() {
    this.args.closeModal();
  }

  <template>
    <DModal
      @title={{this.titleText}}
      @closeModal={{@closeModal}}
      class="peer-nominate-modal"
    >
      <:body>
        {{#if this.submitted}}
          <div class="peer-nominate-success">
            <h3>{{i18n "peer_nominations.modal.success_title"}}</h3>
            <p>{{i18n "peer_nominations.modal.success_body"}}</p>
          </div>
        {{else}}
          <p class="peer-nominate-intro">{{this.introText}}</p>

          <div class="peer-nominate-field">
            <label for="peer-nominate-badge">
              {{i18n "peer_nominations.modal.badge_label"}}
            </label>
            {{#if this.loadingBadges}}
              <p class="peer-nominate-loading">{{i18n "loading"}}</p>
            {{else}}
              <select
                id="peer-nominate-badge"
                class="peer-nominate-badge-select"
                {{on "change" this.updateBadgeSelection}}
              >
                <option value="">
                  {{i18n "peer_nominations.modal.badge_placeholder"}}
                </option>
                {{#each this.badges as |badge|}}
                  <option value={{badge.id}}>{{badge.name}}</option>
                {{/each}}
              </select>
            {{/if}}

            {{#if this.selectedBadge.description}}
              <p class="peer-nominate-badge-description">
                <strong>{{i18n "peer_nominations.modal.badge_description_prefix"}}</strong>
                {{this.selectedBadge.description}}
              </p>
            {{/if}}
          </div>

          <div class="peer-nominate-field">
            <label for="peer-nominate-reason">
              {{this.reasonLabel}}
            </label>
            <textarea
              id="peer-nominate-reason"
              class="peer-nominate-reason"
              maxlength={{this.maxReasonLength}}
              placeholder={{this.reasonPlaceholder}}
              {{on "input" this.updateReason}}
            >{{this.reason}}</textarea>
            <p class="peer-nominate-counter
              {{if this.reasonTooShort 'is-too-short'}}
              {{if this.reasonTooLong 'is-too-long'}}">
              {{this.reasonCounterText}}
            </p>
          </div>
        {{/if}}
      </:body>

      <:footer>
        {{#if this.submitted}}
          <button
            type="button"
            class="btn btn-primary"
            {{on "click" this.close}}
          >
            {{i18n "peer_nominations.modal.success_close"}}
          </button>
        {{else}}
          <button
            type="button"
            class="btn btn-primary"
            disabled={{this.submitDisabled}}
            {{on "click" this.submit}}
          >
            {{#if this.submitting}}
              {{i18n "peer_nominations.modal.submitting"}}
            {{else}}
              {{i18n "peer_nominations.modal.submit"}}
            {{/if}}
          </button>
          <button
            type="button"
            class="btn btn-flat"
            {{on "click" this.close}}
          >
            {{i18n "peer_nominations.modal.cancel"}}
          </button>
        {{/if}}
      </:footer>
    </DModal>
  </template>
}
