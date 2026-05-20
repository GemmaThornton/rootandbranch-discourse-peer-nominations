import Component from "@glimmer/component";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

// Renders at the top of the nominee's approval PM (a PM topic marked
// with peer_nom_decline_for_topic_id). Gives the nominee a "Decline
// this badge" button — POSTs to /peer-nominations/<original_topic_id>/decline-as-nominee.
// Server-side guard ensures only the actual nominee can succeed.
export default class PeerNominationDeclineBanner extends Component {
  @service dialog;
  @service toasts;
  @service currentUser;

  @tracked busy = false;
  @tracked declined = false;

  static shouldRender(args, { currentUser }) {
    if (!currentUser) return false;
    const topic = args.model;
    // Only on PM topics that we've stamped as offering decline. Field
    // value is the original nomination topic id.
    return !!topic?.peer_nom_decline_for_topic_id;
  }

  get topic() {
    return this.args.model;
  }

  get originalTopicId() {
    return this.topic?.peer_nom_decline_for_topic_id;
  }

  showToast(message) {
    if (!this.toasts) return;
    this.toasts.success({ data: { message } });
  }

  @action
  confirmDecline() {
    if (this.busy || this.declined) return;
    this.dialog.yesNoConfirm({
      message: i18n("peer_nominations.decline_banner.confirm_message"),
      didConfirm: () => this.doDecline(),
    });
  }

  async doDecline() {
    if (this.busy) return;
    this.busy = true;
    try {
      await ajax(`/peer-nominations/${this.originalTopicId}/decline-as-nominee`, { type: "POST" });
      this.declined = true;
      this.showToast(i18n("peer_nominations.decline_banner.declined_toast"));
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.busy = false;
    }
  }

  <template>
    <div class="peer-nomination-decline-banner">
      {{#if this.declined}}
        <p class="peer-nomination-decline-banner__done">
          {{i18n "peer_nominations.decline_banner.done_text"}}
        </p>
      {{else}}
        <p class="peer-nomination-decline-banner__hint">
          {{i18n "peer_nominations.decline_banner.hint_text"}}
        </p>
        <button
          type="button"
          class="btn btn-default peer-nomination-decline-banner__button"
          disabled={{this.busy}}
          {{on "click" this.confirmDecline}}
        >
          {{#if this.busy}}
            {{i18n "peer_nominations.decline_banner.button_busy"}}
          {{else}}
            {{i18n "peer_nominations.decline_banner.button"}}
          {{/if}}
        </button>
      {{/if}}
    </div>
  </template>
}
