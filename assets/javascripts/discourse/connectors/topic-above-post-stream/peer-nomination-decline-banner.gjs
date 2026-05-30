import Component from "@glimmer/component";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

// Renders at the top of the nominee's approval PM (a PM topic marked
// with peer_nom_decline_for_topic_id). Default behaviour if the
// nominee does nothing is to accept the badge publicly. The banner
// offers three explicit alternatives:
//
//   1. Decline the badge entirely (badge revoked, grant deleted).
//   2. Accept but limit visibility to Verified Socialists.
//   3. Accept but limit visibility to admins + key organisers.
//
// Each button is server-guarded so only the actual nominee can call
// the corresponding endpoint.
export default class PeerNominationDeclineBanner extends Component {
  @service dialog;
  @service toasts;
  @service currentUser;

  @tracked busy = false;
  @tracked resolution = null; // null | "declined" | "vs_only" | "admin_only"

  static shouldRender(args, { currentUser }) {
    if (!currentUser) return false;
    const topic = args.model;
    return !!topic?.peer_nom_decline_for_topic_id;
  }

  get topic() {
    return this.args.model;
  }

  get originalTopicId() {
    return this.topic?.peer_nom_decline_for_topic_id;
  }

  get doneText() {
    switch (this.resolution) {
      case "declined":
        return i18n("peer_nominations.decline_banner.done_text");
      case "vs_only":
        return i18n("peer_nominations.decline_banner.vs_only_done");
      case "admin_only":
        return i18n("peer_nominations.decline_banner.admin_only_done");
      default:
        return null;
    }
  }

  showToast(message) {
    if (!this.toasts) return;
    this.toasts.success({ data: { message } });
  }

  @action
  confirmDecline() {
    if (this.busy || this.resolution) return;
    this.dialog.yesNoConfirm({
      message: i18n("peer_nominations.decline_banner.confirm_message"),
      didConfirm: () => this.doDecline(),
    });
  }

  @action
  confirmAcceptVsOnly() {
    if (this.busy || this.resolution) return;
    this.dialog.yesNoConfirm({
      message: i18n("peer_nominations.decline_banner.vs_only_confirm"),
      didConfirm: () => this.doAcceptWithScope("vs_only", "vs_only_toast"),
    });
  }

  @action
  confirmAcceptAdminOnly() {
    if (this.busy || this.resolution) return;
    this.dialog.yesNoConfirm({
      message: i18n("peer_nominations.decline_banner.admin_only_confirm"),
      didConfirm: () => this.doAcceptWithScope("admin_only", "admin_only_toast"),
    });
  }

  async doDecline() {
    if (this.busy) return;
    this.busy = true;
    try {
      await ajax(`/peer-nominations/${this.originalTopicId}/decline-as-nominee`, { type: "POST" });
      this.resolution = "declined";
      this.showToast(i18n("peer_nominations.decline_banner.declined_toast"));
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.busy = false;
    }
  }

  async doAcceptWithScope(scope, toastKey) {
    if (this.busy) return;
    this.busy = true;
    try {
      await ajax(
        `/peer-nominations/${this.originalTopicId}/accept-as-nominee-with-scope`,
        { type: "POST", data: { scope } }
      );
      this.resolution = scope;
      this.showToast(i18n(`peer_nominations.decline_banner.${toastKey}`));
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.busy = false;
    }
  }

  <template>
    <div class="peer-nomination-decline-banner">
      {{#if this.resolution}}
        <p class="peer-nomination-decline-banner__done">
          {{this.doneText}}
        </p>
      {{else}}
        <p class="peer-nomination-decline-banner__hint">
          {{i18n "peer_nominations.decline_banner.hint_text"}}
        </p>
        <div class="peer-nomination-decline-banner__buttons">
          <button
            type="button"
            class="btn btn-default peer-nomination-decline-banner__button"
            disabled={{this.busy}}
            {{on "click" this.confirmAcceptVsOnly}}
          >
            {{i18n "peer_nominations.decline_banner.vs_only_button"}}
          </button>
          <button
            type="button"
            class="btn btn-default peer-nomination-decline-banner__button"
            disabled={{this.busy}}
            {{on "click" this.confirmAcceptAdminOnly}}
          >
            {{i18n "peer_nominations.decline_banner.admin_only_button"}}
          </button>
          <button
            type="button"
            class="btn btn-default peer-nomination-decline-banner__button peer-nomination-decline-banner__button--decline"
            disabled={{this.busy}}
            {{on "click" this.confirmDecline}}
          >
            {{#if this.busy}}
              {{i18n "peer_nominations.decline_banner.button_busy"}}
            {{else}}
              {{i18n "peer_nominations.decline_banner.button"}}
            {{/if}}
          </button>
        </div>
      {{/if}}
    </div>
  </template>
}
