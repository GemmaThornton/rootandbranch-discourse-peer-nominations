import Component from "@glimmer/component";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DModal from "discourse/components/d-modal";
import { i18n } from "discourse-i18n";

export default class PeerDeclineModal extends Component {
  @tracked reason = "";
  @tracked submitting = false;

  get topicId() {
    return this.args.model.topicId;
  }

  @action
  updateReason(event) {
    this.reason = event.target.value;
  }

  @action
  async confirm() {
    if (this.submitting) return;
    this.submitting = true;
    try {
      await ajax(`/peer-nominations/${this.topicId}/decline`, {
        type: "POST",
        data: { decline_reason: this.reason.trim() },
      });
      this.args.model.onDeclined?.();
      this.args.closeModal();
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.submitting = false;
    }
  }

  @action
  cancel() {
    this.args.closeModal();
  }

  <template>
    <DModal
      @title={{i18n "peer_nominations.admin_panel.decline_modal_title"}}
      @closeModal={{@closeModal}}
      class="peer-decline-modal"
    >
      <:body>
        <p>{{i18n "peer_nominations.admin_panel.decline_modal_intro"}}</p>
        <label for="peer-decline-reason">
          {{i18n "peer_nominations.admin_panel.decline_reason_label"}}
        </label>
        <textarea
          id="peer-decline-reason"
          class="peer-decline-reason"
          maxlength="500"
          placeholder={{i18n "peer_nominations.admin_panel.decline_reason_placeholder"}}
          {{on "input" this.updateReason}}
        >{{this.reason}}</textarea>
      </:body>

      <:footer>
        <button
          type="button"
          class="btn btn-danger"
          disabled={{this.submitting}}
          {{on "click" this.confirm}}
        >
          {{#if this.submitting}}
            {{i18n "peer_nominations.admin_panel.decline_confirm_busy"}}
          {{else}}
            {{i18n "peer_nominations.admin_panel.decline_confirm"}}
          {{/if}}
        </button>
        <button
          type="button"
          class="btn btn-flat"
          {{on "click" this.cancel}}
        >
          {{i18n "peer_nominations.admin_panel.decline_cancel"}}
        </button>
      </:footer>
    </DModal>
  </template>
}
